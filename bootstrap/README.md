# Bootstrap boundary

For a new machine, start with [getting started](../docs/getting-started.md).
This is the detailed Nix bootstrap contract, not the complete setup sequence.

Nix is the one unavoidable bootstrap exception on a factory DGX: an absent Nix
cannot install itself. This repository therefore keeps the bootstrap inputs in
plain JSON so the host declaration and installer provenance can be reviewed
with only Bash and Python 3.

`nix/source.json` pins the official NixOS `nix-installer` ARM64 Linux artifact
by release, URL, byte size, and SHA-256. It also records the Linux/systemd
planner inputs and the separately managed desired Nix runtime. Keep those two
versions distinct: updating the provisioning binary does not update a running
Nix daemon, and updating the runtime does not require replacing
`/nix/nix-installer`.

From the repository root, render the non-applying host plan with:

```bash
./scripts/dgx-setup plan
```

The plan validates `fleet/hosts.json`, inventories the local substrate without
reading the DGX serial number, and either adopts the exact installed
provisioning artifact, identifies a clean-host download, or holds on a partial
or foreign Nix surface. If Nix exists, evaluation may fetch missing locked
flake sources into the store, but the command does not build/install packages,
change profiles, activate configuration, restart services, enroll Tailscale,
switch desktops, or reboot.

Check the bootstrap pin against the latest official release and downloaded
artifact with:

```bash
./scripts/update-nix-installer.sh --check
```

`--apply` updates only `nix/source.json`; it never installs Nix or activates
host configuration. Verification runs the downloaded binary's version check. The
full dependency updater invokes this verified pin updater before the flake
refresh.

The bootstrap operator is:

```bash
./scripts/dgx-setup bootstrap
```

An exact existing install is adopted as a verified no-op. The current pilot's
installer, receipt, planner base, desired runtime, daemon endpoint, and Nix
files pass that host test; its original receipt did not enable flakes, so that
difference remains an explicit non-mutating hold.

On a truly clean declared ARM64 host, the implemented branch:

1. requires a clean committed repository and a still-current installer pin;
2. downloads the artifact again as root and verifies version, size, and hash;
3. generates and validates the official Linux/systemd plan with 32 build users,
   profile integration, persistent flakes, no channel, and no force;
4. snapshots sanitized systemd/GPU/Tailscale continuity evidence under
   `/var/lib/dgx-setup/nix-bootstrap/`;
5. arms a 15-minute transient rollback before installation;
6. installs from that exact plan and advances the default profile through the
   repository's separately verified Nix runtime path when required;
7. verifies runtime, receipt, features, daemon, systemd, GPU, and every
   pre-existing factory/access service; and
8. disarms automatically only after complete postflight.

The rollback helper invokes the same retained official installer against its
receipt. It refuses manual deletion if a partial Nix surface has no receipt.
For paths whose checksum-bound pre-state was absent, it moves any installer-created
root profile/expression/state/cache residuals into the private rollback
evidence directory rather than deleting them, then requires the exact clean
boundary.
The operator never activates Home Manager, System Manager, Tailscale, a
desktop, or a workload, and never reboots.

The exact-adoption branch is host-tested. The exact clean-install branch passed
its disposable Ubuntu lifecycle on 2026-09-03. The
[validation record](../docs/2026-09-03-nix-bootstrap-lifecycle.md) contains the
derivation, output hash, five completed subtests, corrections discovered by
the test, and independent host postflight. It proved:

- clean official installation from the reviewed plan;
- an armed rollback surviving an injected post-runtime failure;
- receipt-driven uninstall back to the exact clean boundary;
- successful retry at exact runtime 2.35.2 with persistent flakes; and
- a second idempotent adoption with no profile/configuration mutation.

The branch is therefore eligible for the Nix-only bootstrap of a declared
clean ARM64 host through `scripts/dgx-setup bootstrap`. It still requires a
clean commit, current installer pin, local `sudo`, and its built-in preflight;
it grants no authority for unified apply or another ownership layer.

“Safe over SSH” is not sufficient for a Tailscale package or service change:
restarting `tailscaled` terminates Tailscale SSH sessions. Any bootstrap/apply
step that can replace or restart the access plane requires independently
verified console/recovery access and a timed rollback guard. It must preserve
`/var/lib/tailscale` and may not remove apt ownership until the Nix-managed
service passes reboot and reconnect validation. See the
[Tailscale operations reference](../.agents/skills/dgx-spark-ops/references/tailscale.md).

The live Nix runtime is a separately reviewed root concern. The default
`upgrade-nix` fallback points backward and must not be run. Read the exact
[Nix runtime diagnosis and candidate](../root/nix/README.md).

System Manager generation three was the boot-linked canary foundation. The
pilot is now on generation five, which adds Nix-owned Tailscale and headless
target control without taking over Nix configuration or mutable node identity.
New hosts follow the separate [two-generation convergence workflow](../docs/fresh-host-convergence.md).
Read
[root/system-manager/README.md](../root/system-manager/README.md) before any
broader root change.
