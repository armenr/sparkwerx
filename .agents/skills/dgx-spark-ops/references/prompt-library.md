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
service/etc/state/registration allowlists, closure anti-downgrade rules, and
runbook. Run evaluation and dry-run only; do not build, run the sudo container
test, register a generation, create state, or activate the host.
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
Keep Nix 2.34.8 and real userborn rejected, build with --no-link, and leave the
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
registration scope, timed deactivation command, and accepted residual state
file. The disposable root-assisted container test is not host activation.

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
