#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../internal/common.sh"
load_hosts
run_benchmark plain
