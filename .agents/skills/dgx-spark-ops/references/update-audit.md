# Update audit and change control

## Default: read-only audit

An audit may inspect local state, fetch public metadata, browse authoritative
documentation, evaluate Nix expressions, and use dry-run commands. It must not
change repository pins, host package indexes, profiles, services, group
membership, containers, images, or workload state.

Run the deterministic first pass from the repository root:

```bash
.agents/skills/dgx-spark-ops/scripts/audit-updates.sh
```

The script deliberately does not use `sudo`. Use `--offline` to suppress all
remote lookups.

Follow with current documentation research for any `MANUAL`, `UNKNOWN`,
`NOT_PINNED`, or update candidate. The script is inventory and comparison
evidence, not an update decision.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| `CURRENT` | Pin and authoritative candidate match |
| `UPDATE_AVAILABLE` | A newer candidate exists; compatibility is not yet proven |
| `AHEAD` | Installed version is newer than the source's candidate |
| `HOLD` | Candidate is older, incompatible, withdrawn, or otherwise unsafe |
| `MANUAL` | No safe machine-readable source exists or vendor UI owns the decision |
| `NOT_PINNED` | Component/source exists but the repository does not lock it |
| `UNKNOWN` | Lookup or parsing failed; do not guess |
| `INFO` | Inventory fact without an update decision |

Do not collapse `AHEAD` into `CURRENT`; it often indicates a lagging stable
channel. Do not collapse `UPDATE_AVAILABLE` into permission to update.

## Audit coverage

### NVIDIA-owned substrate

Inventory DGX OS, kernel, NVIDIA driver, system CUDA, Docker, Compose, and NVIDIA
Container Toolkit. Check the DGX Dashboard and current NVIDIA release guidance
manually.

Do not run `apt update`, install generic Ubuntu NVIDIA packages, or compare
against unrelated upstream Ubuntu/CUDA channels during an audit. The newest
generic driver is not necessarily the applicable DGX driver.

A cached `apt list --upgradable` result is not proof that the machine is
current because package indexes may be stale.

### Nix runtime

The installer provenance is the official NixOS `nix-installer`; Devbox was only
the trigger. The runtime lives in root's default Nix profile.

Always inspect:

```bash
nix --version
nix --extra-experimental-features "nix-command flakes" \
  upgrade-nix --dry-run \
  --profile /nix/var/nix/profiles/default \
  --refresh
```

Parse and compare the installed and proposed versions. If the proposed version
is lower, report `HOLD` and do not run the real command. The default
`upgrade-nix` metadata is manually maintained and may lag a newer installer or
tagged release. The command does not implement a downgrade guard and its dry-run
message always says “upgrade.” Treat this result as the **Nixpkgs fallback
candidate**, never as independent proof of current upstream stable.

Audit the newest final semantic tag and official `aarch64-linux` artifact as a
second result. A newer tag is not enough: confirm its published checksum, exact
top-level store path, and signed-cache availability through the intended update
path. The deterministic audit emits the fallback candidate and upstream stable
candidate as separate rows.

At the 2026-08-23 checkpoint, the installer release remains 2.35.1, the active
default-profile client/daemon is 2.35.2, the fallback file points ARM64 to
2.34.8, and upstream stable is 2.35.2. The default command is a blocked
downgrade. [`root/nix/README.md`](../../../../root/nix/README.md) records the
source-level diagnosis, checksum/cache-verified release path, pilot activation,
observed profile topology, and exact retained 2.35.1 rollback environment.

When an actual update is explicitly approved and the repository candidate is
newer:

1. Record the current profile target and root profile generations.
2. Re-verify the final tag, official artifact checksum, exact store path, and
   signed-cache metadata recorded under `root/nix/`.
3. Dry-run `upgrade-nix` with the repository's explicit
   `--nix-store-paths-url`; it must name the approved newer version.
4. Run that exact custom-URL command as root without `--dry-run`.
5. Run `sudo systemctl daemon-reload` and restart `nix-daemon.service`.
6. Clear the calling shell's command hash and verify client plus daemon.
7. Run this repository's checks.
8. Do not garbage-collect the exact prior environment until the update is
   accepted.

Never substitute plain `sudo -i nix upgrade-nix` into step 4 unless its fresh
dry-run target exactly equals the separately verified approved release.

Rollback uses the exact prior environment recorded before mutation, followed by
daemon reload and restart. Do not assume it belongs to the new profile's
generation lineage: the pilot's explicit `default` path became its own lineage
while the installer-created root-user profile retained 2.35.1 as a separate GC
root. Treat the official warning about possible store database schema changes
seriously; rollback is not a substitute for compatibility review.

The installed `/nix/nix-installer` binary and `/nix/receipt.json` are
installer/repair artifacts. Do not reinstall or replace them merely to update
the Nix package.

### Tailscale access plane

Read [tailscale.md](tailscale.md) before auditing, migrating, or updating
Tailscale. It is repository-owned fleet infrastructure awaiting migration from
an official apt package, not an NVIDIA-owned component. Its current stable
package and inert unit now exist and are build-validated; activation remains a
separate migration gate.

The first-pass audit reports only:

- installed/running and official stable versions;
- apt versus Nix provenance;
- sanitized service active/enabled and unit ownership;
- sanitized backend/online state; and
- boolean `WantRunning` and `RunSSH` preferences.

Never print or retain raw status or preference JSON, node names, addresses,
machine/node IDs, tailnet membership, auth keys, or ACL/grant contents.

Compare the installed version, repository pin, locked
`pkgs.tailscale.version`, and official stable candidate independently. If
stock Nixpkgs is older, report `HOLD` for that substitution; ownership
migration never justifies a downgrade. If official stable is newer, report
`UPDATE_AVAILABLE` until its ARM64 artifact, checksum, changelog, security
bulletins, SBOM/closure, systemd behavior, and rollback path are validated.

