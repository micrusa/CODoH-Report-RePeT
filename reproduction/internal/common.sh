# Shared operator and VM helpers. Sourcing this file performs no cloud operations.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

ARTIFACT_URL=https://github.com/etclab/codoh-artifact.git
ARTIFACT_REV=4fd30adbd237100399e8ea5a3ed6378196695346

fetch_artifact() {
    local destination=$1
    shift
    if [[ ! -d "$destination/.git" ]]; then
        git init "$destination"
        git -C "$destination" remote add origin "$ARTIFACT_URL"
    fi
    if ! git -C "$destination" cat-file -e "$ARTIFACT_REV^{commit}" 2>/dev/null; then
        git -C "$destination" fetch origin "$ARTIFACT_REV"
    fi
    git -C "$destination" checkout --detach "$ARTIFACT_REV"
    git -C "$destination" submodule update --init -- "$@"
}

load_hosts() {
    umask 077
    ssh_user=${BENCH_SSH_USER:-ubuntu}
    ssh_key=${BENCH_SSH_KEY:-$HOME/.ssh/id_rsa}
    [[ "$ssh_user" =~ ^[a-z_][a-z0-9_-]*$ && -r "$ssh_key" ]] || {
        echo "Set BENCH_SSH_USER and BENCH_SSH_KEY to the image login and private key." >&2
        exit 2
    }
    options=(-i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
    base="\$HOME/codoh-reproduction"
    tf=(terraform "-chdir=$root/terraform")
    hosts=$("${tf[@]}" output -json hosts)
    client=$(jq -er '.client.ip' <<< "$hosts")
    proxy=$(jq -er '.proxy.ip' <<< "$hosts")
    target=$(jq -er '.target.ip' <<< "$hosts")
}

remote() {
    local ip=$1
    shift
    ssh "${options[@]}" "$ssh_user@$ip" "$@"
}

new_run_id() {
    printf '%s-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
}

validate_run_id() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] || {
        echo "Provide the result folder name (up to 64 letters, digits, underscores or hyphens)." >&2
        return 2
    }
}

collect() {
    local id=$1
    local host=$client
    case "$id" in
        table[456]-*) host=$proxy ;;
    esac
    local output="$root/results/$id"
    local temporary
    mkdir -p "$root/results"
    temporary=$(mktemp -d "$root/results/.collect.XXXXXX")
    if remote "$host" "tar -C $base/artifact/repos/coredns/benchmark/results -czf - -- '$id'" \
        | tar -xzf - -C "$temporary"; then
        if [[ -e "$output" ]]; then
            rm -rf "$temporary"
            echo "Local run ID already exists." >&2
            return 1
        fi
        mv "$temporary/$id" "$output"
        rmdir "$temporary"
        printf '%s\n' "$output"
    else
        rm -rf "$temporary"
        return 1
    fi
}

run_microbench() {
    require_matplotlib
    local table=$1
    local id="table$table-$2-$(new_run_id)"
    local status=0
    printf 'Result folder: results/%s/\n' "$id"
    remote "$proxy" "bash -s -- '$table' '$id'" < "$root/internal/run-microbench.sh" || status=$?
    if (( status != 0 )); then
        collect "$id" || true
        return "$status"
    fi
    collect "$id"
    python3 "$root/analysis/plot-microbench.py" "$root/results/$id"
}

require_matplotlib() {
    if ! python3 -c 'import matplotlib' >/dev/null 2>&1; then
        echo "Install Matplotlib for your local python3 before running this experiment." >&2
        exit 1
    fi
}

run_benchmark() {
    local mode=$1
    local id=${2:-"$mode-e2e-$(new_run_id)"}
    local batch_size=${3:-10}
    local status=0
    printf 'Result folder: results/%s/\n' "$id"
    remote "$client" "bash $base/run-on-client.sh '$id' '$mode' '$batch_size'" || status=$?
    if (( status != 0 )); then
        collect "$id" || true
        return "$status"
    fi
    collect "$id"
}
