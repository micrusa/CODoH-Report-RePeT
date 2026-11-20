#!/usr/bin/env bash
set -euo pipefail
umask 077
role=$1
proxy_ip=$2
target_ip=$3
sgx=$4
base="$HOME/codoh-reproduction"
source "$base/common.sh"

export DEBIAN_FRONTEND=noninteractive
if [[ "$(id -u)" == 0 ]] && ! command -v sudo >/dev/null; then
    apt-get update
    apt-get install -y sudo
fi
sudo apt-get update
sudo apt-get install -y ca-certificates curl wget git build-essential pkg-config \
    openssl lsb-release dnsutils unzip python3 jq lsof psmisc iputils-ping
if [[ "$role" == client ]]; then
    sudo apt-get install -y gnuplot-nox ghostscript
fi

export PATH="/usr/local/go/bin:$PATH"
if [[ "$(go version 2>/dev/null || true)" != 'go version go1.25.1 linux/amd64' ]]; then
    download=$(mktemp -d)
    trap 'rm -rf "$download"' EXIT
    archive=go1.25.1.linux-amd64.tar.gz
    curl --fail --location --retry 3 -o "$download/$archive" "https://go.dev/dl/$archive"
    (cd "$download" && echo "7716a0d940a0f6ae8e1f3b3f4f36299dc53e31b16840dbd171254312c41ca12e  $archive" | sha256sum -c -)
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$download/$archive"
fi

repo="$base/artifact"
fetch_artifact "$repo" repos/coredns repos/codoh-client repos/codoh-evals
core="$repo/repos/coredns"
bench="$core/benchmark"
client="$repo/repos/codoh-client"
cp "$repo/repos/codoh-evals/data/umbrella-top-10k-resolvable.csv" "$bench/top-10k-resolvable.csv"
head -n 1000 "$bench/top-10k-resolvable.csv" > "$bench/top-1k-resolvable.csv"
{
    printf 'SSH_USER=%q\n' "$(id -un)"
    printf 'SSH_KEY=%q\n' "$base/orchestrator_key"
    printf 'REMOTE_ROOT=%q\n' "$core"
    printf 'PROXY_IP=%q\nTARGET_IP=%q\nSGX_MODE=%q\n' "$proxy_ip" "$target_ip" "$sgx"
} > "$bench/cloud-env.local.sh"

# Use the same historical C3 revisions and compatibility changes as cloud-setup.sh.
if [[ "$role" == client ]]; then
    (cd "$client" && go build -o odoh-client ./cmd)
    worktree="$client/worktrees/config3"
    if [[ ! -d "$worktree" ]]; then
        git -C "$client" worktree add --detach "$worktree" 010e7fe9bae41ec2b0405d3fd78d109afd9f18e6
        sed -i 's/codoh-enclave-v2/codoh transport key/' "$worktree/commands/blob.go"
        if grep -q 'codoh-response' "$worktree/commands/request.go"; then
            "$bench/patch-config3-client.sh" "$worktree/commands/request.go"
        fi
    fi
    (cd "$worktree" && go build -o odoh-client ./cmd)
else
    (cd "$core" && go build -o coredns-test .)
    worktree="$bench/worktrees/config3-proxy"
    if [[ ! -d "$worktree" ]]; then
        git -C "$core" worktree add --detach "$worktree" e81a315ec3a91dee1bad2cc2bbf139ebee145ab8
    fi
    if grep -q '^go 1.25.5' "$worktree/go.mod"; then
        sed -i 's/^go 1.25.5/go 1.25.1/; s|pathoram-go v0.1.[01]|pathoram-go v0.1.2|' "$worktree/go.mod"
        (cd "$worktree" && GOFLAGS=-mod=mod go mod tidy)
    fi
    sed -i 's/codoh-enclave-v1/codoh transport key/' \
        "$worktree/enclave/crypto.go" "$worktree/plugin/codohtarget/enclave_encrypt.go"
    sed -i 's/X-ODoH-Blob/X-CoDOH-Query/g' "$worktree/enclave/cmd/proxy_mode.go"
    (cd "$worktree" && go build -o coredns-test .)
