#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
reconciler=$repo_dir/scripts/reconcile-codex-relaxed-defaults.sh

fail() {
  printf 'FAIL|codex_relaxed_defaults_test|%s\n' "$1" >&2
  exit 1
}

[[ -x "$reconciler" ]] || fail 'reconciler is missing or not executable'
bash -n "$reconciler" || fail 'reconciler failed syntax validation'

temp_dir="$(mktemp -d)"
cleanup() {
  rm -f -- "$temp_dir/config.toml" "$temp_dir/empty.toml" \
    "$temp_dir/drift.toml" "$temp_dir/link.toml" "$temp_dir/target.toml"
  rmdir -- "$temp_dir"
}
trap cleanup EXIT

printf '%s\n' \
  'model = "keep-this-model"' \
  'approval_policy = "on-request"' \
  'default_permissions = ":workspace"' \
  'approvals_reviewer = "user"' \
  '' \
  '[notice]' \
  'hide_full_access_warning = false' \
  'hide_rate_limit_model_nudge = true' \
  '' \
  '[apps._default]' \
  'approvals_reviewer = "user"' \
  'default_tools_approval_mode = "prompt"' \
  'destructive_enabled = false' \
  'open_world_enabled = false' \
  'enabled = true' \
  '' \
  '[plugins.example]' \
  'enabled = true' \
  >"$temp_dir/config.toml"

"$reconciler" --apply "$temp_dir/config.toml" >/dev/null
grep -Fx 'model = "keep-this-model"' "$temp_dir/config.toml" >/dev/null ||
  fail 'unrelated top-level setting changed'
grep -Fx 'hide_rate_limit_model_nudge = true' "$temp_dir/config.toml" >/dev/null ||
  fail 'unrelated notice setting changed'
grep -Fx 'enabled = true' "$temp_dir/config.toml" >/dev/null ||
  fail 'unrelated app/plugin setting changed'

for expected in \
  'approval_policy = "never"' \
  'default_permissions = ":danger-full-access"' \
  'approvals_reviewer = "auto_review"' \
  'hide_full_access_warning = true' \
  'default_tools_approval_mode = "approve"' \
  'destructive_enabled = true' \
  'open_world_enabled = true'; do
  grep -Fx "$expected" "$temp_dir/config.toml" >/dev/null ||
    fail "managed setting is absent: $expected"
done

before="$(sha256sum "$temp_dir/config.toml" | awk '{print $1}')"
"$reconciler" --apply "$temp_dir/config.toml" >/dev/null
after="$(sha256sum "$temp_dir/config.toml" | awk '{print $1}')"
[[ "$after" == "$before" ]] || fail 'second reconciliation was not idempotent'
"$reconciler" --check "$temp_dir/config.toml" >/dev/null ||
  fail 'check rejected a reconciled config'

printf 'model = "preserved"\n' >"$temp_dir/drift.toml"
if "$reconciler" --check "$temp_dir/drift.toml" >/dev/null 2>&1; then
  fail 'check accepted missing managed settings'
fi

: >"$temp_dir/empty.toml"
"$reconciler" --apply "$temp_dir/empty.toml" >/dev/null
grep -Fx '[notice]' "$temp_dir/empty.toml" >/dev/null ||
  fail 'empty config did not gain notice table'
grep -Fx '[apps._default]' "$temp_dir/empty.toml" >/dev/null ||
  fail 'empty config did not gain app defaults table'

printf 'do-not-touch\n' >"$temp_dir/target.toml"
ln -s "$temp_dir/target.toml" "$temp_dir/link.toml"
if "$reconciler" --apply "$temp_dir/link.toml" >/dev/null 2>&1; then
  fail 'symlinked config was unexpectedly replaced'
fi
grep -Fx 'do-not-touch' "$temp_dir/target.toml" >/dev/null ||
  fail 'symlink target changed after refusal'

printf 'PASS|codex_relaxed_defaults_test|merge, idempotence, check, empty-file, and symlink cases passed\n'
