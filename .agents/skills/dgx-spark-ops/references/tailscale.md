# Tailscale fleet access

## Read this before touching Tailscale

Tailscale is not part of the NVIDIA factory substrate. It is the current remote
management plane and is Nix-owned on `sparkle-01`. Generation four took over
the service; current headless generation five inherits it unchanged. The
manual apt package remains installed only as inactive recovery material.

Do not casually replace it with `pkgs.tailscale`. At the 2026-08-23 baseline:

- the installed official apt package was Tailscale `1.102.3` for `arm64`;
- Tailscale SSH was enabled and working;
- `tailscaled.service` was active, enabled, and wanted by
  `multi-user.target`; and
- this repository's locked stable/apps Nixpkgs provided only `1.98.10` and
  `1.102.2`, respectively; and
- `packages.aarch64-linux.tailscale` pinned stable `1.102.3` from the
  official ARM64 tarball, and both it and the inert unit output passed a
  no-link build/SBOM review.

Those are dated observations, not eternal pins. Re-audit before planning a
change. They explain why the reviewed custom derivation currently exists:
using either of those stock versions would downgrade the machine's
remote-access daemon. Building the adapter did not migrate service ownership.

## Ownership

| Concern | Owner and location |
| --- | --- |
| `tailscale` and `tailscaled` binaries | This repository, through a pinned Nix package |
| `tailscaled.service` and headless boot behavior | Explicit System Manager role in `modules/system/tailscale.nix`; generation four took ownership and current generation five inherits it unchanged in active headless mode |
| Node identity and daemon state | Mutable root-owned state under `/var/lib/tailscale`; never copy into Git or the Nix store |
| Tailscale SSH preference | Declarative desired state applied without embedding an auth key |
| Tailnet ACLs, grants, SSH policy, and device approval | Tailscale control-plane state; document and manage separately from the host package |
| Enrollment/auth keys | External secret storage and host-specific provisioning; never Git, logs, derivations, or world-readable files |

Do not put this host networking and SSH service in a container. It must start at
normal multi-user boot, survive graphical-session changes, own host networking
integration, and remain available in headless mode. Containers remain suitable
for application workloads, not the fleet's only host access path.

## Why a hand-pinned package can exist

If locked stable Nixpkgs still trails the installed approved release, package
the exact official static ARM64 artifact from
`https://pkgs.tailscale.com/stable/` with its published checksum. This is a
small version-gap adapter, not a fork:

- use the unmodified official `tailscale_<version>_arm64.tgz` artifact;
- pin the exact version, URL, and Nix/SRI hash;
- do not float a channel, branch, or URL;
- do not import Tailscale's developer-oriented upstream flake as a production
  dependency merely to obtain a newer binary;
- expose the approved package as `packages.aarch64-linux.tailscale` so the audit
  can read its `.version` without building or activating it; and
- keep service configuration separate from the package expression.

The implemented adapter reads `packages/tailscale/source.json`; the official
version, URL, published hex SHA-256, and Nix SRI hash are all exact pins.
`scripts/update-tailscale.sh --check` discovers the official stable candidate
without mutation. `--apply` rewrites only that JSON for a strictly newer
version; it refuses downgrades and refuses same-version checksum changes. The
normal dependency updater then build-validates the package and unit without
activation.

The custom expression must carry an adjacent comment with this meaning:

```nix
# Temporary anti-downgrade package for the fleet access plane.
# Locked stable Nixpkgs was older than the approved installed Tailscale release.
# Re-check and prefer pkgs.tailscale on every update; see
# .agents/skills/dgx-spark-ops/references/tailscale.md.
```

Do not preserve the custom package out of habit. When locked Nixpkgs provides
the same or newer approved version and its ARM64 package passes the required
checks, replace the custom expression with `pkgs.tailscale` and remove the
adapter in the same reviewed change.

## Read-only audit

Use the skill's audit script for the first pass. If checking manually, expose
only sanitized fields:

```bash
tailscale version --json
tailscale version --json --upstream --track stable
dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' tailscale
systemctl show tailscaled.service \
  -p ActiveState -p UnitFileState -p FragmentPath -p WantedBy --no-pager
tailscale debug prefs | jq '{WantRunning, RunSSH}'
tailscale status --json | jq '{BackendState, SelfOnline: .Self.Online}'
```

Never retain or print the unfiltered output of `tailscale status --json` or
`tailscale debug prefs`; both can contain fleet or node details that do not
belong in inventory, chat, or CI logs.

Compare four values separately:

1. the running/installed version;
2. the repository pin;
3. `pkgs.tailscale.version` from this repository's locked Nixpkgs; and
4. the current official stable candidate.

`tailscale version --upstream --track stable` queries Tailscale's official
release service without changing the package. Confirm important releases in the
official changelog and security bulletins. A newer version is only
`UPDATE_AVAILABLE` until ARM64 availability, release notes, closure/SBOM, unit
compatibility, and rollback are reviewed. An older candidate is `HOLD`; never
downgrade the access plane to make package ownership look tidy.

## Updating the package and service

Package review and live root deployment are different operations:

1. Capture the sanitized audit fields, the active unit source, and the current
   root configuration generation. Do not export node identity or daemon state.
2. Check whether locked `pkgs.tailscale` has caught up. Prefer it when it is an
   approved non-downgrade and passes validation.
3. If the adapter is still needed, run `scripts/update-tailscale.sh --check`,
   read the changelog and all intervening security bulletins, and use its
   explicitly authorized `--apply` mode only for a strictly newer stable
   release. Never accept a same-version checksum mutation automatically.