fi

if [[ "$role" == target ]]; then
    # The runner copies the files to the repo root and starts C3 in its worktree.
    for file in localhost.pem localhost-key.pem; do
        ln -sfn "$core/$file" "$worktree/$file"
    done
    sudo apt-get install -y unbound
    sudo tee /etc/unbound/unbound.conf.d/codoh.conf >/dev/null <<'UNBOUND'
server:
    interface: 127.0.0.1
    port: 5353
    access-control: 127.0.0.0/8 allow
remote-control:
    control-enable: yes
UNBOUND
    sudo systemctl restart unbound
    sudo unbound-control status
fi

if [[ "$role" == proxy ]]; then
    (cd "$core" && go build -o enclave-sim ./enclave/cmd)
    (cd "$worktree" && go build -o enclave-sim ./enclave/cmd)
    # The original cert advertises the guest IP. Clients use the IBM floating IP.
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -keyout "$core/localhost-key.pem" -out "$core/localhost.pem" -days 30 \
        -subj /CN=codoh-benchmark \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:$proxy_ip,IP:$target_ip"
    if [[ "$sgx" == true ]]; then
        sudo test -c /dev/sgx_enclave
        sudo install -d /etc/apt/keyrings
        curl -fsSL https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key |
            sudo tee /etc/apt/keyrings/intel-sgx-keyring.asc >/dev/null
        printf 'deb [signed-by=/etc/apt/keyrings/intel-sgx-keyring.asc arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu %s main\n' "$(lsb_release -cs)" |
            sudo tee /etc/apt/sources.list.d/intel-sgx.list >/dev/null
        sudo apt-get update
        ego_package="ego_1.8.1_amd64_ubuntu-$(lsb_release -rs).deb"
        curl -fsSL "https://github.com/edgelesssys/ego/releases/download/v1.8.1/$ego_package" -o "$base/$ego_package"
        sudo apt-get install -y "$base/$ego_package" libssl-dev \
            libsgx-enclave-common libsgx-dcap-ql libsgx-dcap-default-qpl
        sudo test -c /dev/sgx_provision
        sudo test -d /root/.dcap-qcnl
        if [[ "$(id -u)" != 0 ]]; then
            sudo cp -a /root/.dcap-qcnl "$HOME/"
            sudo chown -R "$(id -u):$(id -g)" "$HOME/.dcap-qcnl"
            for device in /dev/sgx_enclave /dev/sgx_provision; do
                group=$(stat -c %G "$device")
                if [[ "$group" == sgx || "$group" == sgx_prv ]]; then
                    sudo usermod -aG "$group" "$(id -un)"
                fi
            done
        fi
        sudo python3 - <<'PYTHON'
import pathlib
import re

path = pathlib.Path("/etc/sgx_default_qcnl.conf")
config = path.read_text()
for key, value in {"use_secure_cert": "false", "local_cache_only": "true"}.items():
    pattern = rf'("{key}"\s*:\s*)(?:true|false)'
    config, changed = re.subn(pattern, rf"\g<1>{value}", config)
    if not changed:
        config = config.replace("{", f'{{\n    "{key}": {value},', 1)
path.write_text(config)
PYTHON
        sudo systemctl restart aesmd
        for tree in "$core" "$worktree"; do
            (cd "$tree/enclave" && ego-go build -tags ego -o enclave ./cmd && ego sign enclave.json)
        done
    fi
fi

{
    uname -a
    cat /etc/os-release
    lscpu
    go version
    git -C "$repo" rev-parse HEAD
    git -C "$repo" submodule status
    dpkg-query -W 'ego' 'libsgx*' 'unbound' 2>/dev/null || true
} > "$base/$role-environment.txt"
