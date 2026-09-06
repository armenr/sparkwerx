#!@bash@
# shellcheck shell=bash
set -euo pipefail
trial_bin_dir="${BASH_SOURCE[0]%/*}"
trial_bundle="$(@readlink@ -f -- "$trial_bin_dir/..")"
exec @python@ @controller@ --tools @manifest@ --bundle "$trial_bundle" "$@"
