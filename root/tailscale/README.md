# Tailscale root-service artifact

This directory declares the future repository-owned `tailscaled.service`
separately from the pinned binary package. The flake exposes the inert unit tree
as `packages.aarch64-linux.tailscaled-unit`; building it does not copy anything
to `/etc` or `/usr`, reload systemd, stop the apt unit, or restart the daemon.

The unit deliberately preserves the current access-plane invariants:

- mutable node identity remains at `/var/lib/tailscale/tailscaled.state`;
- the local socket remains `/run/tailscale/tailscaled.sock`;
- the daemon remains wanted by `multi-user.target`, including headless mode;
- no enrollment key, node identity, tailnet policy, or Tailscale SSH secret is
  stored in Git or the Nix store; and
- host-specific non-secret daemon flags, if any, belong in a separately managed
  `/etc/dgx-setup/tailscaled.env`.

The output also preserves the official `tailscale-wait-online.service` and
`tailscale-online.target`. They are disabled/static and inactive on the pilot,
and this repository does not enable them implicitly. A future workload may opt
into `tailscale-online.target` only after its boot-order requirement is
reviewed; ordinary headless reachability does not need it.

This is not yet an activation mechanism. Do not link the unit into systemd or
remove apt ownership until a non-NixOS root manager is selected, independent
console/recovery access is proven, and a timed rollback guard is reviewed. A
restart will terminate the current Tailscale SSH connection. Follow
[`tailscale.md`](../../.agents/skills/dgx-spark-ops/references/tailscale.md) for
the migration and validation gates.
