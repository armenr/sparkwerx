#!/usr/bin/env bash
set -uo pipefail

usage() {
  printf 'Usage: %s [--offline]\n' "$(basename "$0")" >&2
}

offline=0
case "${1:-}" in
  "")
    ;;
  --offline)
    offline=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! repo_dir="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null)"; then
  printf '%s\n' "ERROR: the skill must live inside a Git repository." >&2
  exit 1
fi
cd "$repo_dir" || exit 1
repo_flake_uri="git+file://$repo_dir"

sanitize() {
  local value="${1:-}"
  value="${value//$'\t'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/; }"
  printf '%s' "$value"
}

emit() {
  local scope="$1"
  local owner="$2"
  local component="$3"
  local current="$4"
  local candidate="$5"
  local status="$6"
  local source="$7"
  local detail="$8"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(sanitize "$scope")" \
    "$(sanitize "$owner")" \
    "$(sanitize "$component")" \
    "$(sanitize "$current")" \
    "$(sanitize "$candidate")" \
    "$(sanitize "$status")" \
    "$(sanitize "$source")" \
    "$(sanitize "$detail")"
}

short_rev() {
  local revision="${1:-}"
  if [[ -n "$revision" ]]; then
    printf '%.12s' "$revision"
  else
    printf '%s' "UNKNOWN"
  fi
}

version_status() {
  local current="$1"
  local candidate="$2"
  local first

  if [[ "$current" == "$candidate" ]]; then
    printf '%s' "CURRENT"
    return
  fi

  first="$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | head -n 1)"
  if [[ "$first" == "$current" ]]; then
    printf '%s' "UPDATE_AVAILABLE"
  else
    printf '%s' "AHEAD"
  fi
}

remote_head() {
  local url="$1"
  local ref="$2"
  local remote_revision owner repo branch

  remote_revision="$(
    timeout 30s git \
      -c http.lowSpeedLimit=1 \
      -c http.lowSpeedTime=15 \
      ls-remote "$url" "$ref" 2>/dev/null |
      awk 'NR == 1 { print $1 }'
  )"

  # Large GitHub repositories occasionally time out during the smart-Git
  # advertisement even though the authoritative ref API is healthy. Fall back
  # only for a syntactically safe GitHub branch; never infer a revision from a
  # search result or mutable HTML page.
  if [[ -z "$remote_revision" ]] &&
    command -v jq >/dev/null 2>&1 &&
    [[ "$url" =~ ^https://github.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)\.git$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"

    if [[ "$ref" =~ ^refs/heads/([A-Za-z0-9_./-]+)$ ]]; then
      branch="${BASH_REMATCH[1]}"
      remote_revision="$(
        timeout 30s curl --fail --silent --show-error \
          --header 'Accept: application/vnd.github+json' \
          --header 'X-GitHub-Api-Version: 2022-11-28' \
          "https://api.github.com/repos/$owner/$repo/git/ref/heads/$branch" 2>/dev/null |
          jq -r '.object.sha // empty' 2>/dev/null || true
      )"
    fi
  fi

  printf '%s' "$remote_revision"
}

github_latest_release_tag() {
  local owner="$1"
  local repo="$2"

  timeout 30s curl --fail --silent --show-error \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    "https://api.github.com/repos/$owner/$repo/releases/latest" 2>/dev/null |
    jq -r '.tag_name // empty' 2>/dev/null || true
}

root_input_node() {
  local input_name="$1"
  jq -r --arg input "$input_name" '
    .root as $root
    | .nodes[$root].inputs[$input]
    | if type == "array" then .[0] else . end
    // empty
  ' flake.lock 2>/dev/null
}

lock_value() {
  local node="$1"
  local expression="$2"
  jq -r --arg node "$node" "$expression // empty" flake.lock 2>/dev/null
}

compare_branch_input() {
  local input_name="$1"
  local label="$2"
  local node owner repo ref revision url remote_revision current candidate status detail

  node="$(root_input_node "$input_name")"
  if [[ -z "$node" ]]; then
    emit "NIX_REPO" "repository" "$label" "absent" "UNKNOWN" "NOT_PINNED" \
      "repo:flake.lock" "Root input is not pinned."
    return
  fi

  owner="$(lock_value "$node" '.nodes[$node].locked.owner // .nodes[$node].original.owner')"
  repo="$(lock_value "$node" '.nodes[$node].locked.repo // .nodes[$node].original.repo')"
  ref="$(lock_value "$node" '.nodes[$node].locked.ref // .nodes[$node].original.ref')"
  revision="$(lock_value "$node" '.nodes[$node].locked.rev')"
  current="${ref:-detached}@$(short_rev "$revision")"

  if [[ "$offline" -eq 1 ]]; then
    emit "NIX_REPO" "repository" "$label" "$current" "REMOTE_SUPPRESSED" \
      "UNKNOWN" "https://github.com/$owner/$repo" \
      "Offline audit; branch head was not queried."
    return
  fi

  if [[ ! "$owner" =~ ^[A-Za-z0-9_.-]+$ ||
        ! "$repo" =~ ^[A-Za-z0-9_.-]+$ ||
        ! "$ref" =~ ^[A-Za-z0-9_./-]+$ ]]; then
    emit "NIX_REPO" "repository" "$label" "$current" "UNKNOWN" "UNKNOWN" \
      "repo:flake.lock" "Lock metadata did not contain a safe GitHub branch."
    return
  fi

  url="https://github.com/$owner/$repo.git"
  remote_revision="$(remote_head "$url" "refs/heads/$ref")"
  if [[ -z "$remote_revision" ]]; then
    emit "NIX_REPO" "repository" "$label" "$current" "UNKNOWN" "UNKNOWN" \
      "https://github.com/$owner/$repo/tree/$ref" \
      "Unable to resolve the authoritative branch head."
    return
  fi

  candidate="$ref@$(short_rev "$remote_revision")"
  if [[ "$revision" == "$remote_revision" ]]; then
    status="CURRENT"
    detail="Locked revision matches the authoritative branch head."
  else
    status="UPDATE_AVAILABLE"
    detail="The branch head moved; availability only until the resulting lock is validated."
  fi
  emit "NIX_REPO" "repository" "$label" "$current" "$candidate" "$status" \
    "https://github.com/$owner/$repo/tree/$ref" \
    "$detail"
}

