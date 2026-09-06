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
- [x] Retry the hash-pinned, timed, no-reboot restoration path. Attempt one
      safely timed back after the old retention phrase was mistyped; attempt
      two used one pre-mutation Enter, passed two complete postflights,
      automatically disarmed rollback, and retained exact selected/live/
      boot-linked generation three
- [x] Freeze the live System Manager package set in a dedicated exact
      `nixpkgs-root` lane and prove every candidate, recovery bundle, policy,
      parser, and disposable-test derivation remains identity-stable
- [x] Define and audit the checksum-pinned official ARM64 Nix installer source,
      Linux planner inputs, exact-installed adoption classification, and
      read-only fresh-host bootstrap plan
- [x] Implement exact-existing Nix adoption as a host-tested zero-mutation
      transaction
- [x] Implement the clean-host Nix install path with validated official plan,
      rollback-before-mutation, exact runtime update, and continuity postflight
- [x] Pass the exact disposable clean-install, injected-failure/timed-uninstall,
      clean-retry, and second-run adoption lifecycle; record its hash-valid
      output and clean independent host postflight
- [x] Build the single read-only host `plan` entry point that composes the exact
      base, optional roles, user overlays, and workloads
- [x] Build the staged guarded host `apply` entry point for the independently
      proven Nix and headless Home lifecycles; pass its exact live no-op test
- [x] Extend `apply` to verify the separately proven Nix-managed Tailscale role
      without restarting it
- [x] Extend `apply` to verify the separately proven root desktop role; pass
      exact retained generation-five `PLAN_STATUS=READY` and
      `APPLY_STATUS=COMPLETE` no-op integration
- [x] Compose the proven one-time optional Tailscale ownership and desktop
      transition into a guarded, resumable pristine-host workflow without
      weakening either rollback boundary
- [x] Pass and record the combined root-assisted disposable fresh-host gate
      before using that workflow on another DGX
- [x] Use factory update, clone, explicit declaration, plan/SBOM review, and
      repeated guarded `converge` as the other Sparks' initial configuration
      path; do not add an unattended first-boot mechanism

## Phase 3: Tailscale migration

- [x] Review the exact current-stable Tailscale ARM64 package and closure
- [x] Build and validate the Tailscale package/unit without activation
- [x] Build and pass the exact apt-to-Nix transaction, injected-failure
      rollback, candidate/vendor reboot, and persistent timed-rollback lifecycle
- [x] Run the guarded live handoff and require preserved `/var/lib/tailscale`
      identity, a separately authorized reboot, and a fresh SSH reconnect before
      confirmation
- [ ] After an observation period, separately decide whether to remove the now
      inactive Tailscale apt package/source fallback

## Phase 4: minimal Home Manager activation

- [x] Inspect the three-package base plus Armen/Codex activation and collision
      report; suppress Home Manager's generic user-systemd artifacts in headless
- [x] Confirm `lazydocker` adds no Docker permission and Devbox does not alter
      Nix ownership
- [x] Back up/adopt the exact managed paths in a private snapshot
- [x] Activate only the corrected exact base plus Armen's all-modes Codex layer
- [x] Roll the real first generation back to exact pre-Home state, then repeat
      the guarded activation and retain it
- [x] Implement the later-generation `update-headless` path with current-state
      no-op behavior, rollback-before-mutation, and prior-generation retention
- [x] Pass a disposable completed-update rollback without touching the live
      profile

The private snapshot, automatic rollback, exact postflight, disposable test,
real rollback, and fresh reactivation all passed through `scripts/dgx-home`.
Snapshot `20260903T120519Z` is the retained current activation authority; see
the [host result](2026-09-03-home-headless-host.md).
The [generation-update lifecycle](2026-09-03-home-headless-update-lifecycle.md)
is now ready for the first future dependency change; no live update was needed.

## Phase 5: desktop-mode pilot

- [x] Build-test pinned Hyprland on `aarch64-linux`
- [x] Review and build-test current Ghostty as the shared graphical terminal
- [x] Implement, build, and statically inspect the thin `headless` and factory
      `gnome` root-controller candidates without activating them
- [x] Pass the disposable `headless -> gnome -> headless`, reboot, access-plane,
      and factory-fallback lifecycle
- [x] Pass and record the implemented guarded live switch/rollback operator's
      disposable lifecycle
- [x] Run the first separately authorized guarded live switch; reach exact
      headless generation five with Tailscale intact, fail closed on the
      Dashboard service-classification gap, and restore/clean exact generation
      four plus factory GNOME without a reboot
- [x] Pass and record the corrected Dashboard-aware transaction, mode, guarded
      switch, and post-Tailscale integration suite
- [x] Retry and confirm the separately authorized guarded live switch from
      factory GNOME to headless; no reboot is part of that switch
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

- [x] Build, version-smoke-test, and closure-review current Chromium
      152.0.7977.75 ARM64; prove it fails closed without a usable sandbox
- [ ] Add and prove Chromium's exact graphical root sandbox role; then wire and
      validate Chromium plus the separately pinned 1Password extension
- [ ] Firefox 1Password extension without replacing the existing browser profile
- [x] Pin, build, smoke-test, and closure-review current Zed 1.18.0 ARM64
- [ ] Validate Zed under factory GNOME/Vulkan/portals, then wire and activate it
- [x] Pin, build, CLI-smoke-test, and closure-review current LM Studio 0.4.23-1
      ARM64 with the exact unfree exception
- [ ] Resolve LM Studio's Electron sandbox caveat, validate factory-GNOME/GB10
      and URL/update behavior, then wire and activate it
- [ ] ChatGPT desktop package/provenance migration
- [x] Declare and regression-test Armen's all-modes permissive Codex defaults
      without taking ownership of mutable auth/plugin/MCP/desktop config
- [x] Put the exact current Codex CLI package and launcher in Armen's all-modes
      overlay, with repository-owned update checks and standalone rollback input
- [x] Activate and verify the Codex launcher/profile migration on the pilot;
      retain the old standalone tree only as rollback input
- [x] Verify the entire graphical overlay is absent from the active headless
      Home generation

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

- [x] Define one declarative per-host selection surface for the exact base,
      optional Tailscale/access role, desktop mode, named user overlays,
      developer tools, and workload roles
- [x] Promote the implemented new-host workflow—factory update, clone, declare
      roles, review plan/SBOM, guarded converge, and health verification—after
      its combined disposable gate passed
- [ ] Add the remaining host definitions and explicit user-overlay mappings
- [x] Add bounded Nix bootstrap plus optional Tailscale ownership/enrollment
      handoff; keep authentication and node identity external
- [ ] Establish pilot and rollout rings
- [ ] Add drift checks for the DGX substrate, Nix generations, desktop mode,
      overlays, and workload pins
- [ ] Document recovery and replacement-machine procedures
