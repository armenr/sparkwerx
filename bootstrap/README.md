# Bootstrap hold point

Host-level bootstrap belongs here, but no executable bootstrap has been added
yet. It must be reviewed before it can alter `/etc`, `/usr/share`, systemd, GDM,
or the Nix daemon configuration.

The future bootstrap must be:

- idempotent;
- scoped to explicit files owned by this repository;
- able to report a plan before applying it;
- able to remove its own integration without touching DGX OS packages;
- safe for the access path it affects;
- explicit about every command requiring root privileges.

“Safe over SSH” is not sufficient for a Tailscale package or service change:
restarting `tailscaled` terminates Tailscale SSH sessions. Any bootstrap step
that can replace/restart the access plane must require independently verified
console/recovery access and a timed rollback guard. It must preserve
`/var/lib/tailscale` and may not remove apt ownership until the Nix-managed
service passes reboot and reconnect validation. See the
[Tailscale operations reference](../.agents/skills/dgx-spark-ops/references/tailscale.md).

The Nix daemon is also a reviewed root concern. The default `upgrade-nix`
candidate is currently a downgrade and must not be run. Read the exact
[Nix runtime diagnosis and candidate](../root/nix/README.md); its files are
inert evidence, not bootstrap authorization.

System Manager is now the selected root-manager candidate, but only its inert
canary, closure policy, and disposable-container test are defined. Read
[root/system-manager/README.md](../root/system-manager/README.md). A no-link
build or successful container test is not bootstrap or host-activation
authorization. The first host canary still requires an independent local
console, collision/snapshot report, timed deactivation plan, and separate
approval; do not infer safety from an active Tailscale SSH session.
