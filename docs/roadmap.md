# Roadmap

## Phase 0: baseline, decisions, and scaffold

- [x] Confirm OS, architecture, driver, display manager, and storage
- [x] Identify the pre-existing Nix installation
- [x] Capture a sanitized baseline
- [x] Add an ARM64 flake and Home Manager host definition
- [x] Capture ownership, desktop-mode, user-overlay, software-selection, and
      pre-install manifest decisions
- [x] Commit the accepted pristine baseline

## Phase 1: align the repository with accepted policy

Repository-only work; no builds, installs, or activation.

- [x] Replace global `allowUnfree` with default-deny and exact package
      predicates
- [x] Replace the provisional base with exactly `ncdu`, `lazydocker`, and a
      current Devbox pin; remove `fd`, `jq`, and `ripgrep` from the base
- [x] Make Home Manager CLI/manpage plumbing opt-in
- [x] Move XDG, MIME, user-directory, and portal ownership to relevant roles
- [x] Add the `dgx.desktop.mode` enum and shared Ghostty graphical role without
      changing the host
- [x] Add an explicit `armen -> n0b0dy@sparkle-01` overlay mapping
- [x] Ensure excluded software cannot enter convenience roles
- [x] Evaluate the exact base, shared graphical, and per-role closure plans

Completed 2026-08-23. The next gate is explicit build approval after reviewing
the measured software manifest; evaluation did not authorize realization.

## Phase 2: bootstrap and root-manager review

- [ ] Decide whether to enable `flakes` persistently
- [ ] Review Nix trust and build-user settings
- [x] Diagnose the stale `upgrade-nix` fallback, separate it from upstream
      stable, and pin a verified 2.35.2 ARM64 candidate without activation
- [x] Explicitly approve and activate Nix 2.35.2 on the pilot; retain the exact
      2.35.1 rollback environment and verify daemon/build/Tailscale continuity
- [x] Resolve the Nix systemd daemon-reload warning during the approved runtime
      rollout; restart only nix-daemon and verify GDM/Tailscale continuity
- [x] Select and pin System Manager 1.1.0 as the bounded non-NixOS
      candidate; build and inspect its inert 109-path / 230.0 MiB ARM64 closure,
      force its private wrapper to Nix 2.35.2, and reject Nix/user/wrapper/PATH/
      boot defaults
- [x] Let the first root-local container attempt fail closed on System Manager's
      global empty-list tmpfiles behavior; pin an exact-version skip patch, add
      an unmanaged-rule regression sentinel, rebuild policy, and verify the host
      remained untouched
- [x] Pass the exact patched `sudo ./scripts/test-root-canary.sh` derivation;
      prove bounded activation/deactivation, an untouched unmanaged tmpfiles
      sentinel, and clean host postflight without activating or registering the
      host
- [x] Pass the non-configuring host collision/service preflight and prove from
      pinned source that low-level activation needs an explicit pilot GC root;
      declare that root and the snapshot/retention/timed-rollback gates without
      creating it or activating the host
- [x] Run the one-host live canary only with independent console access, a
      same-window private snapshot, explicit activation authorization, the exact
      pilot GC root, and a verified transient rollback timer; retain attempt 3
- [x] Pass the two-generation lifecycle and guarded first-registration
      failure-injection tests, then retain exact live generation one with a
      second snapshot-bound rollback/local-console gate
- [x] Pass the new guarded generation-switch failure-injection test while the
      host remains exactly `ACTIVE_REGISTERED_RETAINED`; do not create the
      host generation-two root or switch the host as part of this test
- [x] Design and policy-pin the live generation-two pilot with its own private
      snapshot, protected-process continuity, timed rollback, repeated
      postflight, local-console confirmation, and no-boot boundary
- [x] Separately authorize and run that exact live pilot from fresh snapshot
      `20260902T083437Z`; retain generation two after repeated postflight and
      local-console confirmation, preserve both pilot roots, and independently
      verify exact `ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`
- [x] Pass the exact 13-subtest/two-restart boot-persistence transaction in a
      disposable container without changing the host
- [x] Design and policy-pin the separate generation-three live activation with
      exact snapshot, all-three-root retention, rollback-before-activation,
      repeated postflight, local-console confirmation, and an explicit
      no-reboot boundary
- [x] Separately authorize and run that exact activation from fresh snapshot
      `20260902T110421Z`; retain exact six-path/three-service generation three
      plus its one boot edge and independently verify
      `ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`
- [x] Design and pass the exact persistent first-reboot recovery transaction in
      a 13-subtest/two-restart disposable lifecycle, proving same-boot
      cancellation, automatic rollback, and confirmed retention without arming
      or rebooting the host
