#!/usr/bin/env bash
set -euo pipefail
umask 077
id=$1
mode=$2
batch_size=10
commit_probability=0.1
base="$HOME/codoh-reproduction"
core="$base/artifact/repos/coredns"
bench="$core/benchmark"
source "$bench/cloud-env.local.sh"
cd "$core"

# Serialize runs because the upstream harness uses fixed remote ports and paths.
exec 9>"$base/run.lock"
flock -n 9 || { echo "A benchmark is already running." >&2; exit 1; }

args=(--standard --resolver unbound)
case "$mode" in
    table3)
        [[ "$SGX_MODE" == true ]] || { echo "Table 3 requires SGX." >&2; exit 1; }
        ;;
    batch-size)
        [[ "$SGX_MODE" == true ]] || { echo "C5 requires SGX." >&2; exit 1; }
        batch_size=${3:-}
        case "$batch_size" in
            10|20|50|256) ;;
            *) echo "Expected a batch size of 10, 20, 50, or 256." >&2; exit 2 ;;
        esac
        commit_probability=${4:-0.1}
        case "$batch_size:$commit_probability" in
            *:0.1|20:0.05|50:0.02|256:0.00390625) ;;
            *) echo "Unexpected commit probability for this batch size." >&2; exit 2 ;;
        esac
        args+=(--configs 5)
        ;;
    *) exit 2 ;;
esac

result="$bench/results/$id"
mkdir -p "$bench/results"
mkdir "$result"
cp "$base/hosts.json" "$base/"*-environment.txt "$result/"
sha256sum "$bench"/top-{1k,10k}-resolvable.csv > "$result/workloads.sha256"
printf '%s\n' 'CODOH_CACHE_SIZE=1024' "CODOH_BATCH_SIZE=$batch_size" \
    "CODOH_BATCH_COMMIT_PROB=$commit_probability" 'CODOH_COVER_COUNT=3' > "$result/parameters.txt"
export CODOH_CACHE_SIZE=1024 CODOH_BATCH_SIZE="$batch_size" CODOH_BATCH_COMMIT_PROB="$commit_probability" CODOH_COVER_COUNT=3

bash -o pipefail ./benchmark/cloud-run.sh --run-id "$id" "${args[@]}" 2>&1 | tee "$result/runner.log"

# Keep failure counts visible. A process exit alone does not prove DNS succeeded.
python3 - "$result" "$mode" "$bench" <<'PY'
import csv
import json
import sys
from pathlib import Path

result = Path(sys.argv[1])
mode = sys.argv[2]
sweep = mode == "batch-size"
if sweep:
    sys.path.insert(0, sys.argv[3])
    from plot_preprocess import compute_percentiles

percentiles = {}
settings = json.loads((result / "metadata.json").read_text())
log = (result / "runner.log").read_text()
if "Failed to flush Unbound cache" in log:
    raise SystemExit("Unbound cache could not be flushed between workloads.")
if settings["sgx_mode"] and "5" in settings["configs"].split(","):
    enclave_log = result / "logs" / "bench-enclave.log"
    if not enclave_log.is_file() or "Generated SGX quote" not in enclave_log.read_text():
        raise SystemExit("C5 did not report generating an SGX quote.")
names = {"1": "doh", "2": "odoh", "3": "codoh-base", "4": "codoh-nosgx", "5": "codoh-full"}
with (result / "query-counts.csv").open("w", newline="") as out:
    writer = csv.writer(out)
    writer.writerow(["config", "workload", "iterations", "successful", "failed", "cache_hits"])
    for config in settings["configs"].split(","):
        for workload in settings["workloads"].split(","):
            name = names[config]
            prefix = result / "raw" / f"{name}_{workload}"
            summary = json.loads(prefix.with_suffix(".json").read_text())
            with prefix.with_suffix(".csv").open() as raw:
                count = sum(1 for _ in csv.DictReader(raw))
            if count != settings["iterations"] or summary["iterations"] != count or not summary["successful"]:
                raise SystemExit(f"Incomplete workload or zero successful queries: {name}/{workload}")
            # Zero hits can be a measurement outcome at larger batch sizes.
            if mode != "batch-size" and name.startswith("codoh") and workload == "warm" and not summary.get("cache_hits"):
                raise SystemExit(f"No warm cache hits: {name}/{workload}")
            writer.writerow([name, workload, count, summary["successful"], summary["failed"],
                             summary.get("cache_hits", 0)])
            if sweep:
                stats = compute_percentiles(prefix.with_suffix(".csv"))
                if stats is None:
                    raise SystemExit(f"No latency samples after warmup: {name}/{workload}")
                percentiles[f"{name}_{workload}"] = stats
if sweep:
    (result / "percentiles_trimmed.json").write_text(json.dumps(percentiles, indent=2) + "\n")
PY
if [[ "$mode" == table3 ]]; then
    ./benchmark/plot.sh "$result"
fi
