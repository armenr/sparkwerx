#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s /path/to/systemctl-show-output unit property\n' \
    "$(basename "$0")" >&2
}

if [[ "$#" -ne 3 ]]; then
  usage
  exit 2
fi

snapshot_file="$1"
unit="$2"
property="$3"

[[ -f "$snapshot_file" && ! -L "$snapshot_file" ]] || {
  printf 'Snapshot file is missing or not a regular file: %s\n' \
    "$snapshot_file" >&2
  exit 1
}
[[ "$unit" =~ ^[A-Za-z0-9_.@:-]+$ ]] || {
  printf 'Invalid systemd unit name: %s\n' "$unit" >&2
  exit 1
}
[[ "$property" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || {
  printf 'Invalid systemd property name: %s\n' "$property" >&2
  exit 1
}

# systemctl does not preserve the order supplied by repeated -p flags. Parse
# each complete blank-line-delimited record so a property emitted before Id
# cannot leak into the next unit. A present-but-empty property is a successful
# empty result; a missing unit record is an error.
awk -v wanted="$unit" -v property="$property" '
  BEGIN {
    RS = ""
    FS = "\n"
    found = 0
  }
  {
    matched = 0
    has_property = 0
    value = ""
    prefix = property "="
    for (i = 1; i <= NF; i++) {
      if ($i == "Id=" wanted) {
        matched = 1
      }
      if (index($i, prefix) == 1) {
        has_property = 1
        value = substr($i, length(prefix) + 1)
      }
    }
    if (matched) {
      if (!has_property) {
        exit 1
      }
      print value
      found = 1
      exit
    }
  }
  END {
    if (!found) {
      exit 1
    }
  }
' "$snapshot_file"