A read-only audit must not run `tailscale up`, `tailscale set`, login/logout,
device approval, ACL changes, service enable/disable, daemon reload/restart, apt
changes, or state-file reads. In particular, a restart of `tailscaled` ends
the active Tailscale SSH session.

The intended native Nix package and root service are documented in
[tailscale.md](tailscale.md). Do not containerize the machine's access plane.
Keep `tailscaled.service` wanted by `multi-user.target` so switching to a
headless role does not remove remote administration.

### Flake inputs

Compare each root input's locked revision to its declared branch or tag without
rewriting `flake.lock`.

Current policy:

- Nixpkgs tracks stable `nixos-26.05`;
- Home Manager tracks matching `release-26.05` and follows Nixpkgs;
- Hyprland tracks a separately reviewed upstream release tag.

A stable branch moving is an available lock refresh. A new Hyprland tag is an
available compositor upgrade requiring release-note review and an ARM64/NVIDIA
build gate.

When explicitly approved, `scripts/update-dependencies.sh` is the repository's
mutation path. Review its diff, ensure Hyprland's tag and compatibility patch are
still correct, and keep all builds `--no-link` until activation is separately
approved.

The Hyprland v0.56.2 pin currently carries a small patch matching upstream commit
`91f29f2`, because the release tag's CMake Glaze constraint rejects its own
locked Glaze version. Remove the patch only when the selected source no longer
needs it and the build confirms that fact.

### Selected Nix packages

The deterministic audit compares the selected direct packages against their
official release sources: ncdu, lazydocker, Devbox, Ghostty, Chromium, Zed, and
LM Studio. It also reports the locked stable/apps package versions separately
from upstream application releases. A package may therefore be current while
its branch has moved, or stale even before a lock refresh is approved.

Treat Chromium, Zed, and LM Studio as selected-but-uninstalled until their exact
current package candidates, closures, services/autostarts, state paths, and
ARM64 behavior pass the manifest gate. The LM Studio check follows only the
official Linux ARM64 latest-download redirect and does not download the
installer. Never claim that all dependencies are current merely because
`flake.lock` is reproducible or both branch-head checks succeeded.

### Retained System Manager canary

Resolve the exact current root-canary output, then run the repository's
`scripts/audit-root-canary-state.sh` classifier. It emits only
`INACTIVE_ABSENT`, `INACTIVE_EMPTY`, `ACTIVE_RETAINED`, or
`DRIFT|reason`. The current retained attempt-3 authority should report
`ACTIVE_RETAINED`; that is a healthy known state, not an unexpected install.

While retained, do not run the inactive preflight or activation helper.
Registration profile links and the upstream extra GC root must remain absent.
The separately designed generation-registration container test is documented
under `root/system-manager/validation/`; evaluation or dry-run status is not a
test pass and a test pass would not authorize live registration.

### NVIDIA playbooks

Compare the repository's pinned `NVIDIA/dgx-spark-playbooks` commit to the
official branch head. If no pin exists, report `NOT_PINNED`.

A changed playbook is not automatically an application update. Inspect the
specific workload directory, its last-updated notes, Dockerfile/base image,
commands, models, ports, volume paths, and rollback instructions.

Never execute a playbook's mutable `curl ... refs/heads/main | bash` shortcut.
Use assets from the reviewed pinned commit.

### Container images

Audit Compose and workload manifests for:

- floating tags;
- missing `linux/arm64` support;
- missing image digests;
- changed tag-to-digest resolution;
- playbook or CUDA/driver compatibility changes;
- unpinned Dockerfile bases;
- unreviewed build-time downloads.

Registry inspection is read-only. Do not use `docker pull` as an update check.
For private NGC metadata, request access to use the configured credential but
never expose it in output.

An image digest change under the same tag is an update event. Review it like a
new release.

### Applications outside Nix

Codex CLI, the ChatGPT Debian package, Firefox, and the 1Password extension began
as explicit user-application exceptions. Report their installed versions when
available. Tailscale is not in this category; it has its own fleet-access
migration and update policy above.

Use an official machine-readable release source only where one exists. Otherwise
mark the component `MANUAL`. Do not invent a scraper, replace a Debian package,
or migrate ownership during an audit.

## Audit report contract

Include:

1. audit timestamp and host;
2. whether the audit was online or offline;
3. one row per component with owner, current pin, candidate, status, source, and
   compatibility note;
4. explicit blockers and unknowns;
5. proposed validation gates for real candidates;
6. statement that no changes were made, or an exact list if the user separately
   authorized changes.

Prioritize actionable differences. Avoid reporting every transitive Nix flake
node as an independent fleet decision unless it changed unexpectedly.

## Controlled apply sequence

For an approved candidate:

1. Reconfirm the exact target and source immediately before mutation.
2. Capture the previous version, revision, digest, generation, or service state.
3. Change only the relevant pin or ownership layer.
4. Format and validate configuration.
5. Build or fetch without activation.
6. Run component-specific smoke tests.
7. Show the diff and evidence.
8. Request or confirm authorization for activation if it was not already given.
9. Activate on the pilot only.
10. Observe, then roll out to the next fleet ring.

Stop if:

- a version comparison implies downgrade;
- ARM64 or GB10 support is unclear;
- a container digest cannot be resolved;
- a source is mutable but cannot be pinned;
- secrets would enter logs or Git;
- rollback is undefined;
- the change would restart or replace `tailscaled` through the only active
  Tailscale SSH/recovery connection;
- the change would cross into a different ownership layer;
- validation requires a host mutation the user did not authorize.