audit_selected_nix_packages() {
  local manifest role pname component current candidate status source detail
  local tag location
  local -a nix_args

  nix_args=(
    --extra-experimental-features "nix-command flakes"
    eval
    --json
    --no-write-lock-file
  )
  if [[ "$offline" -eq 1 ]]; then
    nix_args+=(--offline)
  fi
  manifest="$(
    timeout 60s nix "${nix_args[@]}" \
      .#lib.dgxProfileManifests.aarch64-linux 2>/dev/null || true
  )"

  package_version() {
    local selected_role="$1"
    local selected_pname="$2"
    jq -r \
      --arg role "$selected_role" \
      --arg pname "$selected_pname" \
      '.roles[$role][]? | select(.pname == $pname) | .version' \
      <<<"$manifest" 2>/dev/null |
      head -n 1
  }

  emit_package_comparison() {
    local scope="$1"
    local package_owner="$2"
    local package_component="$3"
    local package_current="$4"
    local package_candidate="$5"
    local package_source="$6"
    local update_gate="$7"
    local package_status package_detail

    if [[ -z "$package_current" ]]; then
      emit "$scope" "$package_owner" "$package_component" \
        "absent" "${package_candidate:-UNKNOWN}" "NOT_PINNED" \
        "$package_source" \
        "The selected package is missing from the machine-readable manifest."
      return
    fi

    if [[ "$offline" -eq 1 ]]; then
      emit "$scope" "$package_owner" "$package_component" \
        "$package_current" "REMOTE_SUPPRESSED" "UNKNOWN" "$package_source" \
        "Offline audit; the official release source was not queried."
      return
    fi

    if [[ -z "$package_candidate" ]]; then
      emit "$scope" "$package_owner" "$package_component" \
        "$package_current" "UNKNOWN" "UNKNOWN" "$package_source" \
        "The official release source could not be parsed; do not guess."
      return
    fi

    package_status="$(version_status "$package_current" "$package_candidate")"
    case "$package_status" in
      CURRENT)
        package_detail="The repository candidate matches the newest official stable release."
        ;;
      UPDATE_AVAILABLE)
        package_detail="Availability only. $update_gate"
        ;;
      AHEAD)
        package_status="HOLD"
        package_detail="The repository candidate is ahead of the official stable result; investigate provenance and do not downgrade automatically."
        ;;
    esac

    emit "$scope" "$package_owner" "$package_component" \
      "$package_current" "$package_candidate" "$package_status" \
      "$package_source" "$package_detail"
  }

  if ! jq -e '.schemaVersion == 1' >/dev/null 2>&1 <<<"$manifest"; then
    for component in \
      ncdu lazydocker Ghostty Chromium Zed "LM Studio desktop"; do
      emit "NIX_PACKAGE" "repository" "$component" \
        "MANIFEST_UNAVAILABLE" "UNKNOWN" "UNKNOWN" \
        "repo:flake.nix" \
        "The machine-readable profile manifest did not evaluate."
    done
    return
  fi

  current="$(package_version fleetBase ncdu)"
  candidate=""
  if [[ "$offline" -eq 0 ]]; then
    candidate="$(
      timeout 30s curl --fail --silent --show-error \
        https://dev.yorhel.nl/ncdu 2>/dev/null |
        grep -oE 'ncdu-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz' |
        head -n 1 |
        sed -E 's/^ncdu-//; s/\.tar\.gz$//' || true
    )"
  fi
  emit_package_comparison \
    "NIX_PACKAGE" "fleet base" "ncdu" "$current" "$candidate" \
    "https://dev.yorhel.nl/ncdu" \
    "Refresh the stable lock, then re-evaluate the exact three-package base."

  current="$(package_version fleetBase lazydocker)"
  candidate=""
  if [[ "$offline" -eq 0 ]]; then
    tag="$(github_latest_release_tag jesseduffield lazydocker)"
    candidate="${tag#v}"
  fi
  emit_package_comparison \
    "NIX_PACKAGE" "fleet base" "lazydocker" "$current" "$candidate" \
    "https://github.com/jesseduffield/lazydocker/releases" \
    "Refresh the stable lock and validate ARM64 plus Docker 29 compatibility; do not grant Docker-socket access."

  current="$(package_version sharedGraphical ghostty)"
  candidate=""
  if [[ "$offline" -eq 0 ]]; then
    candidate="$(
      timeout 30s curl --fail --silent --show-error \
        https://ghostty.org/docs/install/release-notes 2>/dev/null |
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+' |
        sort -Vr |
        head -n 1 || true
    )"
  fi
  emit_package_comparison \
    "NIX_PACKAGE" "shared graphical role" "Ghostty" \
    "$current" "$candidate" \
    "https://ghostty.org/docs/install/release-notes" \
    "Refresh the stable lock, then repeat the ARM64 GTK/GPU and closure review; keep it absent from headless."

  current="$(package_version personalGraphicalCandidates chromium)"
  candidate=""
  if [[ "$offline" -eq 0 ]]; then
    candidate="$(
      timeout 30s curl --fail --silent --show-error \
        'https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=5' \
        2>/dev/null |
        jq -r '.[0].version // empty' 2>/dev/null || true
    )"
  fi
  emit_package_comparison \
    "NIX_PACKAGE" "Armen candidate overlay" "Chromium" \
    "$current" "$candidate" \
    "https://chromiumdash.appspot.com/releases?platform=Linux" \
    "Refresh only the apps lock, then review security delta, ARM64 closure, extensions, and NVIDIA graphics before wiring it."

  current="$(package_version personalGraphicalCandidates zed-editor)"
  candidate=""
  if [[ "$offline" -eq 0 ]]; then
    tag="$(github_latest_release_tag zed-industries zed)"
    candidate="${tag#v}"
  fi
  emit_package_comparison \
    "NIX_PACKAGE" "Armen candidate overlay" "Zed" \
    "$current" "$candidate" \
    "https://github.com/zed-industries/zed/releases" \
    "Refresh only the apps lock, inspect intervening security notes, and validate ARM64 Vulkan/Wayland/portal behavior before wiring it."

  current="$(package_version personalGraphicalCandidates lmstudio)"
  candidate=""
  if [[ "$offline" -eq 0 ]]; then
    location="$(
      timeout 30s curl --fail --silent --show-error --head \
        https://lmstudio.ai/download/latest/linux/arm64 2>/dev/null |
        sed -nE 's/^location:[[:space:]]*//Ip' |
        tr -d '\r' |
        tail -n 1
    )"
    candidate="$(
      sed -nE \
        's#^.*/arm64/([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)/.*$#\1#p' \
        <<<"$location"
    )"
  fi
  emit_package_comparison \
    "NIX_PACKAGE" "Armen candidate overlay" "LM Studio desktop" \
    "$current" "$candidate" "https://lmstudio.ai/download" \
    "Refresh only the apps lock, preserve the exact lmstudio unfree allowlist, inspect the ARM64 closure/model paths, and validate GB10 acceleration before wiring it."
}

