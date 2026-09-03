#!/usr/bin/env bash
set -euo pipefail

# Reconcile only Armen's approval/permission defaults plus the self-update
# switch required by Nix package ownership. Codex and the ChatGPT desktop app
# may continue to own every unrelated key in config.toml.

fail() {
  printf 'FAIL|codex_relaxed_defaults|%s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'usage: %s (--apply|--check) /absolute/path/to/config.toml\n' "$0" >&2
  exit 64
}

config_is_current() {
  awk '
    BEGIN { section = "top" }
    {
      line = $0
      header = line
      sub(/^[[:space:]]*/, "", header)
      sub(/[[:space:]]*#.*$/, "", header)
      sub(/[[:space:]]*$/, "", header)
      if (header ~ /^\[.*\]$/) {
        if (header == "[notice]") section = "notice"
        else if (header == "[apps._default]") section = "apps"
        else section = "other"
        next
      }

      if (section == "top" && line ~ /^[[:space:]]*approval_policy[[:space:]]*=/) {
        top_approval++
        if (line ~ /^[[:space:]]*approval_policy[[:space:]]*=[[:space:]]*"never"[[:space:]]*(#.*)?$/) top_approval_ok++
      }
      if (section == "top" && line ~ /^[[:space:]]*default_permissions[[:space:]]*=/) {
        top_permissions++
        if (line ~ /^[[:space:]]*default_permissions[[:space:]]*=[[:space:]]*":danger-full-access"[[:space:]]*(#.*)?$/) top_permissions_ok++
      }
      if (section == "top" && line ~ /^[[:space:]]*approvals_reviewer[[:space:]]*=/) {
        top_reviewer++
        if (line ~ /^[[:space:]]*approvals_reviewer[[:space:]]*=[[:space:]]*"auto_review"[[:space:]]*(#.*)?$/) top_reviewer_ok++
      }
      if (section == "top" && line ~ /^[[:space:]]*check_for_update_on_startup[[:space:]]*=/) {
        top_update++
        if (line ~ /^[[:space:]]*check_for_update_on_startup[[:space:]]*=[[:space:]]*false[[:space:]]*(#.*)?$/) top_update_ok++
      }
      if (section == "notice" && line ~ /^[[:space:]]*hide_full_access_warning[[:space:]]*=/) {
        notice_warning++
        if (line ~ /^[[:space:]]*hide_full_access_warning[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$/) notice_warning_ok++
      }
      if (section == "apps" && line ~ /^[[:space:]]*approvals_reviewer[[:space:]]*=/) {
        apps_reviewer++
        if (line ~ /^[[:space:]]*approvals_reviewer[[:space:]]*=[[:space:]]*"auto_review"[[:space:]]*(#.*)?$/) apps_reviewer_ok++
      }
      if (section == "apps" && line ~ /^[[:space:]]*default_tools_approval_mode[[:space:]]*=/) {
        apps_mode++
        if (line ~ /^[[:space:]]*default_tools_approval_mode[[:space:]]*=[[:space:]]*"approve"[[:space:]]*(#.*)?$/) apps_mode_ok++
      }
      if (section == "apps" && line ~ /^[[:space:]]*destructive_enabled[[:space:]]*=/) {
        apps_destructive++
        if (line ~ /^[[:space:]]*destructive_enabled[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$/) apps_destructive_ok++
      }
      if (section == "apps" && line ~ /^[[:space:]]*open_world_enabled[[:space:]]*=/) {
        apps_open_world++
        if (line ~ /^[[:space:]]*open_world_enabled[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$/) apps_open_world_ok++
      }
    }
    END {
      if (top_approval != 1 || top_approval_ok != 1) exit 1
      if (top_permissions != 1 || top_permissions_ok != 1) exit 1
      if (top_reviewer != 1 || top_reviewer_ok != 1) exit 1
      if (top_update != 1 || top_update_ok != 1) exit 1
      if (notice_warning != 1 || notice_warning_ok != 1) exit 1
      if (apps_reviewer != 1 || apps_reviewer_ok != 1) exit 1
      if (apps_mode != 1 || apps_mode_ok != 1) exit 1
      if (apps_destructive != 1 || apps_destructive_ok != 1) exit 1
      if (apps_open_world != 1 || apps_open_world_ok != 1) exit 1
      exit 0
    }
  ' "$1"
}

[[ "$#" -eq 2 ]] || usage
mode=$1
target=$2
[[ "$mode" == --apply || "$mode" == --check ]] || usage
[[ "$target" == /* ]] || fail 'config path must be absolute'

target_dir=${target%/*}
[[ -n "$target_dir" ]] || fail 'config path has no parent directory'

if [[ -L "$target_dir" ]]; then
  fail 'refusing a symlinked Codex config directory'
fi
if [[ -e "$target_dir" && ! -d "$target_dir" ]]; then
  fail 'Codex config parent exists but is not a directory'
fi
if [[ -d "$target_dir" && ! -O "$target_dir" ]]; then
  fail 'Codex config directory is not owned by the current user'
fi

if [[ -L "$target" ]]; then
  fail 'refusing to replace a symlinked Codex config'
fi
if [[ -e "$target" && ! -f "$target" ]]; then
  fail 'Codex config exists but is not a regular file'
fi
if [[ -e "$target" && ! -O "$target" ]]; then
  fail 'Codex config is not owned by the current user'
fi
if [[ "$mode" == --check && ! -f "$target" ]]; then
  fail 'Codex config does not exist'
fi

if [[ -f "$target" ]] && config_is_current "$target"; then
  printf 'PASS|codex_relaxed_defaults|already-current\n'
  exit 0
fi

if [[ "$mode" == --apply ]]; then
  [[ -d "$target_dir" ]] || install -d -m 0700 -- "$target_dir"
fi

temp_file="$(mktemp "$target_dir/.config.toml.dgx.XXXXXX")"
cleanup() {
  rm -f -- "$temp_file"
}
trap cleanup EXIT

input=/dev/null
[[ -f "$target" ]] && input=$target

awk '
  function emit_top() {
    if (top_emitted) return
    print "approval_policy = \"never\""
    print "default_permissions = \":danger-full-access\""
    print "approvals_reviewer = \"auto_review\""
    print "check_for_update_on_startup = false"
    top_emitted = 1
  }

  function emit_notice() {
    if (notice_emitted) return
    print "hide_full_access_warning = true"
    notice_emitted = 1
  }

  function emit_apps() {
    if (apps_emitted) return
    print "approvals_reviewer = \"auto_review\""
    print "default_tools_approval_mode = \"approve\""
    print "destructive_enabled = true"
    print "open_world_enabled = true"
    apps_emitted = 1
  }

  function finish_section() {
    if (section == "top") emit_top()
    if (section == "notice") emit_notice()
    if (section == "apps") emit_apps()
  }

  BEGIN {
    section = "top"
  }

  {
    line = $0
    header = line
    sub(/^[[:space:]]*/, "", header)
    sub(/[[:space:]]*#.*$/, "", header)
    sub(/[[:space:]]*$/, "", header)

    if (header ~ /^\[.*\]$/) {
      finish_section()
      if (header == "[notice]") {
        notice_sections++
        if (notice_sections > 1) exit 65
        section = "notice"
      } else if (header == "[apps._default]") {
        apps_sections++
        if (apps_sections > 1) exit 66
        section = "apps"
      } else {
        section = "other"
      }
      print line
      next
    }

    if (section == "top" &&
        line ~ /^[[:space:]]*(approval_policy|default_permissions|approvals_reviewer|check_for_update_on_startup)[[:space:]]*=/) next
    if (section == "top" &&
        line ~ /^[[:space:]]*notice[.]hide_full_access_warning[[:space:]]*=/) next
    if (section == "top" &&
        line ~ /^[[:space:]]*apps[.]_default[.](approvals_reviewer|default_tools_approval_mode|destructive_enabled|open_world_enabled)[[:space:]]*=/) next
    if (section == "notice" &&
        line ~ /^[[:space:]]*hide_full_access_warning[[:space:]]*=/) next
    if (section == "apps" &&
        line ~ /^[[:space:]]*(approvals_reviewer|default_tools_approval_mode|destructive_enabled|open_world_enabled)[[:space:]]*=/) next

    print line
  }

  END {
    finish_section()
    if (!notice_sections) {
      if (NR > 0) print ""
      print "[notice]"
      emit_notice()
    }
    if (!apps_sections) {
      print ""
      print "[apps._default]"
      emit_apps()
    }
  }
' "$input" >"$temp_file" || fail 'Codex config has duplicate managed tables'

target_mode=0600
[[ -f "$target" ]] && target_mode="$(stat -c '%a' -- "$target")"
chmod "$target_mode" -- "$temp_file"

if [[ -f "$target" ]] && cmp -s -- "$temp_file" "$target"; then
  printf 'PASS|codex_relaxed_defaults|already-current\n'
  exit 0
fi

if [[ "$mode" == --check ]]; then
  fail 'Codex permission defaults differ from Armen policy'
fi

mv -f -- "$temp_file" "$target"
trap - EXIT
printf 'PASS|codex_relaxed_defaults|reconciled\n'
