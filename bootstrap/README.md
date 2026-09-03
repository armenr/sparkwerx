# Bootstrap boundary

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

`--apply` updates only `nix/source.json`; it never executes the installer. The
full dependency updater invokes this verified pin updater before the flake
refresh.

The executable install/adopt transaction and complete uninstall/rollback path
are still intentionally absent. Before adding them, require:

- an exact clean-host versus existing-install classifier;
- an idempotent, checksum-verifying download and reviewed installer plan;
- explicit ownership for every `/etc`, `/nix`, user/group, and systemd change;
- a previous-state snapshot and rollback/uninstall route;
- Nix daemon, build, GPU, factory-service, and access-plane postflight; and
- no implicit authority to activate Home Manager, migrate Tailscale, switch a
  desktop, or reboot.

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

System Manager generation three is the retained, boot-linked canary foundation
for future bounded root roles. It still owns no Nix configuration, desktop, or
Tailscale state. Read
[root/system-manager/README.md](../root/system-manager/README.md) before any
broader root change.