audit_root_integration() {
  local manifest manager_node manager_ref manager_locked_rev
  local manager_version manager_branch manager_rev private_nix_version
  local private_nix_rev release_version release_rev current candidate
  local test_result registration_test_result registration_test_matches
  local live_registration_host live_registration_state registration_mode
  local policy_ok live_state root_output status detail
  local -a nix_args

  if [[ ! -r root/nix/release.json ]] || ! command -v jq >/dev/null 2>&1; then
    emit "ROOT_INTEGRATION" "repository" "System Manager candidate policy" \
      "UNKNOWN" "UNKNOWN" "HOLD" "repo:root/system-manager/README.md" \
      "The machine-readable release pin or jq is unavailable."
    return
  fi

  nix_args=(
    --extra-experimental-features "nix-command flakes"
    eval
    --json
    --no-write-lock-file
  )
  if [[ "$offline" -eq 1 ]]; then
    nix_args+=(--offline)
  fi
  manifest="$(
    timeout 60s nix "${nix_args[@]}" \
      .#lib.dgxRootManagerManifest.aarch64-linux 2>/dev/null || true
  )"
  if ! jq -e '.schemaVersion == 1' >/dev/null 2>&1 <<<"$manifest"; then
    emit "ROOT_INTEGRATION" "repository" "System Manager candidate policy" \
      "INVALID_OR_UNAVAILABLE" "review manifest" "HOLD" \
      "repo:flake.nix" \
      "The inert root-manager manifest did not evaluate; no activation was attempted."
    return
  fi

  manager_node="$(root_input_node "system-manager")"
  manager_ref="$(lock_value "$manager_node" \
    '.nodes[$node].locked.ref // .nodes[$node].original.ref')"
  manager_locked_rev="$(lock_value "$manager_node" '.nodes[$node].locked.rev')"
  manager_version="$(jq -r '.manager.version // empty' <<<"$manifest")"
  manager_branch="$(jq -r '.manager.branch // empty' <<<"$manifest")"
  manager_rev="$(jq -r '.manager.rev // empty' <<<"$manifest")"
  private_nix_version="$(jq -r '.privateNixRuntime.version // empty' <<<"$manifest")"
  private_nix_rev="$(jq -r '.privateNixRuntime.rev // empty' <<<"$manifest")"
  manager_patch_name="$(jq -r '.manager.patches[0].name // empty' <<<"$manifest")"
  manager_patch_hash="$(jq -r '.manager.patches[0].sha256 // empty' <<<"$manifest")"
  release_version="$(jq -r '.version // empty' root/nix/release.json)"
  release_rev="$(jq -r '.tagCommit // empty' root/nix/release.json)"
  test_result="$(jq -r '.isolatedTest.result // empty' <<<"$manifest")"
  registration_test_result="$(
    jq -r '.registration.isolatedLifecycleTest.result // empty' <<<"$manifest"
  )"
  registration_test_matches="$(
    jq -r '.registration.isolatedLifecycleTest.matchesCurrent // false' <<<"$manifest"
  )"
  generation_switch_test_result="$(
    jq -r '.registration.guardedGenerationSwitch.isolatedTransactionTest.result // empty' <<<"$manifest"
  )"
  generation_switch_test_matches="$(
    jq -r '.registration.guardedGenerationSwitch.isolatedTransactionTest.matchesCurrent // false' <<<"$manifest"
  )"
  boot_persistence_test_result="$(
    jq -r '.bootPersistence.isolatedTransactionTest.result // empty' <<<"$manifest"
  )"
  boot_persistence_test_matches="$(
    jq -r '.bootPersistence.isolatedTransactionTest.matchesCurrent // false' <<<"$manifest"
  )"
  reboot_recovery_test_result="$(
    jq -r '.bootPersistence.rebootRecovery.isolatedTransactionTest.result // empty' <<<"$manifest"
  )"
  reboot_recovery_test_matches="$(
    jq -r '.bootPersistence.rebootRecovery.isolatedTransactionTest.matchesCurrent // false' <<<"$manifest"
  )"
  reboot_recovery_status="$(
    jq -r '.bootPersistence.rebootRecovery.status // empty' <<<"$manifest"
  )"
  live_registration_host="$(
    jq -r '.registration.guardedFirstGeneration.liveRegistration.host // empty' <<<"$manifest"
  )"
  live_registration_state="$(
    jq -r '.registration.guardedFirstGeneration.liveRegistration.stateClass // empty' <<<"$manifest"
  )"
  live_switch_host="$(
    jq -r '.registration.guardedGenerationSwitch.liveSwitch.host // empty' <<<"$manifest"
  )"
  live_switch_state="$(
    jq -r '.registration.guardedGenerationSwitch.liveSwitch.stateClass // empty' <<<"$manifest"
  )"
  live_boot_host="$(
    jq -r '.bootPersistence.liveActivation.host // empty' <<<"$manifest"
  )"
  live_boot_state="$(
    jq -r '.bootPersistence.liveActivation.stateClass // empty' <<<"$manifest"
  )"
  generation_one_output="$(
    jq -r '.registration.guardedGenerationSwitch.exactCandidates.generationOne // empty' <<<"$manifest"
  )"
  generation_two_output="$(
    jq -r '.registration.guardedGenerationSwitch.exactCandidates.generationTwo // empty' <<<"$manifest"
  )"
  generation_three_output="$(
    jq -r '.bootPersistence.exactCandidates.generationThree // empty' <<<"$manifest"
  )"

  current="system-manager=${manager_version:-UNKNOWN}@$(short_rev "$manager_rev");private-nix=${private_nix_version:-UNKNOWN}@$(short_rev "$private_nix_rev");patch=${manager_patch_name:-MISSING}@${manager_patch_hash:0:12};container-test=${test_result:-UNKNOWN};registration-test=${registration_test_result:-UNKNOWN};registration-match=${registration_test_matches:-UNKNOWN};generation-switch-test=${generation_switch_test_result:-UNKNOWN};generation-switch-match=${generation_switch_test_matches:-UNKNOWN};boot-test=${boot_persistence_test_result:-UNKNOWN};boot-match=${boot_persistence_test_matches:-UNKNOWN};reboot-recovery=${reboot_recovery_test_result:-UNKNOWN};reboot-recovery-match=${reboot_recovery_test_matches:-UNKNOWN};reboot-recovery-status=${reboot_recovery_status:-UNKNOWN};live-state=${live_boot_state:-${live_switch_state:-UNKNOWN}}"
  candidate="locked-branch=${manager_ref:-UNKNOWN};verified-nix=${release_version:-UNKNOWN}"
  policy_ok="$(jq -r '
    (.system == "aarch64-linux") and
    (.manager.activated == false) and
    ((.manager.patches | length) == 1) and
    (.manager.patches[0].name == "skip-empty-tmpfiles") and
    (.manager.patches[0].path == "patches/system-manager/skip-empty-tmpfiles.patch") and
    (.manager.patches[0].sha256 == "32756de30fd5730ebe60cce6ef89fc924ccd4eb3530e21ceb53fdf6073ba0e9a") and
    (.registration.performed == false) and
    (.registration.isolatedLifecycleTest.result == "passed") and
    (.registration.isolatedLifecycleTest.matchesCurrent == true) and
    (.registration.isolatedLifecycleTest.evidence == "root/system-manager/validation/2026-09-01-registration-container-test.md") and
    (.registration.isolatedLifecycleTest.hostRegistrationPerformed == false) and
    (.registration.isolatedLifecycleTest.hostActivationPerformed == false) and
    (.registration.isolatedLifecycleTest.hostPostflight == "clean") and
    (.registration.guardedFirstGeneration.status == "completed-first-generation-registration-retained") and
    (.registration.guardedFirstGeneration.liveRegistrationPerformed == true) and
    (.registration.guardedFirstGeneration.liveRegistration.host == "sparkle-01") and
    (.registration.guardedFirstGeneration.liveRegistration.stateClass == "ACTIVE_REGISTERED_RETAINED") and
    (.registration.guardedFirstGeneration.liveRegistration.evidence == "root/system-manager/validation/2026-09-01-first-registration-host-attempt-3.md") and
    (.registration.guardedFirstGeneration.liveRegistration.localConsoleConfirmed == true) and
    (.registration.guardedFirstGeneration.liveRegistration.rollbackDisarmed == true) and
    (.registration.guardedGenerationSwitch.status == "live-generation-two-registered-retained") and
    (.registration.guardedGenerationSwitch.currentHostState == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED") and
    (.registration.guardedGenerationSwitch.hostGenerationTwoRetentionPerformed == true) and
    (.registration.guardedGenerationSwitch.liveSwitchPerformed == true) and
    (.registration.guardedGenerationSwitch.livePilot.status == "generation-two-retained-after-console-confirmation") and
    (.registration.guardedGenerationSwitch.livePilot.hostGenerationTwoRetentionPerformed == true) and
    (.registration.guardedGenerationSwitch.livePilot.liveSwitchPerformed == true) and
    (.registration.guardedGenerationSwitch.liveSwitch.host == "sparkle-01") and
    (.registration.guardedGenerationSwitch.liveSwitch.stateClass == "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED") and
    (.registration.guardedGenerationSwitch.liveSwitch.evidence == "root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md") and
    (.registration.guardedGenerationSwitch.liveSwitch.localConsoleConfirmed == true) and
    (.registration.guardedGenerationSwitch.liveSwitch.rollbackDisarmed == true) and
    (.registration.guardedGenerationSwitch.liveSwitch.rollbackServiceRan == false) and
    (.registration.guardedGenerationSwitch.liveSwitch.bootLinkCreated == false) and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.result == "passed") and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.matchesCurrent == true) and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.evidence == "root/system-manager/validation/2026-09-02-generation-switch-transaction-container-test.md") and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.hostRegistrationPerformed == false) and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.hostActivationPerformed == false) and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.hostCandidateRetentionPerformed == false) and
    (.registration.guardedGenerationSwitch.isolatedTransactionTest.hostPostflight == "clean") and
    (.bootPersistence.status == "live-generation-three-boot-linked-retained") and
    (.bootPersistence.currentHostState == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED") and
    (.bootPersistence.retention.hostCreated == true) and
    (.bootPersistence.isolatedTransactionTest.result == "passed") and
    (.bootPersistence.isolatedTransactionTest.matchesCurrent == true) and
    (.bootPersistence.isolatedTransactionTest.hostPostflight == "clean") and
    (.bootPersistence.livePilot.status == "generation-three-retained-after-console-confirmation") and
    (.bootPersistence.livePilot.hostCandidateRetentionPerformed == true) and
    (.bootPersistence.livePilot.hostRegistrationPerformed == true) and
    (.bootPersistence.livePilot.hostActivationPerformed == true) and
    (.bootPersistence.livePilot.hostBootLinkCreated == true) and
    (.bootPersistence.livePilot.hostRebootPerformed == false) and
    (.bootPersistence.liveActivation.host == "sparkle-01") and
    (.bootPersistence.liveActivation.stateClass == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED") and
    (.bootPersistence.liveActivation.evidence == "root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md") and
    (.bootPersistence.liveActivation.localConsoleConfirmed == true) and
    (.bootPersistence.liveActivation.rollbackDisarmed == true) and
    (.bootPersistence.liveActivation.rollbackServiceRan == false) and
    (.bootPersistence.liveActivation.protectedServicesUnchanged == true) and
    (.bootPersistence.liveActivation.bootLinkCreated == true) and
    (.bootPersistence.liveActivation.managedPathCount == 6) and
    (.bootPersistence.liveActivation.managedServiceCount == 3) and
    (.bootPersistence.liveActivation.hostRebootPerformed == false) and
    (.bootPersistence.rebootRecovery.status == "live-recovery-designed-host-not-armed") and
    (.bootPersistence.rebootRecovery.requiredHostState == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED") and
    (.bootPersistence.rebootRecovery.postbootAuditor.stateClass == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_REBOOTED_RETAINED") and
    (.bootPersistence.rebootRecovery.postbootAuditor.requiresManagerAndCanaryActive == true) and
    (.bootPersistence.rebootRecovery.postbootAuditor.requiresReactivationTargetInactive == true) and
    (.bootPersistence.rebootRecovery.productionBundle.delayMinutes == 10) and
    (.bootPersistence.rebootRecovery.confirmation.phrase == "KEEP REBOOTED GENERATION THREE") and
    (.bootPersistence.rebootRecovery.rollback.cleanupPhrase == "CLEAN ROLLED BACK REBOOT RECOVERY") and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.result == "passed") and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.matchesCurrent == true) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.subtestCount == 13) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.evidence == "root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md") and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.disposableRestarts == 2) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.provesAutomaticRollback == true) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.provesConfirmedRetention == true) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.provesExactCleanup == true) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.provesSameBootDisarm == true) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.hostRecoveryArmed == false) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.hostRebootPerformed == false) and
    (.bootPersistence.rebootRecovery.isolatedTransactionTest.hostPostflight == "clean") and
    (.bootPersistence.rebootRecovery.livePilot.status == "repository-design-complete-host-not-armed") and
    (.bootPersistence.rebootRecovery.livePilot.pilotProgram.actions == [
      "arm",
      "disarm-preboot",
      "status",
      "confirm",
      "verify-rolled-back",
      "cleanup-rolled-back"
    ]) and
    (.bootPersistence.rebootRecovery.livePilot.pilotProgram.performsReboot == false) and
    (.bootPersistence.rebootRecovery.livePilot.requiresSeparateRebootAuthorization == true) and
    (.bootPersistence.rebootRecovery.livePilot.hostSnapshotCreated == false) and
    (.bootPersistence.rebootRecovery.livePilot.hostRecoveryArmed == false) and
    (.bootPersistence.rebootRecovery.livePilot.hostRebootPerformed == false) and
    (.bootPersistence.rebootRecovery.hostRecoveryArmed == false) and
    (.bootPersistence.rebootRecovery.hostRebootPerformed == false) and
    (.pilotRetention.path == "/nix/var/nix/gcroots/dgx-setup-root-canary-pilot") and
    (.pilotRetention.created == false) and
    (.pilotRetention.requiredForLowLevelActivation == true) and
    (.pilotRetention.removeOnlyAfterDeactivation == true) and
    (.pilotRetention.replacesRegistration == false) and
    (.isolatedTest.result == "passed") and
    (.isolatedTest.evidence == "root/system-manager/validation/2026-08-24-container-test.md") and
    (.isolatedTest.matchesCurrent == true) and
    (.isolatedTest.hostActivationPerformed == false) and
    (.isolatedTest.hostPostflight == "clean") and
    (.privateNixRuntime.ownsHostInstallation == false) and
    (.managerState.path == "/var/lib/system-manager/state/system-manager-state.json") and
    (.policy.ownsNix == false) and
    (.policy.ownsUsers == false) and
    (.policy.enablesSetuidWrappers == false) and
    (.policy.exportsGlobalPath == false) and
    (.policy.linksCurrentSystem == false) and
    (.policy.replaceExisting == false) and
    (.policy.startsAtBoot == false) and
    (.policy.globalPackages == []) and
    (.policy.managedTmpfiles == []) and
    (.policy.invokesGlobalTmpfiles == false) and
    (.policy.tmpfilesMode == "skip-when-empty") and
    (.policy.ports == []) and
    (.policy.etcEntries == ["dgx-setup/canary", "systemd/system"]) and
    (.policy.services == [
      "dgx-setup-canary.service",
      "sysinit-reactivation.target",
      "system-manager.target"
    ])
  ' <<<"$manifest")"

  root_output="$(jq -r '.manager.rootOutputPath // empty' <<<"$manifest")"
  registration_mode=unregistered
  other_root_output=
  middle_root_output=
  if [[ "$host_name" == "$live_boot_host" &&
        "$live_boot_state" == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED" ]]; then
    root_output="$generation_three_output"
    other_root_output="$generation_one_output"
    middle_root_output="$generation_two_output"
    registration_mode=registered-third-boot
  elif [[ "$host_name" == "$live_switch_host" &&
        "$live_switch_state" == "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED" ]]; then
    root_output="$generation_two_output"
    other_root_output="$generation_one_output"
    registration_mode=registered-second
  elif [[ "$host_name" == "$live_registration_host" &&
        "$live_registration_state" == "ACTIVE_REGISTERED_RETAINED" ]]; then
    registration_mode=registered-first
  fi
  live_state="$(
    "$repo_dir/scripts/audit-root-canary-state.sh" \
      "$root_output" "$registration_mode" "$other_root_output" \
      "$middle_root_output" 2>/dev/null ||
      true
  )"

  if [[ -z "$manager_node" || "$manager_rev" != "$manager_locked_rev" ||
        "$manager_branch" != "$manager_ref" ]]; then
    status="HOLD"
    detail="Manifest and System Manager lock metadata disagree; no activation was attempted."
  elif [[ "$private_nix_version" != "$release_version" ||
          "$private_nix_rev" != "$release_rev" ]]; then
    status="HOLD"
    detail="System Manager's private Nix engine differs from the verified repository release pin."
  elif [[ "$policy_ok" != "true" ]]; then
    status="HOLD"
    detail="The candidate exceeds the approved inert ownership policy."
  elif [[ "$host_name" == "$live_boot_host" &&
          "$live_state" == "ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED" ]]; then
    status="CURRENT"
    detail="The exact tests and manifest agree; sparkle-01 retains registered/live generation three, all three numbered generations and direct pilot roots, the upstream generation-three root, and the one declarative boot edge. Persistent first-reboot recovery passed its current 13-subtest lifecycle and its no-reboot live helpers are policy-pinned; the host recovery surface remains unarmed and the first real host reboot remains unperformed and separately gated."
  elif [[ "$host_name" == "$live_boot_host" ]]; then
    status="HOLD"
    detail="${live_state#DRIFT|}"
    detail="${detail:-The declared pilot host does not match its retained generation-three boot-linked state.}"
  elif [[ "$host_name" == "$live_switch_host" &&
          "$live_state" == "ACTIVE_REGISTERED_GENERATION_TWO_RETAINED" ]]; then
    status="CURRENT"
    detail="The exact tests and manifest agree; sparkle-01 retains registered/live generation two, registered generation one, both direct pilot roots, and the upstream generation-two root without a boot link."
  elif [[ "$host_name" == "$live_switch_host" ]]; then
    status="HOLD"
    detail="${live_state#DRIFT|}"
    detail="${detail:-The declared pilot host does not match its retained generation-two state.}"
  elif [[ "$host_name" == "$live_registration_host" &&
          "$live_state" == "ACTIVE_REGISTERED_RETAINED" ]]; then
    status="CURRENT"
    detail="The exact tests and manifest agree; sparkle-01 retains the exact five-path/three-service activation, generation one, upstream extra root, and pilot root without a boot link."
  elif [[ "$host_name" == "$live_registration_host" ]]; then
    status="HOLD"
    detail="${live_state#DRIFT|}"
    detail="${detail:-The declared pilot host does not match its retained registered state.}"
  elif [[ "$live_state" == "ACTIVE_RETAINED" ]]; then
    status="CURRENT"
    detail="The exact five-path/three-service canary is retained active and directly rooted on this host without registration or a boot link."
  elif [[ "$live_state" == "INACTIVE_EMPTY" ]]; then
    status="CURRENT"
    detail="The only live artifact is the exact empty version-0 state left by deactivation; registration and managed paths are absent."
  elif [[ "$live_state" == "INACTIVE_ABSENT" ]]; then
    status="CURRENT"
    detail="Manifest, patch, lock, private Nix pin, and disposable-test evidence agree; no live root-manager artifact was detected."
  else
    status="HOLD"
    detail="${live_state#DRIFT|}"
    detail="${detail:-The live root-manager state could not be classified safely.}"
  fi

  emit "ROOT_INTEGRATION" "repository" "System Manager candidate policy" \
    "$current" "$candidate" "$status" \
    "repo:root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md" \
    "$detail"
}

