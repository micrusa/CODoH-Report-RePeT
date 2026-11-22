#!/usr/bin/env bash
set -euo pipefail

runs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../runs" && pwd)"
"$runs_dir/table4_1M_ops.sh"
"$runs_dir/table5.sh"
"$runs_dir/table6_1M_ops.sh"