- [x] Build, review, test, and policy-pin the live recovery snapshot, arm,
      same-boot disarm, status, post-boot confirmation, rollback-verification,
      and cleanup helpers; keep all reboot execution outside those helpers
- [x] Separately authorize recovery arming and the first real pilot reboot; let
      the missed deadline automatically restore exact generation two, then
      verify rollback and clean the recovery surface
- [ ] Retry the hash-pinned, timed, no-reboot restoration path to return
      generation three to selected/live/boot-linked state. Attempt one reached
      healthy generation three, then safely timed back to generation two after
      the old retention phrase was mistyped; the corrected helper uses one
      pre-mutation Enter and automatic repeated-postflight retention
- [ ] Define a checksum-pinned, idempotent Nix install/adoption bootstrap and a
      complete uninstall/rollback path
- [ ] Build a single read-only host `plan` and guarded host `apply` entry point
      that composes the exact base, optional roles, user overlays, and workloads
- [ ] Decide how the other Sparks receive first-boot configuration

## Phase 3: Tailscale migration

- [x] Review the exact current-stable Tailscale ARM64 package and closure
- [x] Build and validate the Tailscale package/unit without activation
- [ ] Migrate from apt only with independent recovery, a timed rollback,
      preserved `/var/lib/tailscale` state, and a reboot/reconnect test
- [ ] Remove the Tailscale apt package/source only after Nix ownership is proven

## Phase 4: minimal Home Manager activation

- [ ] Inspect the three-package base activation and collision report
- [ ] Confirm `lazydocker` adds no Docker permission and Devbox does not alter
      Nix ownership
- [ ] Back up or adopt any files Home Manager would own
- [ ] Activate only the corrected exact base
- [ ] Confirm rollback to the previous Home Manager generation

## Phase 5: desktop-mode pilot

- [x] Build-test pinned Hyprland on `aarch64-linux`
- [ ] Review and build-test current Ghostty as the shared graphical terminal
- [ ] Implement and inspect `headless` and factory `gnome` transitions first
- [ ] Validate the NVIDIA userspace bridge for Hyprland
- [ ] Review Hyprland's portal as an independent closure
- [ ] Add a reversible GDM session entry
- [ ] Test `headless -> gnome -> hyprland -> gnome -> headless` locally
- [ ] Decide whether to select KDE; if selected, repeat the independent package,
      portal, GDM, and rollback gates
- [ ] Record resource use and pass/fail results for login, suspend, sharing,
      applications, and CUDA/container workloads

## Phase 6: Armen overlay migration

Each item gets its own manifest record, current pin, closure review, build
approval, graphical validation, activation approval, and rollback.

- [ ] Wire and validate pinned Chromium plus the 1Password Chromium extension
- [ ] Firefox 1Password extension without replacing the existing browser profile
- [ ] Wire and validate the pinned current Zed candidate
- [ ] Wire and validate the pinned current LM Studio candidate and exact unfree exception
- [ ] ChatGPT desktop package/provenance migration
- [x] Declare and regression-test Armen's all-modes permissive Codex defaults
      without taking ownership of mutable auth/plugin/MCP/desktop config
- [ ] Decide where the existing Codex CLI belongs
- [ ] Verify the entire graphical overlay becomes inactive in headless mode

## Phase 7: selected DGX workloads

- [ ] Decide separately whether headless LM Studio `llmster` is wanted
- [ ] Pin the NVIDIA Isaac playbook, Isaac Sim/Lab source revisions, LFS assets,
      toolchain, and downloads
- [ ] Produce the Isaac/Omniverse manifest and disk estimate before source
      checkout or build; enumerate extra Omniverse apps/components separately
- [ ] Build and validate Isaac without pulling in NIM or AI Enterprise
- [ ] Approve models, persistent storage, services, ports, and autostart
      independently for every workload

## Phase 8: fleet rollout

- [ ] Define one declarative per-host selection surface for the exact base,
      optional Tailscale/access role, desktop mode, named user overlays,
      developer tools, and workload roles
- [ ] Make the supported new-host path: factory update, clone, declare roles,
      review plan/SBOM, guarded apply, and health verification
- [ ] Add the remaining host definitions and explicit user-overlay mappings
- [ ] Add bootstrap and Tailscale enrollment automation with bounded,
      auditable output and external secret delivery
- [ ] Establish pilot and rollout rings
- [ ] Add drift checks for the DGX substrate, Nix generations, desktop mode,
      overlays, and workload pins
- [ ] Document recovery and replacement-machine procedures
