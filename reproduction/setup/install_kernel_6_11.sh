#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../internal/common.sh"
load_hosts

kernel_package=${KERNEL_PACKAGE:-linux-generic-hwe-24.04}
sgx=$("${tf[@]}" output -raw enable_sgx)

for attempt in {1..30}; do
    if remote "$proxy" "cloud-init status --wait"; then
        break
    fi
    if [[ "$attempt" == 30 ]]; then
        echo "SSH or cloud-init failed on $proxy" >&2
        exit 1
    fi
    sleep 5
done

current_kernel=$(remote "$proxy" "uname -r")
if remote "$proxy" "dpkg --compare-versions '$current_kernel' ge 6.11"; then
    printf 'Proxy %s is already running kernel %s (>= 6.11).\n' "$proxy" "$current_kernel"
else
    printf 'Installing %s on proxy %s (current kernel: %s)...\n' "$kernel_package" "$proxy" "$current_kernel"
    old_boot_id=$(remote "$proxy" "cat /proc/sys/kernel/random/boot_id")
    remote "$proxy" "export DEBIAN_FRONTEND=noninteractive; sudo apt-get update && sudo apt-get install -y '$kernel_package'"
    remote "$proxy" "sudo reboot" || true

    printf 'Waiting for proxy %s to reboot...\n' "$proxy"
    for attempt in {1..60}; do
        sleep 5
        new_boot_id=$(remote "$proxy" "cat /proc/sys/kernel/random/boot_id" 2>/dev/null || true)
        if [[ -n "$new_boot_id" && "$new_boot_id" != "$old_boot_id" ]]; then
            break
        fi
        if [[ "$attempt" == 60 ]]; then
            echo "Timed out waiting for proxy $proxy to reboot." >&2
            exit 1
        fi
    done

    current_kernel=$(remote "$proxy" "uname -r")
    if ! remote "$proxy" "dpkg --compare-versions '$current_kernel' ge 6.11"; then
        printf 'Expected kernel >= 6.11 after reboot on %s, but got %s.\n' "$proxy" "$current_kernel" >&2
        exit 1
    fi
    printf 'Proxy %s booted into kernel %s.\n' "$proxy" "$current_kernel"
fi

if [[ "$sgx" == true ]]; then
    remote "$proxy" "sudo test -c /dev/sgx_enclave"
fi

# Refresh the recorded kernel line if prepare.sh was already run earlier.
remote "$proxy" "if [[ -f $base/proxy-environment.txt ]]; then
    { uname -a; tail -n +2 $base/proxy-environment.txt; } > $base/proxy-environment.txt.tmp &&
    mv $base/proxy-environment.txt.tmp $base/proxy-environment.txt
fi"