printf '# dgx-spark-ops update audit\n'
printf '# timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '# repository=%s\n' "$repo_dir"
if [[ "$offline" -eq 1 ]]; then
  printf '# mode=offline\n'
else
  printf '# mode=online\n'
fi
printf 'SCOPE\tOWNER\tCOMPONENT\tCURRENT\tCANDIDATE\tSTATUS\tSOURCE\tDETAIL\n'

host_name="$(hostname 2>/dev/null || printf '%s' "UNKNOWN")"
architecture="$(uname -m 2>/dev/null || printf '%s' "UNKNOWN")"
kernel="$(uname -r 2>/dev/null || printf '%s' "UNKNOWN")"
os_name="$(
  sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null |
    head -n 1 |
    sed 's/^"//; s/"$//'
)"
emit "HOST" "local" "hostname" "$host_name" "n/a" "INFO" "local:hostname" \
  "Audit target."
emit "HOST" "local" "architecture" "${architecture:-UNKNOWN}" \
  "aarch64" "INFO" "local:uname" "DGX Spark fleet target architecture."
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "DGX OS" \
  "${os_name:-UNKNOWN}" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/dgx/dgx-spark/" \
  "Dashboard/vendor guidance owns applicability; package indexes were untouched."
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "kernel" \
  "$kernel" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/dgx/dgx-spark/" \
  "Do not compare against a generic Ubuntu kernel channel."

gpu_query="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true)"
if [[ -n "$gpu_query" ]]; then
  gpu_names="$(printf '%s\n' "$gpu_query" | awk -F', *' '{print $1}' | paste -sd ';' -)"
  driver_versions="$(printf '%s\n' "$gpu_query" | awk -F', *' '{print $2}' | sort -u | paste -sd ';' -)"
  nvidia_output="$(nvidia-smi 2>/dev/null || true)"
  cuda_version="$(
    printf '%s\n' "$nvidia_output" |
      sed -n 's/.*CUDA Version:[[:space:]]*\([^ |]*\).*/\1/p' |
      head -n 1
  )"
else
  gpu_names="UNKNOWN"
  driver_versions="UNKNOWN"
  cuda_version="UNKNOWN"
fi
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "GPU" "$gpu_names" \
  "CHECK_DASHBOARD" "MANUAL" "local:nvidia-smi" \
  "Hardware inventory; no GPU settings were changed."
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "NVIDIA driver" \
  "$driver_versions" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/dgx/dgx-spark/" \
  "The newest generic NVIDIA driver is not automatically the applicable one."
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "CUDA compatibility" \
  "${cuda_version:-UNKNOWN}" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/dgx/dgx-spark/" \
  "This is the driver-reported CUDA compatibility level."

