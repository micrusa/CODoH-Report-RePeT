#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$root/setup/install_kernel_6_11.sh"
"$root/setup/prepare.sh"
"$root/runs/table4_1M_ops.sh"
