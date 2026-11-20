#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../internal/common.sh"
validate_run_id "${1:-}"
load_hosts
collect "$1"