4. Produce and review the proposed SBOM/closure before installation. Build with
   no activation and verify `tailscale version` from the result.
5. Review the service diff. Preserve `/var/lib/tailscale`, the local socket and
   state paths, `multi-user.target` enablement, and a single deliberate daemon
   restart. Never put an auth key in a Nix derivation or command line captured
   by logs.
6. Treat a changed root fingerprint as a separate root-generation deployment,
   not permission to activate from a dependency updater. A general later-root
   upgrade operator is not implemented yet; prepare and test that transaction
   before a live service update.
7. For an approved live deployment, verify independent recovery, arm automatic
   rollback before the handoff, and expect the Tailscale SSH connection to end.
   Reconnect and verify identity, SSH, unit ownership, and headless reachability.
   Reboot validation is a separately planned host action.
8. Retain the previous package and root generation until the deployment's
   access and recovery checks pass. Do not remove apt fallback implicitly.

`dgx-tailscale migrate` is **not** an update command. It expects the original
generation-three/vendor state and byte-identical apt/Nix binaries. Reusing it
for a later release or the retained generation-five host is incorrect.

## Completed pilot migration

These gates passed on `sparkle-01` on 2026-09-05. Exact generation four took
ownership, and current headless generation five inherits its Nix unit and
running daemon unchanged. Node
identity and Tailscale SSH were preserved, a fresh SSH connection succeeded
after the real reboot, and no rollback is armed. The apt package/repository are
retained only as inactive fallback material. Access-plane authority is
`root/tailscale/validation/2026-09-05-host-attempt-2.md`; current host authority
is `root/desktop/validation/2026-09-05-host-attempt-2.md`.

The following is the historical one-time migration sequence, not instructions
for the current retained pilot. New hosts use
[`dgx-setup converge`](../../../../docs/getting-started.md) and its independent
optional-access workflow. The original migration deliberately kept the apt
package and repository in place:

```bash
./scripts/dgx-tailscale plan
./scripts/dgx-tailscale migrate
# Reconnect after the deliberate restart.
./scripts/dgx-tailscale status
# Separately authorize and perform one reboot; this script has no reboot action.
./scripts/dgx-tailscale status
./scripts/dgx-tailscale confirm
```

The command itself is the action boundary; the operator uses no fragile exact
confirmation phrases. `migrate` refuses a dirty repository, reruns the exact
disposable lifecycle, validates byte-identical apt/Nix binaries, snapshots only
sanitized metadata plus protected-file hashes, roots both rollback closures,
and arms the timer before launching the detached handoff. `confirm` refuses the
original boot. `rollback` restores generation three and the apt unit;
`cleanup-rolled-back` removes only a verified guard after rollback. Retiring
the apt fallback remains a separate cleanup decision even after a successful
reboot and reconnect.

The reusable migration proof is
`scripts/test-tailscale-unit-lifecycle.sh`. It runs the apt-shaped vendor unit,
generation-three preservation, injected post-registration failure, generation-
four takeover with one explicit restart, a candidate reboot, exact generation-
three rollback, a vendor reboot, and persistent unconfirmed-reboot rollback
entirely inside a disposable container. Its host wrapper accepts exact
generation-three/vendor ownership, generation-four/Nix ownership, or confirmed
headless generation-five/inherited Nix ownership, and compares the host daemon
PID/start time before and after. Passing
this test does not authorize a live restart.

## Headless and rollback invariants

- `tailscaled.service` must remain reachable from `multi-user.target` even when
  GDM/GNOME/Hyprland and graphical targets are disabled.
- Never test a daemon replacement through the sole connection it will destroy.
- Keep a physical login path and a timed rollback for the first migration and
  for changes to the unit, state path, or networking flags.
- A rollback restores the previous package and unit while retaining the node's
  existing mutable identity. Deleting `/var/lib/tailscale` is not rollback.
- Do not treat Tailscale SSH itself as independent recovery. The break-glass
  choice—physical console and/or separately reviewed OpenSSH—is an explicit
  security decision.

## Authoritative breadcrumbs

- Stable packages and published checksums: https://pkgs.tailscale.com/stable/
- Release changelog: https://tailscale.com/changelog
- Security bulletins: https://tailscale.com/security-bulletins
- Tailscale SSH behavior: https://tailscale.com/docs/features/tailscale-ssh
- Security practices: https://tailscale.com/docs/reference/best-practices/security
- Candidate non-NixOS root manager: https://github.com/numtide/system-manager
- Repository package pin: `packages/tailscale/source.json`
- Repository inert unit: `root/tailscale/unit.nix`
- Repository System Manager role: `modules/system/tailscale.nix`
- Disposable ownership test: `root/tailscale/unit-lifecycle-test.nix`
- Root-only safe test wrapper: `scripts/test-tailscale-unit-lifecycle.sh`
- Guarded live operator: `scripts/dgx-tailscale`
- Exact migration transaction: `scripts/root-tailscale-migration-transaction.sh`
- Persistent rollback bundle: `root/tailscale/migration-bundle.nix`
- Latest recorded result:
  `root/tailscale/validation/2026-09-05-migration-lifecycle-container-test.md`
- First live guard's verified rollback and cleanup:
  `root/tailscale/validation/2026-09-05-host-attempt-1.md`
- Current retained Nix-managed host authority:
  `root/tailscale/validation/2026-09-05-host-attempt-2.md`
