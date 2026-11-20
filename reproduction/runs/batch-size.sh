#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../internal/common.sh"
require_matplotlib
load_hosts

if [[ "$("${tf[@]}" output -raw enable_sgx)" != true ]]; then
    echo "The batch-size sweep requires an SGX proxy." >&2
    exit 1
fi

sweep_id=$(new_run_id)
printf 'Sweep ID: %s\n' "$sweep_id"
run_benchmark baseline "batch-size-c2-$sweep_id"
status=0
for batch_size in 10 20 50 100 200 400; do
    if ! run_benchmark batch-size "batch-size-c5-b$batch_size-$sweep_id" "$batch_size"; then
        printf 'C5 batch size %s failed. Continuing with the sweep.\n' "$batch_size" >&2
        status=1
    fi
done
if (( status != 0 )); then
    exit "$status"
fi
python3 "$root/analysis/plot-batch-size.py" "$sweep_id"
