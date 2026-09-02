# Prompt library

Invoke the skill explicitly with `$dgx-spark-ops`. State the allowed mutation
boundary in the prompt; a check or audit is read-only by default.

## Whole-system audits

```text
$dgx-spark-ops Audit sparkle-01 for available updates and configuration drift.
Be read-only: do not update locks, pull images, install packages, restart
services, or activate anything. Separate availability from DGX applicability
and validation. Cite authoritative sources and finish with prioritized next
actions.
```

```text
$dgx-spark-ops Run an offline inventory audit only. Compare local state with
repository pins, mark remote candidates UNKNOWN, and make no changes.
```

```text
$dgx-spark-ops Compare every enrolled Spark with this repository and with one
another. Report drift by ownership layer and propose a pilot-first convergence
plan. Do not change any machine.
```

## Focused audits

```text
$dgx-spark-ops Check only Nix itself, Nixpkgs, Home Manager, and Hyprland for
updates. Detect downgrade candidates, review ARM64 compatibility, and do not
rewrite flake.lock.
```

```text
$dgx-spark-ops Audit the System Manager root candidate read-only. Compare its
matching release-26.05 head, private Nix release, machine-readable root manifest,
service/etc/state/registration allowlists, the exact-version empty-tmpfiles
patch/hash, unmanaged-rule regression sentinel, closure anti-downgrade rules,
exact recorded container-test evidence, `isolatedTest.matchesCurrent`, and
runbook. Run evaluation and dry-run only; do not build, rerun the sudo container
test, register a generation, create state, or activate the host.
```

```text
$dgx-spark-ops Audit the completed System Manager generation-switch milestone
read-only as historical evidence. Verify its exact candidates,
transaction/test evidence, helper hashes, parser regression, and spent-snapshot
record without expecting generation two to remain current. Do not rerun the
live wrapper, roll back or select a generation, or remove any retained root.
```

```text
$dgx-spark-ops Audit the current System Manager post-recovery state read-only.
Require exact classifier ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED,
generation-one/two numbered links, selected/upstream-rooted/live generation
two, all three direct pilot roots, absent generation-three numbered link and
boot/recovery edges, unloaded recovery units, healthy protected
services/GPU/sanitized Tailscale SSH, and no broader ownership. Accept a
cleanly idle nix-daemon.service only behind exact active/listening
nix-daemon.socket. Require recovery status
live-recovery-operational-host-not-armed, live-attempt status
automatic-rollback-verified-cleaned, restoration status
repository-ready-not-run, and matching 13-subtest evidence. Do not create a
snapshot, invoke a bare transaction, rerun a spent wrapper, restore, arm,
reboot, or remove a generation/root.
```

```text
$dgx-spark-ops Audit the NVIDIA-owned substrate: DGX OS, firmware, kernel,
driver, CUDA, Docker, and NVIDIA Container Toolkit. Inventory locally, use only
current NVIDIA guidance for applicability, and make no host changes.
```

```text
$dgx-spark-ops Audit Tailscale and Tailscale SSH without changing anything.
Report only sanitized version, provenance, service state, backend/online state,
WantRunning, and RunSSH. Compare the installed package, repository pin, locked
Nixpkgs, and official stable release; flag downgrades and explain whether the
temporary custom package is still needed. Do not print node/tailnet data or
restart tailscaled.
```

```text
$dgx-spark-ops Audit all workload Compose files and Dockerfiles for floating
tags, digest drift, ARM64 support, unpinned downloads, storage, secrets,
health checks, and rollback. Do not pull or start images.
```

```text
$dgx-spark-ops Check the official NVIDIA DGX Spark playbook for <workload>
against our pinned commit and configuration. Explain upstream changes and
whether they apply; do not execute any playbook.
```

## Explain and plan

```text
$dgx-spark-ops Explain why the proposed Nix runtime candidate is safe, ahead,
or a downgrade. Show the installed version, candidate source, ARM64 binary
path, daemon/profile ownership, validation gates, and rollback risks.
```

```text
$dgx-spark-ops Make an exact update plan for <component> from <current> to
<candidate>. Include source links, pins/digests, compatibility evidence,
expected downloads/builds, pilot validation, activation boundary, and rollback.
Do not modify files or the host.
```

```text
$dgx-spark-ops Design the fresh-DGX workflow: factory update, clone this repo,
declare the exact base plus optional roles and user overlays, render one
read-only plan/SBOM, then apply through one guarded entry point. Include the
checksum-pinned Nix bootstrap exception, optional Nix-managed Tailscale,
mutable-state/secrets boundaries, previous-generation retention, health gates,
and rollback. Do not install, activate, or reboot anything.
```

