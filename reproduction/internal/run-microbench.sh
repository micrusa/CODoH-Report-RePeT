#!/usr/bin/env bash
set -euo pipefail
umask 077

table=$1
id=$2
base="$HOME/codoh-reproduction"
artifact="$base/artifact"
core="$artifact/repos/coredns"
result="$core/benchmark/results/$id"

export PATH="/usr/local/go/bin:$PATH"
unset OE_SIMULATION
if [[ ! -r "$core/enclave/private.pem" || ! -c /dev/sgx_enclave ]] ||
    ! command -v ego >/dev/null || ! command -v ego-go >/dev/null; then
    echo "Prepare the SGX proxy before running Tables 4–6." >&2
    exit 1
fi

exec 9>"$base/microbench.lock"
flock -n 9 || { echo "A microbenchmark is already running on this proxy." >&2; exit 1; }
mkdir -p "$(dirname "$result")"
mkdir "$result"
cp "$base/proxy-environment.txt" "$result/"

# Match the published table definitions and reuse the pinned Go benchmarks.
repo="$core"
package=./enclave
iterations=10000
case "$table" in
    4)
        plain='^Benchmark(HPKE_(Seal|Open)|AESGCM_(Seal|Seal_PreNonce|Open)|NonceGen_Only|Ed25519_(Sign|Verify))$'
        sgx=$plain
        ;;
    5)
        plain='^Benchmark(LRU|ORAM)Cache_Get$/^N=(256|512|1024|2048)$'
        sgx='^BenchmarkORAMCache_Get$/^N=(256|512|1024|2048)$'
        ;;
    6)
        git -C "$artifact" submodule update --init -- repos/pathoram-go
        repo="$artifact/repos/pathoram-go"
        package=.
        iterations=100
        plain=
        sgx='^BenchmarkAccess$/^blocks=(256|1024|4096|16384)$/^blockSize=4096$/^read$'
        # Short scans can finish within one SGX clock tick at 100 iterations.
        linear_sgx="${sgx/BenchmarkAccess/BenchmarkLinearScan}"
        linear_iterations=100000
        ;;
    *) exit 2 ;;
esac

printf 'table=%s\niterations=%s\ntrials=3\nbenchmark_commit=%s\n' \
    "$table" "$iterations" "$(git -C "$repo" rev-parse HEAD)" > "$result/parameters.txt"
if [[ "$table" == 6 ]]; then
    printf 'linear_scan_iterations=%s\n' "$linear_iterations" >> "$result/parameters.txt"
fi

if [[ -n "$plain" ]]; then
    (cd "$repo" && go test -run='^$' -bench="$plain" -benchtime="${iterations}x" \
        -count=3 "$package") 2>&1 | tee "$result/plain.txt"
fi

# Compile and sign in a temporary directory, using the prepared enclave's manifest and key.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd "$repo" && ego-go test -c -o "$work/bench.test" "$package")
ln -s "$core/enclave/private.pem" "$work/private.pem"
jq '.exe = "bench.test"' "$core/enclave/enclave.json" > "$work/enclave.json"
(
    cd "$work"
    ego sign enclave.json
    ego run bench.test -test.run='^$' -test.bench="$sgx" \
        -test.benchtime="${iterations}x" -test.count=3
    if [[ "$table" == 6 ]]; then
        ego run bench.test -test.run='^$' -test.bench="$linear_sgx" \
            -test.benchtime="${linear_iterations}x" -test.count=3
    fi
) 2>&1 | tee "$result/sgx.txt"

python3 - "$result" "$table" "$iterations" "${linear_iterations:-0}" <<'PY'
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import median

result = Path(sys.argv[1])
table, iterations, linear_iterations = map(int, sys.argv[2:])
expected = {4: {"plain": 8, "sgx": 8}, 5: {"plain": 8, "sgx": 4}, 6: {"sgx": 8}}
pattern = re.compile(r"^(Benchmark\S+?)(?:-\d+)?\s+(\d+)\s+(\d+(?:\.\d+)?)\s+ns/op\b")
rows = []
for mode, expected_cases in expected[table].items():
    measurements = defaultdict(list)
    for line in (result / f"{mode}.txt").read_text().splitlines():
        match = pattern.match(line)
        if match:
            benchmark, count, ns = match.groups()
            trial_iterations = linear_iterations if benchmark.startswith("BenchmarkLinearScan/") else iterations
            if int(count) == trial_iterations:
                measurements[benchmark].append(float(ns))
    if len(measurements) != expected_cases or any(len(values) != 3 for values in measurements.values()):
        raise SystemExit(f"Expected {expected_cases} benchmark cases with three timings each in {mode}.txt; "
                         f"found {len(measurements)} cases with recorded timings")
    for benchmark, values in measurements.items():
        rows.append((benchmark, mode, median(values) / 1000))

with (result / "medians.csv").open("w", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(["benchmark", "mode", "median_us_per_op"])
    writer.writerows(rows)
PY
