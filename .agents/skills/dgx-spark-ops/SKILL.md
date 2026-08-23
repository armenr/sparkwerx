---
name: dgx-spark-ops
description: Audit, plan, and safely maintain this DGX Spark fleet's Nix configuration, NVIDIA substrate boundary, Tailscale access plane, Hyprland, and AI workloads. Use for update checks, drift audits, dependency bumps, Tailscale/Tailscale SSH work, NVIDIA playbook use, workload packaging or deployment, compatibility review, and rollback planning. Do not use for generic Nix or Linux work unrelated to this fleet.
---

# DGX Spark operations

Keep DGX OS as the NVIDIA-owned hardware-enablement substrate while making the
configuration above it reproducible, reviewable, and fleet-ready.

## Start here

1. Resolve the repository root with `git rev-parse --show-toplevel`. Do not
   assume the caller's current directory is the root.
2. Read [references/operating-model.md](references/operating-model.md) and the
   repository [decision register](../../../docs/decision-register.md) before
   recommending or changing ownership boundaries, packages, profiles, desktop
   modes, user overlays, or workloads.
3. Read the [pre-install software manifest](../../../docs/software-manifest.md)
   before proposing a package realization or workload build. For System Manager
   or any root integration, also read the
   [root-manager runbook](../../../root/system-manager/README.md).
4. Select the smallest applicable mode below and read only its routed
   references.
5. Treat an unqualified request to "check", "audit", or "see what is outdated"
   as read-only. Do not turn an audit into an update.

## Modes

### Audit updates or drift

Read [references/update-audit.md](references/update-audit.md) and
[references/source-map.md](references/source-map.md). Run:

```bash
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh
```

Use `--offline` only when network access is unavailable or the user requests an
offline inventory. Supplement the script with current authoritative web sources
for components it marks `MANUAL`, `UNKNOWN`, or `NOT_PINNED`.

Report availability, applicability, and validation separately. A newer version
is not automatically safe for DGX Spark.

### Plan an update

Read [references/update-audit.md](references/update-audit.md). Produce an exact
change set, source links, compatibility evidence, expected downloads/builds,
validation gates, activation boundary, and rollback procedure. Do not mutate
the host or repository merely because the user requested a plan.

### Plan software, a user overlay, or a desktop mode

Read the [decision register](../../../docs/decision-register.md),
[software manifest](../../../docs/software-manifest.md), and whichever of the
[desktop-mode](../../../docs/desktop-modes.md) or
[user-overlay](../../../docs/user-overlays.md) contracts applies.

Preserve the exact `ncdu`/`lazydocker`/current-Devbox CLI base, shared
Ghostty graphical role, exact user scope, singular desktop mode, default-deny
unfree policy, and explicit non-selections. Check current ARM64 sources and
versions, but report a package as selected-not-ready when the lock is stale.
Return the exact profile graph, closure-review plan, services/state, validation,
and rollback. Do not build, install, activate, or switch modes merely because a
design was accepted.

### Apply an approved update

Read [references/update-audit.md](references/update-audit.md). Confirm the user
actually asked to apply the identified change. Update one ownership layer at a
time, preserve the previous pin/generation, validate before activation, and stop
at any compatibility or downgrade ambiguity.

Never combine DGX OS/driver updates, Nix runtime updates, flake updates,
container-image changes, and workload activation into one opaque operation.

### Audit, test, or change root integration

Read the [root-manager runbook](../../../root/system-manager/README.md),
[decision register](../../../docs/decision-register.md), and
[software manifest](../../../docs/software-manifest.md). Read
`../../../root/nix/README.md` as well before changing the private Nix input.

An audit may evaluate `lib.dgxRootManagerManifest`, policy assertions, lock
metadata, and dry-run plans. It must not run the root-assisted container helper,
register a profile, create state, or activate the host. Keep System Manager on
the branch matching stable Nixpkgs and keep its private wrapper aligned with the
separately reviewed current host Nix release. Treat any reappearance of stale
Nix, real `userborn`, users, wrappers, global PATH, boot links, unexpected
units, replacement ownership, global tmpfiles processing, a missing or
version-mismatched `skip-empty-tmpfiles` patch, or a processed unmanaged
tmpfiles sentinel as a stop condition.

`sudo ./scripts/test-root-canary.sh` is a separately authorized disposable
Ubuntu activation/deactivation test, not a host activation. Actual host
activation additionally requires independent local console access, exact
collision/snapshot evidence, an exact retained store output, timed rollback, and
explicit approval for the already-built output. Low-level activation does not
GC-root its closure. The live pilot therefore requires the manifest-declared
`/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` symlink before rollback is
armed; do not remove it while active, substitute a floating output, or infer
permission to run `register-profile`. If root integration affects Tailscale or
desktop mode, route through those references and gates too.

The exact recorded patched derivation passed on 2026-08-24 with clean host
postflight. Require `isolatedTest.result == "passed"` and
`isolatedTest.matchesCurrent == true` in the root manifest. A changed input,
patch, or test derivation invalidates that evidence and requires a separately
authorized disposable rerun; it still never authorizes host activation.