docker_client="$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)"
compose_version="$(docker compose version --short 2>/dev/null || true)"
toolkit_version="$(
  nvidia-ctk --version 2>/dev/null |
    sed -nE '1s/.*version[[:space:]]+//p' || true
)"
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "Docker client" \
  "${docker_client:-NOT_FOUND}" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/dgx/dgx-spark/" "Vendor-owned package."
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "Docker Compose" \
  "${compose_version:-NOT_FOUND}" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/dgx/dgx-spark/" "Vendor-owned package."
emit "NVIDIA_SUBSTRATE" "NVIDIA/DGX Dashboard" "NVIDIA Container Toolkit" \
  "${toolkit_version:-NOT_FOUND}" "CHECK_DASHBOARD" "MANUAL" \
  "https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/" \
  "Keep compatible with the DGX OS driver and Docker packages."

docker_server="$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"
if [[ -n "$docker_server" ]]; then
  docker_access_detail="Current user can access Docker daemon version $docker_server."
else
  docker_access_detail="Current user cannot access the daemon; no sudo or group change was attempted."
fi
emit "HOST" "reviewed bootstrap" "Docker daemon access" \
  "${docker_server:-DENIED_OR_INACTIVE}" "n/a" "INFO" "local:docker-info" \
  "$docker_access_detail"

# Tailscale is deliberately audited as the fleet access plane, not as a generic
# user app or NVIDIA substrate package. The existing apt package is migration
# input. A temporary Nix derivation may be required to prevent a downgrade when
# locked stable Nixpkgs lags the approved release. Before changing this logic or
# the package/service, read references/tailscale.md.
#
# Never print the raw output of status or prefs below: it can identify nodes,
# addresses, or the tailnet. Extract only the explicitly approved fields.
tailscale_path="$(command -v tailscale 2>/dev/null || true)"
tailscale_path_target="$(readlink -f "$tailscale_path" 2>/dev/null || true)"
tailscale_daemon_path="$(command -v tailscaled 2>/dev/null || true)"
tailscale_deb_version="$(
  dpkg-query -W -f='${Version}' tailscale 2>/dev/null || true
)"
tailscale_deb_arch="$(
  dpkg-query -W -f='${Architecture}' tailscale 2>/dev/null || true
)"
tailscale_current="NOT_FOUND"
tailscale_candidate="UNKNOWN"

if [[ -n "$tailscale_path" ]]; then
  if command -v jq >/dev/null 2>&1; then
    tailscale_current="$(
      tailscale version --json 2>/dev/null |
        jq -r '.short // .majorMinorPatch // empty' 2>/dev/null || true
    )"
  else
    tailscale_current="$(tailscale version 2>/dev/null | head -n 1 || true)"
  fi
  tailscale_current="${tailscale_current:-UNKNOWN}"

  if [[ "$offline" -eq 1 ]]; then
    tailscale_candidate="REMOTE_SUPPRESSED"
    tailscale_status="UNKNOWN"
    tailscale_detail="Offline audit; official stable release was not queried."
  elif command -v jq >/dev/null 2>&1; then
    tailscale_candidate="$(
      timeout 30s tailscale version --json --upstream --track stable 2>/dev/null |
        jq -r '.upstream // empty' 2>/dev/null || true
    )"
    if [[ -n "$tailscale_candidate" ]]; then
      tailscale_status="$(version_status "$tailscale_current" "$tailscale_candidate")"
      if [[ "$tailscale_status" == "AHEAD" ]]; then
        tailscale_status="HOLD"
        tailscale_detail="Official candidate is older than installed; refuse a downgrade."
      elif [[ "$tailscale_status" == "CURRENT" ]]; then
        tailscale_detail="Installed release matches official stable; repository package evidence and active service ownership are audited separately."
      else
        tailscale_detail="Availability only; review ARM64 artifact, checksum, changelog, security bulletins, SBOM, unit, and rollback."
      fi
    else
      tailscale_candidate="UNKNOWN"
      tailscale_status="UNKNOWN"
      tailscale_detail="Unable to parse Tailscale's official stable release response."
    fi
  else
    tailscale_status="UNKNOWN"
    tailscale_detail="jq is unavailable, so the official JSON candidate was not parsed."
  fi
else
  tailscale_status="UNKNOWN"
  tailscale_detail="Tailscale CLI is not on PATH."
fi

if [[ -n "$tailscale_deb_version" ]]; then
  tailscale_binary_owner="manual official apt (migration input)"
  tailscale_installed_detail="deb=${tailscale_deb_version};arch=${tailscale_deb_arch:-UNKNOWN}; daemon=${tailscale_daemon_path:+present}"
