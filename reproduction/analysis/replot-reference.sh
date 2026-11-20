#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../internal/common.sh"
repo="$root/.reference/artifact"
mkdir -p "$root/.reference"
fetch_artifact "$repo" repos/coredns
mkdir -p "$root/.reference/data"
tar -xzf "$repo/paper-results/table3-latency-cdfs.tar.gz" -C "$root/.reference/data"
"$repo/repos/coredns/benchmark/plot.sh" "$root/.reference/data/multi-region-combined"