Keep the helper's direct `--store local` execution. Nix 2.35 does not forward
experimental-feature overrides to the daemon, while the test's `uid-range`
build requires temporary `auto-allocate-uids` and `cgroups`. Do not persist
those features or restart/reconfigure the daemon merely to run this test.
Disclose `/nix/var/nix/userpool2` and `/nix/var/nix/cgroups` as Nix
operational bookkeeping; do not delete their records casually.
Keep `NIX_USER_CONF_FILES=/dev/null` in the helper so root-specific user config
cannot add hidden settings; system `/etc/nix/nix.conf` is still read. Do not
claim this suppresses the observed non-fatal top-level Nix 2.35.2
`auto-allocate-uids` warning. The successful derivation log and valid output,
not that cosmetic warning, determine the test verdict.

### Audit, migrate, or update Tailscale

Read [references/tailscale.md](references/tailscale.md),
[references/update-audit.md](references/update-audit.md), and
[references/source-map.md](references/source-map.md). Tailscale is a
repository-owned fleet access service that is still awaiting migration from its
manual apt installation; it is not part of the NVIDIA factory substrate.

An audit may inspect only sanitized version, package provenance, unit state,
backend state, online state, `WantRunning`, and `RunSSH`. Never print raw
`tailscale status --json`, preferences, node addresses, node IDs, tailnet data,
auth keys, or ACL contents.

Do not restart or replace `tailscaled` over the machine's only Tailscale SSH
session. A daemon restart terminates that session. Package migration or
activation requires independently verified console/recovery access and the
rollback guard defined in the reference.

### Add or change an AI workload

Read [references/workload-map.md](references/workload-map.md),
[references/source-map.md](references/source-map.md), the
[decision register](../../../docs/decision-register.md), and the
[software manifest](../../../docs/software-manifest.md). Start from the current
NVIDIA DGX Spark playbook, then pin every mutable source used by the resulting
configuration. Prefer Nix for tools and configuration and NVIDIA-validated
containers or source-build workflows for tightly coupled CUDA/Python runtimes.
Do not substitute a catalog-adjacent product for the workload the user selected.

## Non-negotiable invariants

- NVIDIA/DGX Dashboard owns firmware, kernel, system NVIDIA driver, CUDA base,
  Docker engine, and NVIDIA Container Toolkit.
- The permanent fleet base contains exactly `ncdu`, `lazydocker`, and
  `devbox`. Home Manager CLI/manpages and XDG/MIME/portal plumbing remain
  opt-in role concerns.
- Ghostty belongs to the shared graphical role for GNOME, Hyprland, and KDE and
  is inactive in headless mode.
- Never set global `allowUnfree = true`. Permit only the exact selected package
  after it appears in the reviewed manifest.
- Keep ChatGPT, Chromium, both 1Password browser extensions, Zed, and LM Studio
  in Armen's graphical overlay. Keep Isaac and Omniverse robotics/simulation
  tooling in an independent workload role.
- Do not add or recommend VS Code, Google Chrome, NIM, NVIDIA AI Enterprise, the
  1Password desktop app, or LM Link unless Armen explicitly changes the current
  non-selection.
- Do not independently upgrade vendor-owned packages with Nix, pip, or generic
  upstream installers.
- Always dry-run `nix upgrade-nix` and compare versions. Refuse downgrades; its
  stable metadata can lag the installer-provided Nix version.
- Never run `nix flake update`, `docker pull`, `docker compose up`, package
  installation, `home-manager switch`, GDM changes, daemon restarts, or host
  updates during a read-only audit.
- Never commit secrets, model-registry tokens, cookies, private model metadata,
  or unsanitized host inventory.
- Do not use floating container tags such as `latest` or `main` as reproducible
  pins. Record the architecture-specific digest and the human-readable source
  tag.
- Keep models, caches, databases, generated media, and logs outside the Nix
  store and container image.
- Hyprland stays opt-in until the non-NixOS NVIDIA graphics bridge, portals, GDM
  entry, and rollback path are validated.
- Installing `lazydocker` never implies Docker group membership; that remains
  a reviewed root-equivalent host change.
- Installing Devbox never authorizes its installer to install, replace, or
  upgrade the repository-owned Nix runtime.
- System Manager is selected only as a bounded inactive candidate. Preserve its
  exact service/`/etc` allowlists, state/registration disclosure, no-boot policy,
  Nix 2.35.2 private runtime, and closure rejection of Nix 2.34.8 and real
  `userborn`. Preserve the exact-version `skip-empty-tmpfiles` patch, its
  manifest hash/policy, and the unmanaged-rule regression sentinel; never allow
  an empty managed set to trigger global factory tmpfiles processing. Preserve
  the explicit pilot GC-root disclosure: low-level activation is unregistered
  and otherwise unrooted, so its exact closure and rollback program must remain
  retained until verified deactivation. Preserve the exact passed-test evidence
  only while it matches the currently evaluated
  derivation. A build or container test never implies host activation.
- The apt-installed Tailscale package is temporary migration input. Do not
  downgrade it to the older package in locked Nixpkgs, delete its mutable
  identity, containerize the host access plane, or remove apt ownership before
  the Nix-managed service has been validated.
- Keep `tailscaled.service` available from `multi-user.target`; headless mode
  must not disable the fleet access plane.

## Evidence and output

For an audit, return a compact table with:

- component and ownership layer;
- installed or pinned version/revision/digest;
- latest candidate and authoritative source;
- status: `CURRENT`, `UPDATE_AVAILABLE`, `AHEAD`, `HOLD`, `MANUAL`,
  `NOT_PINNED`, or `UNKNOWN`;
- compatibility evidence and recommended next action.

State the audit date, network limitations, commands that were not run, and
whether anything changed. Cite current web claims next to the claim they
support.

For reusable invocation examples, read
[references/prompt-library.md](references/prompt-library.md).