elif [[ "$tailscale_path_target" == /nix/store/* ]]; then
  tailscale_binary_owner="repository/Nix"
  tailscale_installed_detail="CLI resolves from the Nix store; verify the active unit separately."
elif [[ -n "$tailscale_path" ]]; then
  tailscale_binary_owner="unclassified host install"
  tailscale_installed_detail="CLI exists outside apt and the Nix store; investigate provenance."
else
  tailscale_binary_owner="repository target"
  tailscale_installed_detail="No installed CLI was detected."
fi
emit "FLEET_ACCESS" "$tailscale_binary_owner" "Tailscale release" \
  "$tailscale_current" "$tailscale_candidate" "$tailscale_status" \
  "https://pkgs.tailscale.com/stable/" "$tailscale_detail $tailscale_installed_detail"

tailscale_nix_eval_args=(
  --extra-experimental-features "nix-command flakes"
  eval --raw --impure --no-write-lock-file
)
if [[ "$offline" -eq 1 ]]; then
  tailscale_nix_eval_args+=(--offline)
fi
tailscale_locked_nixpkgs="UNKNOWN"
tailscale_repo_pin=""
if command -v nix >/dev/null 2>&1 && [[ -r flake.lock ]]; then
  tailscale_locked_nixpkgs="$(
    timeout 60s nix "${tailscale_nix_eval_args[@]}" --expr \
      "let f = builtins.getFlake \"$repo_flake_uri\"; in f.inputs.nixpkgs.legacyPackages.aarch64-linux.tailscale.version" \
      2>/dev/null || true
  )"
  tailscale_locked_nixpkgs="${tailscale_locked_nixpkgs:-UNKNOWN}"
  tailscale_repo_pin="$(
    timeout 60s nix "${tailscale_nix_eval_args[@]}" \
      '.#packages.aarch64-linux.tailscale.version' 2>/dev/null || true
  )"
fi

if [[ "$tailscale_current" =~ ^[0-9] &&
      "$tailscale_locked_nixpkgs" =~ ^[0-9] ]]; then
  tailscale_nixpkgs_status="$(
    version_status "$tailscale_current" "$tailscale_locked_nixpkgs"
  )"
  if [[ "$tailscale_nixpkgs_status" == "AHEAD" ]]; then
    tailscale_nixpkgs_status="HOLD"
    tailscale_nixpkgs_detail="Locked stock package is older than installed Tailscale; a direct substitution would downgrade the access plane."
  else
    tailscale_nixpkgs_detail="Stock package still requires ARM64 build, SBOM, unit, and migration validation."
  fi
else
  tailscale_nixpkgs_status="UNKNOWN"
  tailscale_nixpkgs_detail="Unable to compare installed Tailscale with the locked stock Nixpkgs package."
fi
emit "FLEET_ACCESS" "locked Nixpkgs" "stock Tailscale substitution" \
  "$tailscale_current" "$tailscale_locked_nixpkgs" \
  "$tailscale_nixpkgs_status" "repo:flake.lock" "$tailscale_nixpkgs_detail"

if [[ -z "$tailscale_repo_pin" ]]; then
  tailscale_repo_pin="absent"
  tailscale_repo_status="NOT_PINNED"
  tailscale_repo_detail="No repository Tailscale package output exists yet; apt ownership remains migration input."
elif [[ "$tailscale_repo_pin" =~ ^[0-9] && "$tailscale_candidate" =~ ^[0-9] ]]; then
  tailscale_repo_status="$(version_status "$tailscale_repo_pin" "$tailscale_candidate")"
  if [[ "$tailscale_current" =~ ^[0-9] &&
        "$(version_status "$tailscale_current" "$tailscale_repo_pin")" == "AHEAD" ]]; then
    tailscale_repo_status="HOLD"
    tailscale_repo_detail="Repository pin is older than installed Tailscale; do not activate it."
  elif [[ "$tailscale_repo_status" == "AHEAD" ]]; then
    tailscale_repo_status="HOLD"
    tailscale_repo_detail="Repository pin is ahead of the official stable channel; investigate provenance before activation."
  elif [[ "$tailscale_repo_status" == "UPDATE_AVAILABLE" ]]; then
    tailscale_repo_detail="Repository pin trails official stable; run the checksum-verified updater, then rebuild/review without activation."
  else
    tailscale_repo_detail="Repository pin matches official stable; revalidate its build/SBOM after every change, and treat active service ownership as a separate gate."
  fi
else
  tailscale_repo_status="UNKNOWN"
  tailscale_repo_detail="Repository Tailscale pin could not be compared."
fi
emit "FLEET_ACCESS" "repository" "Tailscale package pin" \
  "$tailscale_repo_pin" "$tailscale_candidate" "$tailscale_repo_status" \
  "repo:flake.nix" "$tailscale_repo_detail"

tailscale_active="$(systemctl is-active tailscaled.service 2>/dev/null || true)"
tailscale_enabled="$(systemctl is-enabled tailscaled.service 2>/dev/null || true)"
tailscale_wanted_by="$(
  systemctl show tailscaled.service -p WantedBy --value 2>/dev/null || true
)"
tailscale_fragment="$(
  systemctl show tailscaled.service -p FragmentPath --value 2>/dev/null || true
)"
tailscale_fragment_target="$(readlink -f "$tailscale_fragment" 2>/dev/null || true)"
case "$tailscale_fragment_target" in
  /nix/store/*)
    tailscale_unit_owner="repository/Nix"
    ;;
  /usr/lib/systemd/* | /lib/systemd/*)
    tailscale_unit_owner="host package (migration input)"
    ;;
  "")
    tailscale_unit_owner="not found"
    ;;
  *)
    tailscale_unit_owner="review required"
    ;;
esac
emit "FLEET_ACCESS" "$tailscale_unit_owner" "tailscaled.service" \
  "active=${tailscale_active:-UNKNOWN};enabled=${tailscale_enabled:-UNKNOWN};wanted-by=${tailscale_wanted_by:-UNKNOWN}" \
  "multi-user.target" "INFO" "local:systemctl-show" \
  "Headless mode must retain this service; the audit did not reload, restart, enable, or disable it."

tailscale_backend="UNKNOWN"
tailscale_self_online="UNKNOWN"
tailscale_want_running="UNKNOWN"
tailscale_run_ssh="UNKNOWN"
if [[ -n "$tailscale_path" ]] && command -v jq >/dev/null 2>&1; then
  tailscale_backend="$(
    timeout 10s tailscale status --json 2>/dev/null |
      jq -r '.BackendState // "UNKNOWN"' 2>/dev/null || true
  )"
  tailscale_self_online="$(
    timeout 10s tailscale status --json 2>/dev/null |
      jq -r 'if .Self.Online == null then "UNKNOWN" else (.Self.Online | tostring) end' \
        2>/dev/null || true
  )"
  tailscale_want_running="$(
    timeout 10s tailscale debug prefs 2>/dev/null |
      jq -r 'if .WantRunning == null then "UNKNOWN" else (.WantRunning | tostring) end' \
        2>/dev/null || true
  )"
  tailscale_run_ssh="$(
    timeout 10s tailscale debug prefs 2>/dev/null |
      jq -r 'if .RunSSH == null then "UNKNOWN" else (.RunSSH | tostring) end' \
        2>/dev/null || true
  )"
fi
emit "FLEET_ACCESS" "mutable daemon/control-plane state" \
  "Tailscale runtime and SSH" \
  "backend=${tailscale_backend:-UNKNOWN};online=${tailscale_self_online:-UNKNOWN};WantRunning=${tailscale_want_running:-UNKNOWN};RunSSH=${tailscale_run_ssh:-UNKNOWN}" \
  "documented desired state" "INFO" "local:sanitized-tailscale-cli" \
  "Only approved booleans/state labels are emitted; node, address, identity, and tailnet data were discarded."

if [[ -x /nix/nix-installer ]]; then
  installer_version="$(/nix/nix-installer --version 2>/dev/null || true)"
else
  installer_version="NOT_FOUND"
fi
nix_profile_target="$(readlink -f /nix/var/nix/profiles/default 2>/dev/null || true)"
nix_root_user_profile_target="$(
  readlink -f /nix/var/nix/profiles/per-user/root/profile 2>/dev/null || true
)"
daemon_state="$(systemctl show nix-daemon.service -p ActiveState --value 2>/dev/null || true)"
daemon_reload="$(systemctl show nix-daemon.service -p NeedDaemonReload --value 2>/dev/null || true)"
emit "NIX_RUNTIME" "official nix-installer" "installer provenance" \
  "${installer_version:-UNKNOWN}" "n/a" "INFO" \
  "https://github.com/NixOS/nix-installer" \
  "Devbox triggered this installer; Devbox does not own runtime updates."
emit "NIX_RUNTIME" "root Nix profile" "default profile target" \
  "${nix_profile_target:-UNKNOWN}" "n/a" "INFO" "local:readlink" \
  "Active machine-wide runtime profile target."
if [[ -z "$nix_root_user_profile_target" ]]; then
  root_user_profile_detail="No root-user profile target was resolved."
elif [[ "$nix_root_user_profile_target" != "$nix_profile_target" ]]; then
  root_user_profile_detail="This is distinct from the active default profile; retain and classify it before garbage collection or rollback."
else
  root_user_profile_detail="This resolves to the same environment as the active default profile."
fi
emit "NIX_RUNTIME" "root user profile" "root-user profile target" \
  "${nix_root_user_profile_target:-UNKNOWN}" "n/a" "INFO" "local:readlink" \
  "$root_user_profile_detail"
emit "NIX_RUNTIME" "systemd/root Nix profile" "nix-daemon" \
  "state=${daemon_state:-UNKNOWN};need-reload=${daemon_reload:-UNKNOWN}" \
  "n/a" "INFO" "local:systemctl-show" \
  "Audit did not reload or restart the daemon."

if command -v nix >/dev/null 2>&1; then
  nix_version="$(nix --version 2>/dev/null | awk '{print $NF}')"
  if [[ "$offline" -eq 1 ]]; then
    emit "NIX_RUNTIME" "Nixpkgs manual fallback pointer" \
      "Nix upgrade-nix fallback candidate" "$nix_version" \
      "REMOTE_SUPPRESSED" "UNKNOWN" \
      "https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/tools/nix-fallback-paths.nix" \
      "Offline audit; the fallback pointer used by upgrade-nix was not queried."
    emit "NIX_RUNTIME" "upstream Nix release" "Nix stable release" \
      "$nix_version" "REMOTE_SUPPRESSED" "UNKNOWN" \
      "https://github.com/NixOS/nix/tags" \
      "Offline audit; stable tags and the aarch64-linux release artifact were not queried."
  else
    nix_fallback_output="$(
      timeout 120s nix \
        --extra-experimental-features "nix-command flakes" \
        upgrade-nix --dry-run \
        --profile /nix/var/nix/profiles/default \
        --refresh 2>&1 || true
    )"
    nix_fallback_candidate="$(
      printf '%s\n' "$nix_fallback_output" |
        sed -nE 's/.*would (upgrade|downgrade)( Nix)? to version ([0-9][0-9.]*).*/\3/ip' |
        head -n 1
    )"
    if [[ -n "$nix_fallback_candidate" ]]; then
      nix_fallback_status="$(version_status "$nix_version" "$nix_fallback_candidate")"
      if [[ "$nix_fallback_status" == "AHEAD" ]]; then
        nix_fallback_status="HOLD"
        nix_fallback_detail="The manually maintained Nixpkgs fallback pointer is older than installed Nix. upgrade-nix does not compare versions and would perform this downgrade; do not run it."
      elif [[ "$nix_fallback_status" == "CURRENT" ]]; then
        nix_fallback_detail="The fallback pointer happens to match installed Nix; it is not proof that this is the latest upstream stable release."
      else
        nix_fallback_detail="Fallback candidate only; compare it with upstream stable and verify the aarch64-linux artifact plus rollback before applying."
      fi
      emit "NIX_RUNTIME" "Nixpkgs manual fallback pointer" \
        "Nix upgrade-nix fallback candidate" "$nix_version" \
        "$nix_fallback_candidate" "$nix_fallback_status" \
        "https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/tools/nix-fallback-paths.nix" \
        "$nix_fallback_detail"
    else
      nix_fallback_excerpt="$(printf '%s\n' "$nix_fallback_output" | tail -n 2)"
      emit "NIX_RUNTIME" "Nixpkgs manual fallback pointer" \
        "Nix upgrade-nix fallback candidate" "$nix_version" \
        "UNKNOWN" "UNKNOWN" \
        "https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/tools/nix-fallback-paths.nix" \
        "Unable to parse the fallback-pointer dry-run: $nix_fallback_excerpt"
    fi

    nix_release_tags="$(
      timeout 30s git \
        -c http.lowSpeedLimit=1 \
        -c http.lowSpeedTime=15 \
        ls-remote --tags --refs https://github.com/NixOS/nix.git \
        'refs/tags/*' 2>/dev/null || true
    )"
    nix_upstream_candidate="$(
      printf '%s\n' "$nix_release_tags" |
        awk '{sub("refs/tags/", "", $2); print $2}' |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
        sort -V |
        tail -n 1
    )"
    if [[ -n "$nix_upstream_candidate" ]]; then
      nix_upstream_status="$(version_status "$nix_version" "$nix_upstream_candidate")"
      nix_release_artifact="https://releases.nixos.org/nix/nix-${nix_upstream_candidate}/nix-${nix_upstream_candidate}-aarch64-linux.tar.xz"
      if timeout 30s curl --fail --silent --show-error --head --location \
        "$nix_release_artifact" >/dev/null 2>&1; then
        nix_artifact_detail="The official aarch64-linux binary artifact exists."
      else
        nix_artifact_detail="The official aarch64-linux binary artifact could not be verified; hold any update."
        if [[ "$nix_upstream_status" == "UPDATE_AVAILABLE" ]]; then
          nix_upstream_status="HOLD"
        fi
      fi
      if [[ "$nix_upstream_status" == "AHEAD" ]]; then
        nix_upstream_status="HOLD"
        nix_upstream_detail="Installed Nix is ahead of the newest final upstream tag; investigate provenance and do not downgrade."
      elif [[ "$nix_upstream_status" == "CURRENT" ]]; then
        nix_upstream_detail="Installed Nix matches the newest final upstream tag."
      else
        nix_upstream_detail="A real upstream update is available; the stale fallback pointer cannot install it, so use only a separately validated explicit update path."
      fi
      emit "NIX_RUNTIME" "upstream Nix release" "Nix stable release" \
        "$nix_version" "$nix_upstream_candidate" "$nix_upstream_status" \
        "$nix_release_artifact" \
        "$nix_upstream_detail $nix_artifact_detail"
    else
      emit "NIX_RUNTIME" "upstream Nix release" "Nix stable release" \
        "$nix_version" "UNKNOWN" "UNKNOWN" \
        "https://github.com/NixOS/nix/tags" \
        "Unable to determine the newest final semantic release tag."
    fi
  fi

  nix_repo_release_file="root/nix/release.json"
  if [[ -r "$nix_repo_release_file" ]] && command -v jq >/dev/null 2>&1; then
    nix_repo_candidate="$(jq -r '.version // empty' "$nix_repo_release_file")"
    nix_repo_store_path="$(jq -r '.storePath // empty' "$nix_repo_release_file")"
    nix_repo_artifact="$(jq -r '.artifactUrl // empty' "$nix_repo_release_file")"
    nix_repo_declared_store="$(
      timeout 30s nix eval --impure --raw --expr \
        '(import ./root/nix/store-paths.nix).aarch64-linux' 2>/dev/null || true
    )"
    if [[ "$nix_repo_candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ &&
          "$nix_repo_store_path" =~ ^/nix/store/[0-9a-z]{32}-nix-[0-9.]+$ &&
          "$nix_repo_declared_store" == "$nix_repo_store_path" ]]; then
      nix_repo_status="$(version_status "$nix_version" "$nix_repo_candidate")"
      nix_repo_profile_active=0
      if [[ "$nix_profile_target" == /nix/store/* ]]; then
        nix_profile_references="$(
          nix-store --query --references "$nix_profile_target" 2>/dev/null || true
        )"
        if grep -Fqx "$nix_repo_store_path" <<<"$nix_profile_references"; then
          nix_repo_profile_active=1
        fi
      fi
      if [[ "$nix_repo_status" == "AHEAD" ]]; then
        nix_repo_status="HOLD"
        nix_repo_detail="Repository candidate is older than installed Nix; refuse a downgrade."
      elif [[ "$offline" -eq 0 && -n "${nix_upstream_candidate:-}" &&
              "$nix_repo_candidate" != "$nix_upstream_candidate" ]]; then
        nix_repo_status="HOLD"
        nix_repo_detail="Repository candidate does not match the newest final upstream tag; re-audit before use."
      elif [[ "$offline" -eq 1 ]]; then
        if [[ "$nix_repo_status" == "CURRENT" &&
              "$nix_repo_profile_active" -eq 1 ]]; then
          nix_repo_detail="Exact release/store-path files agree and the root default profile actively references this Nix store path; remote artifact and signed-cache checks were suppressed."
        else
          nix_repo_detail="Exact candidate/store-path files agree; remote artifact and signed-cache checks were suppressed."
        fi
      elif timeout 30s nix path-info --store https://cache.nixos.org/ \
        "$nix_repo_store_path" >/dev/null 2>&1; then
        if [[ "$nix_repo_status" == "CURRENT" &&
              "$nix_repo_profile_active" -eq 1 ]]; then
          nix_repo_detail="Exact release/store-path files agree, match upstream stable, are available from the signed Nix cache, and are active through the root default profile."
        elif [[ "$nix_repo_status" == "CURRENT" ]]; then
          nix_repo_status="HOLD"
          nix_repo_detail="The client version matches the release pin, but the root default profile does not reference its exact Nix store path; investigate runtime ownership."
        else
          nix_repo_detail="Exact candidate/store-path files agree, match upstream stable, and are available from the signed Nix cache. Root-profile activation remains separately unapproved."
        fi
      else
        nix_repo_status="HOLD"
        nix_repo_detail="The exact store path was not verified in the signed Nix cache; do not activate it."
      fi
      emit "NIX_RUNTIME" "repository" "Nix runtime release pin" \
        "$nix_version" "$nix_repo_candidate" "$nix_repo_status" \
        "${nix_repo_artifact:-repo:$nix_repo_release_file}" \
        "$nix_repo_detail"
    else
      emit "NIX_RUNTIME" "repository" "Nix runtime release pin" \
        "$nix_version" "INVALID" "HOLD" "repo:$nix_repo_release_file" \
        "release.json and store-paths.nix are missing, invalid, or inconsistent."
    fi
  else
    emit "NIX_RUNTIME" "repository" "Nix runtime release pin" \
      "$nix_version" "absent" "NOT_PINNED" "repo:root/nix/" \
      "No reviewed repository Nix runtime candidate is available."
  fi
else
  emit "NIX_RUNTIME" "root Nix profile" "Nix runtime" "NOT_FOUND" "UNKNOWN" \
    "UNKNOWN" "https://nixos.org/download/" "Nix is not on PATH."
fi

if [[ -r flake.lock ]] && command -v jq >/dev/null 2>&1; then
  compare_branch_input "nixpkgs" "Nixpkgs"
  compare_branch_input "nixpkgs-apps" "Nixpkgs apps"
  compare_branch_input "home-manager" "Home Manager"
  compare_branch_input "system-manager" "System Manager"
  audit_root_integration

  devbox_current="$(jq -r '.version // empty' packages/devbox/source.json 2>/dev/null || true)"
  if [[ -z "$devbox_current" ]]; then
    emit "NIX_PACKAGE" "repository" "Devbox" "absent" "UNKNOWN" \
      "NOT_PINNED" "repo:packages/devbox/source.json" \
      "The permanent fleet-base Devbox release pin is missing."
  elif [[ "$offline" -eq 1 ]]; then
    emit "NIX_PACKAGE" "repository" "Devbox" "$devbox_current" \
      "REMOTE_SUPPRESSED" "UNKNOWN" \
      "https://github.com/jetify-com/devbox/releases" \
      "Offline audit; final upstream release tags were not queried."
  else
    devbox_tags="$(
      timeout 30s git \
        -c http.lowSpeedLimit=1 \
        -c http.lowSpeedTime=15 \
        ls-remote --tags --refs https://github.com/jetify-com/devbox.git \
        'refs/tags/*' 2>/dev/null || true
    )"
    devbox_latest="$(
      printf '%s\n' "$devbox_tags" |
        awk '{sub("refs/tags/", "", $2); print $2}' |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
        sort -V |
        tail -n 1
    )"
    if [[ -n "$devbox_latest" ]]; then
      devbox_status="$(version_status "$devbox_current" "$devbox_latest")"
      if [[ "$devbox_status" == "AHEAD" ]]; then
        devbox_status="HOLD"
        devbox_detail="The upstream result is older than the repository pin; do not downgrade."
      elif [[ "$devbox_status" == "CURRENT" ]]; then
        devbox_detail="The exact source and Go vendor hashes pin the newest final upstream release."
      else
        devbox_detail="Update the source and Go vendor hashes, then build/SBOM the ARM64 package before activation."
      fi
      emit "NIX_PACKAGE" "repository" "Devbox" "$devbox_current" \
        "$devbox_latest" "$devbox_status" \
        "https://github.com/jetify-com/devbox/releases" "$devbox_detail"
    else
      emit "NIX_PACKAGE" "repository" "Devbox" "$devbox_current" \
        "UNKNOWN" "UNKNOWN" \
        "https://github.com/jetify-com/devbox/releases" \
        "Unable to determine the newest final upstream release tag."
    fi
  fi

  audit_selected_nix_packages

  hypr_node="$(root_input_node "hyprland")"
  if [[ -n "$hypr_node" ]]; then
    hypr_owner="$(lock_value "$hypr_node" '.nodes[$node].locked.owner // .nodes[$node].original.owner')"
    hypr_repo="$(lock_value "$hypr_node" '.nodes[$node].locked.repo // .nodes[$node].original.repo')"
    hypr_ref="$(lock_value "$hypr_node" '.nodes[$node].locked.ref // .nodes[$node].original.ref')"
    hypr_revision="$(lock_value "$hypr_node" '.nodes[$node].locked.rev')"
    hypr_current="${hypr_ref:-detached}@$(short_rev "$hypr_revision")"
    if [[ "$offline" -eq 1 ]]; then
      emit "NIX_REPO" "repository" "Hyprland" "$hypr_current" \
        "REMOTE_SUPPRESSED" "UNKNOWN" "https://github.com/hyprwm/Hyprland/releases" \
        "Offline audit; release tags were not queried."
    else
      hypr_tags="$(
        timeout 30s git \
          -c http.lowSpeedLimit=1 \
          -c http.lowSpeedTime=15 \
          ls-remote --tags --refs https://github.com/hyprwm/Hyprland.git \
          'refs/tags/v*' 2>/dev/null || true
      )"
      hypr_latest="$(
        printf '%s\n' "$hypr_tags" |
          awk '{sub("refs/tags/v", "", $2); print $2}' |
          grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
          sort -V |
          tail -n 1
      )"
      hypr_current_version="${hypr_ref#v}"
      if [[ -n "$hypr_latest" &&
            "$hypr_current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        hypr_status="$(version_status "$hypr_current_version" "$hypr_latest")"
        emit "NIX_REPO" "repository" "Hyprland" "$hypr_current" \
          "v$hypr_latest" "$hypr_status" \
          "https://github.com/hyprwm/Hyprland/releases" \
          "Review release notes, the Glaze patch, portals, ARM64 build, and NVIDIA runtime before activation."
      else
        emit "NIX_REPO" "repository" "Hyprland" "$hypr_current" \
          "UNKNOWN" "UNKNOWN" "https://github.com/hyprwm/Hyprland/releases" \
          "Could not compare the pinned ref with upstream semantic release tags."
      fi
    fi
  else
    emit "NIX_REPO" "repository" "Hyprland" "absent" "UNKNOWN" \
      "NOT_PINNED" "repo:flake.lock" "Root input is not pinned."
  fi

  playbook_node="$(root_input_node "dgx-spark-playbooks")"
  if [[ -n "$playbook_node" ]]; then
    compare_branch_input "dgx-spark-playbooks" "NVIDIA DGX Spark playbooks"
  elif [[ "$offline" -eq 1 ]]; then
    emit "WORKLOAD_SOURCE" "repository" "NVIDIA DGX Spark playbooks" \
      "absent" "REMOTE_SUPPRESSED" "NOT_PINNED" \
      "https://github.com/NVIDIA/dgx-spark-playbooks" \
      "Add an exact source pin before deriving workload configuration."
  else
    playbook_head="$(remote_head "https://github.com/NVIDIA/dgx-spark-playbooks.git" "HEAD")"
    emit "WORKLOAD_SOURCE" "repository" "NVIDIA DGX Spark playbooks" \
      "absent" "$(short_rev "$playbook_head")" "NOT_PINNED" \
      "https://github.com/NVIDIA/dgx-spark-playbooks" \
      "The displayed head is informational; add an exact reviewed commit pin."
  fi
else
  emit "NIX_REPO" "repository" "flake inputs" "UNKNOWN" "UNKNOWN" "UNKNOWN" \
    "repo:flake.lock" "flake.lock or jq is unavailable."
fi

if command -v codex >/dev/null 2>&1; then
  codex_version="$(codex --version 2>/dev/null | awk '{print $NF}')"
else
  codex_version="NOT_FOUND"
fi
if [[ "$offline" -eq 1 || "$codex_version" == "NOT_FOUND" ]]; then
  emit "USER_APP" "manual install; role open" "Codex CLI" "$codex_version" \
    "REMOTE_SUPPRESSED" "UNKNOWN" "https://www.npmjs.com/package/@openai/codex" \
    "Official npm metadata was not queried."
else
  codex_candidate="$(
    curl -fsSL --connect-timeout 10 --max-time 30 \
      'https://registry.npmjs.org/@openai%2Fcodex/latest' 2>/dev/null |
      jq -r '.version // empty' 2>/dev/null || true
  )"
  if [[ -n "$codex_candidate" ]]; then
    codex_status="$(version_status "$codex_version" "$codex_candidate")"
    emit "USER_APP" "manual install; role open" "Codex CLI" "$codex_version" \
      "$codex_candidate" "$codex_status" \
      "https://www.npmjs.com/package/@openai/codex" \
      "Availability only; update ownership has not yet been migrated into Nix."
  else
    emit "USER_APP" "manual install; role open" "Codex CLI" "$codex_version" \
      "UNKNOWN" "UNKNOWN" "https://www.npmjs.com/package/@openai/codex" \
      "Unable to read official npm release metadata."
  fi
fi

chatgpt_packages="$(
  dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null |
    awk 'BEGIN {IGNORECASE=1} $1 ~ /(chatgpt|openai)/ {print $1 "=" $2}' |
    paste -sd ';' - || true
)"
emit "USER_APP" "manual package; Armen overlay input" "ChatGPT desktop package" \
  "${chatgpt_packages:-NOT_DETECTED}" "CHECK_OFFICIAL_APP" "MANUAL" \
  "https://openai.com/chatgpt/desktop/" \
  "No stable package feed is assumed; do not replace the installed deb during an audit."
firefox_version="$(firefox --version 2>/dev/null | sed 's/^[^0-9]*//' || true)"
emit "USER_APP" "DGX OS application substrate" "Firefox" \
  "${firefox_version:-NOT_FOUND}" "CHECK_VENDOR_CHANNEL" "MANUAL" \
  "local:firefox-version" "Preserve the existing OS/application ownership."
emit "USER_APP" "Firefox extension store" "1Password extension" \
  "PROFILE_NOT_INSPECTED" "CHECK_FIREFOX_ADDONS" "MANUAL" \
  "https://addons.mozilla.org/firefox/addon/1password-x-password-manager/" \
  "Browser profile data was deliberately not inspected."

workload_files=0
if [[ -d workloads ]]; then
  while IFS= read -r -d '' file; do
    workload_files=$((workload_files + 1))
    relative_file="${file#"$repo_dir"/}"
    case "$(basename "$file")" in
      compose*.yaml | compose*.yml | docker-compose*.yaml | docker-compose*.yml)
        while IFS=: read -r line_number image_line; do
          image_ref="${image_line#*:}"
          image_ref="${image_ref%%#*}"
          image_ref="$(printf '%s' "$image_ref" | sed -E 's/^[[:space:]"'\'']+//; s/[[:space:]"'\'']+$//')"
          [[ -z "$image_ref" ]] && continue
          if [[ "$image_ref" =~ @sha256:[0-9A-Fa-f]{64}$ ]]; then
            image_status="INFO"
            image_detail="Architecture-specific digest is pinned; registry drift was not resolved by this script."
          else
            image_status="NOT_PINNED"
            image_detail="Pin the reviewed linux/arm64 digest as well as the readable source tag."
          fi
          emit "WORKLOAD_IMAGE" "repository/container" \
            "$relative_file:$line_number" "$image_ref" "REGISTRY_NOT_QUERIED" \
            "$image_status" "repo:$relative_file" "$image_detail"
        done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "$file" 2>/dev/null || true)
        ;;
      Dockerfile | Dockerfile.* | *.Dockerfile)
        while IFS=: read -r line_number from_line; do
          read -r -a from_parts <<<"$from_line"
          image_ref=""
          for part in "${from_parts[@]:1}"; do
            [[ "$part" == --* ]] && continue
            image_ref="$part"
            break
          done
          [[ -z "$image_ref" ]] && continue
          if [[ "$image_ref" == "scratch" ]]; then
            image_status="INFO"
            image_detail="Scratch base has no registry pin."
          elif [[ "$image_ref" =~ @sha256:[0-9A-Fa-f]{64}$ ]]; then
            image_status="INFO"
            image_detail="Base image digest is pinned; validate linux/arm64 support."
          else
            image_status="NOT_PINNED"
            image_detail="Pin the base image's reviewed linux/arm64 digest."
          fi
          emit "WORKLOAD_BASE" "repository/container" \
            "$relative_file:$line_number" "$image_ref" "REGISTRY_NOT_QUERIED" \
            "$image_status" "repo:$relative_file" "$image_detail"
        done < <(grep -nEi '^[[:space:]]*FROM[[:space:]]+' "$file" 2>/dev/null || true)
        ;;
    esac
  done < <(
    find "$repo_dir/workloads" -type f \
      \( -iname 'compose*.yml' -o -iname 'compose*.yaml' \
      -o -iname 'docker-compose*.yml' -o -iname 'docker-compose*.yaml' \
      -o -iname 'Dockerfile' -o -iname 'Dockerfile.*' \
      -o -iname '*.Dockerfile' \) -print0 |
      sort -z
  )
fi
if [[ "$workload_files" -eq 0 ]]; then
  emit "WORKLOAD" "repository" "workload definitions" "none" "n/a" "INFO" \
    "repo:workloads/" "No Compose files or Dockerfiles are currently configured."
fi

printf '# result=READ_ONLY; no pins, profiles, packages, services, or images changed\n'
