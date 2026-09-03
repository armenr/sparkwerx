# Tailscale fleet access

## Read this before touching Tailscale

Tailscale is not part of the NVIDIA factory substrate. It is the current remote
management plane and must ultimately be owned by this repository. The manual apt
installation on `sparkle-01` is a working bootstrap and migration source, not a
permanent exception.

Do not casually replace it with `pkgs.tailscale`. At the 2026-08-23 baseline:

- the installed official apt package is Tailscale `1.102.3` for `arm64`;
- Tailscale SSH is enabled and working;
- `tailscaled.service` is active, enabled, and wanted by
  `multi-user.target`; and
- this repository's locked stable/apps Nixpkgs provide only `1.98.10` and
  `1.102.2`, respectively; and
- `packages.aarch64-linux.tailscale` pins current stable `1.102.3` from the
  official ARM64 tarball, and both it and the inert unit output have passed a
  no-link build/SBOM review.

Those are dated observations, not eternal pins. Re-audit before planning a
change. They explain why the reviewed custom derivation currently exists:
using either locked stock package today would downgrade the machine's
remote-access daemon. Building the adapter did not migrate service ownership.

## Intended ownership

| Concern | Owner and location |
| --- | --- |
| `tailscale` and `tailscaled` binaries | This repository, through a pinned Nix package |
| `tailscaled.service` and headless boot behavior | Explicit System Manager role in `modules/system/tailscale.nix`; generation four is built and lifecycle-tested but is not yet active on the host |
| Node identity and daemon state | Mutable root-owned state under `/var/lib/tailscale`; never copy into Git or the Nix store |
| Tailscale SSH preference | Declarative desired state applied without embedding an auth key |
| Tailnet ACLs, grants, SSH policy, and device approval | Tailscale control-plane state; document and manage separately from the host package |
| Enrollment/auth keys | External secret storage and bounded provisioning; never Git, logs, derivations, or world-readable files |

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
2. the repository pin, once one exists;
3. `pkgs.tailscale.version` from this repository's locked Nixpkgs; and
4. the current official stable candidate.

`tailscale version --upstream --track stable` queries Tailscale's official
release service without changing the package. Confirm important releases in the
official changelog and security bulletins. A newer version is only
`UPDATE_AVAILABLE` until ARM64 availability, release notes, closure/SBOM, unit
compatibility, and rollback are reviewed. An older candidate is `HOLD`; never
downgrade the access plane to make package ownership look tidy.

## Update procedure

Before an update or the initial apt-to-Nix migration:

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
6. Verify physical console or another independent recovery path. Arm an
   automatic rollback/restart guard before cutting over.
7. Activate on `sparkle-01` only. Expect the current Tailscale SSH connection to
   terminate when `tailscaled` restarts; reconnect and validate backend running,
   node online, and Tailscale SSH enabled.
8. Keep the previous package and root configuration generation until remote
   access, reboot, and headless-mode tests pass.

For the one-time migration, do not remove the apt package or repository first.
Build and validate the Nix package and unit, cut over using the same mutable
state, and remove apt ownership only after the Nix-managed daemon has survived a
reboot and a fresh Tailscale SSH connection. Exact cutover commands depend on
the approved root manager and belong in a separately reviewed runbook.

The current pre-migration proof is
`scripts/test-tailscale-unit-lifecycle.sh`. It runs the apt-shaped vendor unit,
generation-three preservation, generation-four takeover with one explicit
restart, a candidate reboot, exact generation-three rollback, and a vendor
reboot entirely inside a disposable container. It also refuses to run unless
the real host remains on exact generation three with the vendor Tailscale unit,
and compares the host daemon PID/start time before and after. Passing this test
does not authorize the live restart.

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
- Latest recorded result:
  `root/tailscale/validation/2026-09-03-unit-lifecycle-container-test.md`
