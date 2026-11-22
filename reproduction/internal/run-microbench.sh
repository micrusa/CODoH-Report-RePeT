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
        iterations=${3:-10000}
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
        lookup_cycle=100
        iterations=${3:-$lookup_cycle}
        plain=
        sgx='^BenchmarkAccess$/^blocks=(256|1024|4096|16384)$/^blockSize=4096$/^read$'
        # Short scans can finish within one SGX clock tick at 100 iterations.
        linear_sgx="${sgx/BenchmarkAccess/BenchmarkLinearScan}"
        linear_iterations=${3:-10000000}
        ;;
    *) exit 2 ;;
esac

trials=3
warmup_trials=0
if [[ "$table" == 5 || "$iterations" == 1000000 ]]; then
    trials=5
    warmup_trials=1
fi
total_trials=$((warmup_trials + trials))
printf 'table=%s\niterations=%s\ntrials=%s\nwarmup_trials=%s\nbenchmark_commit=%s\n' \
    "$table" "$iterations" "$trials" "$warmup_trials" "$(git -C "$repo" rev-parse HEAD)" > "$result/parameters.txt"
if [[ "$table" == 6 ]]; then
    printf 'linear_scan_iterations=%s\nlinear_scan_lookup_cycle=%s\n' \
        "$linear_iterations" "$lookup_cycle" >> "$result/parameters.txt"
    if [[ "$iterations" != "$lookup_cycle" ]]; then
        printf 'pathoram_lookup_cycle=%s\n' "$lookup_cycle" >> "$result/parameters.txt"
    fi
fi

if [[ -n "$plain" ]]; then
    (cd "$repo" && go test -run='^$' -bench="$plain" -benchtime="${iterations}x" \
        -count="$total_trials" "$package") 2>&1 | tee "$result/plain.txt"
fi

# Compile and sign in a temporary directory, using the prepared enclave's manifest and key.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
build_flags=()
if [[ "$table" == 6 ]]; then
    # Repeat the original lookup sequence throughout the longer timing window.
    python3 - "$repo/oram_test.go" "$work" "$lookup_cycle" "$iterations" <<'PY'
import json
import sys
from pathlib import Path

original = Path(sys.argv[1]).resolve()
work = Path(sys.argv[2])
lookup_cycle, iterations = map(int, sys.argv[3:])


def repeat_lookups(source, benchmark, lookup):
    before, marker, rest = source.partition(f"func {benchmark}(b *testing.B) {{")
    body, next_function, after = rest.partition("\nfunc ")
    if not marker or body.count(lookup) != 1:
        raise SystemExit(f"Pinned {benchmark} no longer matches the lookup-cycle adaptation.")
    body = body.replace(lookup, lookup.replace("numBlocks", str(lookup_cycle)))
    return before + marker + body + next_function + after


source = repeat_lookups(original.read_text(), "BenchmarkLinearScan", "target := i % numBlocks")
if iterations != lookup_cycle:
    source = repeat_lookups(source, "BenchmarkAccess", "oram.Read(i % numBlocks)")
replacement = work / "oram_test.go"
replacement.write_text(source)
(work / "overlay.json").write_text(json.dumps({"Replace": {str(original): str(replacement)}}))
PY
    build_flags+=("-overlay=$work/overlay.json")
fi
(cd "$repo" && ego-go test -c "${build_flags[@]}" -o "$work/bench.test" "$package")
ln -s "$core/enclave/private.pem" "$work/private.pem"
if [[ "$table" == 4 && "$iterations" == 1000000 ]]; then
    # HPKE Open retains one ciphertext per operation before starting the timer.
    jq '.exe = "bench.test" | .heapSize = 2048' "$core/enclave/enclave.json" > "$work/enclave.json"
else
    jq '.exe = "bench.test"' "$core/enclave/enclave.json" > "$work/enclave.json"
fi
printf 'enclave_heap_mb=%s\n' "$(jq -er '.heapSize' "$work/enclave.json")" >> "$result/parameters.txt"
(
    cd "$work"
    ego sign enclave.json
    ego run bench.test -test.run='^$' -test.bench="$sgx" \
        -test.benchtime="${iterations}x" -test.count="$total_trials"
    if [[ "$table" == 6 ]]; then
        ego run bench.test -test.run='^$' -test.bench="$linear_sgx" \
            -test.benchtime="${linear_iterations}x" -test.count="$total_trials"
    fi
) 2>&1 | tee "$result/sgx.txt"

python3 - "$result" "$table" "$iterations" "${linear_iterations:-0}" "$trials" "$warmup_trials" <<'PY'
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import median, stdev

result = Path(sys.argv[1])
table = sys.argv[2]
iterations, linear_iterations, trials, warmup_trials = map(int, sys.argv[3:])
expected = {
    "4": {"plain": 8, "sgx": 8},
    "5": {"plain": 8, "sgx": 4},
    "6": {"sgx": 8},
}
pattern = re.compile(r"^(Benchmark\S+?)(?:-\d+)?\s+(\d+)\s+(\d+(?:\.\d+)?)\s+ns/op\b")
rows = []
trial_rows = []
for mode, expected_cases in expected[table].items():
    measurements = defaultdict(list)
    for line in (result / f"{mode}.txt").read_text().splitlines():
        match = pattern.match(line)
        if match:
            benchmark, count, ns = match.groups()
            trial_iterations = linear_iterations if benchmark.startswith("BenchmarkLinearScan/") else iterations
            if int(count) == trial_iterations:
                measurements[benchmark].append(float(ns) / 1000)
    total_trials = trials + warmup_trials
    if len(measurements) != expected_cases or any(len(values) != total_trials for values in measurements.values()):
        raise SystemExit(f"Expected {expected_cases} benchmark cases with {total_trials} timings each in {mode}.txt; "
                         f"found {len(measurements)} cases with recorded timings")
    for benchmark, values in measurements.items():
        values = values[warmup_trials:]
        trial_rows.extend((benchmark, mode, trial, value) for trial, value in enumerate(values, start=1))
        rows.append((benchmark, mode, median(values), stdev(values)))

with (result / "trials.csv").open("w", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(["benchmark", "mode", "trial", "us_per_op"])
    writer.writerows(trial_rows)

with (result / "medians.csv").open("w", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(["benchmark", "mode", "median_us_per_op", "stddev_us_per_op"])
    writer.writerows(rows)
PY
