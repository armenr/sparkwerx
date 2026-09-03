# Tailscale root-service ownership

This directory contains both the independently inspectable systemd artifacts
and the disposable lifecycle test for the repository-owned `tailscaled.service`.
The actual System Manager role lives in `modules/system/tailscale.nix`, and the
flake exposes its first host candidate as
`packages.aarch64-linux.root-system-tailscale-migration`. Building any of these
outputs does not copy anything to `/etc` or `/usr`, reload systemd, stop the apt
unit, or restart the daemon.

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

The generation-four candidate is not live yet. Its disposable container test
has passed the complete vendor-to-Nix handoff, candidate reboot, rollback to
the vendor unit, and vendor reboot while preserving the same mutable identity
file. Run it with:

```bash
sudo ./scripts/test-tailscale-unit-lifecycle.sh
```

The wrapper also proves the real host's retained generation and running vendor
Tailscale process are identical before and after the disposable test. See the
[recorded result](validation/2026-09-03-unit-lifecycle-container-test.md).

Do not activate generation four or remove apt ownership until the live
migration transaction has a persistent timed rollback and independent local
console access has been verified. The deliberate daemon restart will terminate
the current Tailscale SSH connection. Follow
[`tailscale.md`](../../.agents/skills/dgx-spark-ops/references/tailscale.md) for
the migration and validation gates.
