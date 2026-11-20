#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../internal/common.sh"
load_hosts

sgx=$("${tf[@]}" output -raw enable_sgx)
for ip in "$client" "$proxy" "$target"; do
    for attempt in {1..30}; do
        if remote "$ip" "cloud-init status --wait && mkdir -p $base"; then
            break
        fi
        if [[ "$attempt" == 30 ]]; then
            echo "SSH or cloud-init failed on $ip" >&2
            exit 1
        fi
        sleep 5
    done
    tar -C "$root/internal" -cf - common.sh prepare-node.sh run-on-client.sh |
        remote "$ip" "tar -xf - -C $base"
done

# The orchestrator key is created on the client. Only its public key leaves it.
public_key=$(remote "$client" "umask 077; test -f $base/orchestrator_key ||
    ssh-keygen -q -t ed25519 -N '' -C codoh-orchestrator -f $base/orchestrator_key;
    ssh-keygen -y -f $base/orchestrator_key")
for ip in "$proxy" "$target"; do
    printf 'from="%s",restrict %s\n' "$client" "$public_key" | remote "$ip" \
        'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys;
        IFS= read -r entry; if ! grep -Fqx -- "$entry" ~/.ssh/authorized_keys; then
            printf "%s\n" "$entry" >> ~/.ssh/authorized_keys;
        fi'
done

remote "$client" "cat > $base/hosts.json" <<< "$hosts"
for role in target proxy client; do
    ip=$(jq -er --arg role "$role" '.[$role].ip' <<< "$hosts")
    remote "$ip" "bash $base/prepare-node.sh '$role' '$proxy' '$target' '$sgx'"
    if [[ "$role" != client ]]; then
        remote "$ip" "cat $base/$role-environment.txt" |
            remote "$client" "cat > $base/$role-environment.txt"
    fi
done