```text
$dgx-spark-ops Plan the apt-to-Nix Tailscale migration on sparkle-01. Preserve
the existing node identity and Tailscale SSH preference, keep the service in
multi-user.target, explain the anti-downgrade package pin, include the SBOM
gate, require independent recovery access and a timed rollback, and stop before
any build, install, service change, or apt removal.
```

```text
$dgx-spark-ops Evaluate <tool or workload> for this fleet. First honor the
decision register's selected scope and explicit non-selections. Decide what Nix
should own and what should use a container or pinned vendor source build, using
the current NVIDIA Spark playbook. Return a manifest-ready design and acceptance
tests, with no changes.
```

## Profiles, desktops, and selected applications

```text
$dgx-spark-ops Audit the exact fleet base and shared graphical role. Compare
locked and current ARM64 releases for ncdu, lazydocker, Devbox, and Ghostty.
Confirm lazydocker grants no Docker access, Devbox does not own Nix updates, and
Ghostty is absent from headless. Return manifest deltas only; make no changes.
```

```text
$dgx-spark-ops Compare the accepted decision register with the current flake
and machine-readable profile manifest. Be repository-read-only. Evaluate the
policy checks without building; report any drift in the exact base, stable/apps
pin boundary, unfree predicate, desktop enum, shared Ghostty role, independent
Hyprland portal gate, or explicit Armen mapping. Do not rewrite the lock, build,
or activate anything.
```

```text
$dgx-spark-ops Regenerate the read-only profile SBOM for headless, GNOME,
Hyprland, and Hyprland-with-portal. Run ./scripts/check.sh, evaluate
.#lib.dgxProfileManifests.aarch64-linux, and use only nix build --dry-run
--no-link for missing-output plans. Compare sizes and direct/effective packages
with docs/software-manifest.md. Do not remove --dry-run, realize an output,
rewrite the lock, or change the host.
```

```text
$dgx-spark-ops Plan the exact switch from <current-mode> to <target-mode> on
sparkle-01. Show affected systemd targets, GDM/session files, portals, user
profiles, resource impact, Tailscale preservation, validation, and one-command
rollback. Do not modify the repository or host.
```

```text
$dgx-spark-ops Audit only Armen's selected graphical applications for current
ARM64 releases and repository pins: ChatGPT, Chromium, both 1Password browser
extensions, Zed, and LM Studio desktop. Keep VS Code, Google Chrome, the
1Password desktop app, LM Link, NIM, and AI Enterprise out. Make no changes.
```

```text
$dgx-spark-ops Prepare a pre-build manifest for Zed and LM Studio desktop.
Compare locked Nixpkgs with current official releases, identify exact source
pins and only necessary unfree exceptions, estimate closures, and define GNOME,
Hyprland, and rollback tests. Stop before editing or building.
```

```text
$dgx-spark-ops Plan the selected Isaac role from the current official Spark
playbook. Include Isaac Sim, Isaac Lab, and selected Omniverse robotics tooling;
itemize each additional Omniverse app or Kit component instead of assuming the
whole catalog. Pin source/LFS/toolchain/download inputs, estimate build and
persistent storage, and define graphical and headless tests. Exclude NIM and AI
Enterprise. Do not clone, download, build, or activate anything.
```

## Approved repository changes

```text
$dgx-spark-ops Update only <flake input> to <exact revision/tag>. Show the
source evidence and diff, format the repository, run evaluation and ARM64
builds with --no-link, and stop before activation.
```

```text
$dgx-spark-ops Update System Manager only within the matching stable branch.
Diff every evaluated service, /etc entry, package, state path, registration
path, private Nix version, and closure path against the current root manifest.
Keep Nix 2.34.8 and real userborn rejected, preserve or explicitly reassess the
empty-tmpfiles patch and sentinel, build with `--no-link`, and leave the
root-assisted container test, registration, and host activation as separate
gates.
```

```text
$dgx-spark-ops Scaffold <workload> from the official NVIDIA playbook at <exact
commit>. Pin ARM64 image digests and all downloads, document storage, ports,
health checks, secrets, validation, and rollback. Do not pull, start, or expose
the service.
```

```text
$dgx-spark-ops Update the repository's Tailscale package only to <exact stable
version>. First check whether locked pkgs.tailscale can replace the custom
adapter. Otherwise update the exact official ARM64 URL and hash, document
release/security changes, generate the SBOM, and build with no activation. Do
not restart tailscaled or change apt ownership.
```

## Separately authorized pilot activation

```text
$dgx-spark-ops Activate the already-reviewed <change> on sparkle-01 only. First
reconfirm the exact approved diff and rollback point. Run the stated validation,
stop on any failed gate, preserve the prior generation/digest, and do not roll
out to other Sparks.
```

For a Tailscale activation, the prompt must additionally name the independent
recovery path, rollback timer/runbook, and accepted session interruption. Never
infer those from a prior build or from the fact that Tailscale SSH currently
works.

For a System Manager host canary, the prompt must name the already-built output,
independent local console, exact collision/snapshot evidence, state and
registration scope, exact pilot GC-root path and lifecycle, timed deactivation
command, and accepted residual state file. Low-level activation is otherwise
unrooted; never remove the pilot root before verified deactivation. The
disposable root-assisted container test is not host activation.

For a System Manager generation switch, the prompt must additionally name the
fresh root-owned snapshot, its timestamp, the independent local console, both
exact candidates and pilot-root paths, the passed transaction evidence, the
ten-minute `rollback-switch` timer, the exact `KEEP GENERATION TWO` phrase, and
the fact that rollback preserves both pilot roots. Never infer this authority
from the repository-complete live plan or a prior activation/registration.

For the System Manager generation-three boot-persistence activation, the prompt
must name the fresh root-owned snapshot and timestamp, all three exact
candidates and direct roots, passed 13-subtest/two-restart evidence, independent
local console, the ten-minute `rollback-boot` timer, exact
`KEEP GENERATION THREE`, and the fact that rollback returns to live no-boot
generation two while preserving all three roots. It must explicitly say not to
reboot: the activation timer is transient and does not survive one. A first
real reboot requires a different persistent-recovery plan and separate explicit
authorization; never infer it from a successful activation.

That generation-three activation has completed on `sparkle-01` from spent
snapshot `20260902T110421Z`. Do not use the activation prompt to rerun it there.
The persistent-recovery design and current 13-subtest/two-restart proof are now
complete, but the host remains unarmed and unrebooted.

For a first-reboot recovery snapshot, the prompt must authorize only creation of
one fresh root-owned snapshot using the reviewed snapshot helper. It must name
the physical console and state that snapshot creation authorizes neither arming
nor reboot.

```text
$dgx-spark-ops Create one fresh persistent first-reboot recovery snapshot on
sparkle-01 using the exact reviewed helper. I have verified the physical local
console. Do not arm recovery and do not reboot. Return only the resulting
snapshot path, exact state verdict, and next authorization phrase.
```

For recovery arming, the prompt must name the fresh snapshot timestamp and
authorize only the exact `arm` action. Require the 13-subtest current match,
clean committed repository, physical console, exact generation-three prestate,
ten-minute next-boot rollback, and phrase `ARM PERSISTENT RECOVERY`. State that
the helper has no reboot action. If the window is canceled, use the separate
`disarm-preboot` action and exact `DISARM PREBOOT RECOVERY` phrase.

```text
$dgx-spark-ops I verified the local console and authorize persistent
first-reboot recovery arming on sparkle-01 using snapshot <timestamp>. Arm and
verify only; do not reboot. Stop with the exact preboot status and the separate
reboot authorization boundary.
```

A reboot prompt must separately and unambiguously authorize one reboot after
recovery is already armed and exact preboot status passes. Never infer it from
snapshot creation, arming, the disposable PASS, or “continue.” After the new
boot, the snapshot-bound helper must either confirm exact generation three with
`KEEP REBOOTED GENERATION THREE` before the deadline or verify the automatic
generation-two rollback. Rolled-back evidence cleanup separately requires
`CLEAN ROLLED BACK REBOOT RECOVERY`.

Activation wording is intentionally narrow. A previous audit, plan, build, or
scaffold request is not authorization to activate.

## Useful follow-ups

- “Turn the UNKNOWN rows into sourced findings, without making changes.”
- “For each UPDATE_AVAILABLE row, tell me what evidence is still missing.”
- “Group these candidates into independent, rollback-safe batches.”
- “Generate a maintenance-window runbook, but do not execute it.”
- “Show which facts came from local evidence, repository pins, NVIDIA, Nix,
  upstream projects, or inference.”
- “Re-run only the failed/unknown checks and compare with the prior report.”
