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

Generation four is now the confirmed live configuration on `sparkle-01`. Its
disposable container test passed the complete vendor-to-Nix handoff,
injected-failure rollback, candidate reboot, rollback to the vendor unit,
vendor reboot, and persistent unconfirmed-reboot rollback while preserving the
same mutable identity file.
Run it with:

```bash
sudo ./scripts/test-tailscale-unit-lifecycle.sh
```

The wrapper accepts either exact pre-migration generation three/vendor
ownership or exact post-migration generation four/Nix ownership and proves the
real host's selected state and running Tailscale process are identical before
and after the disposable test. See the
[current recorded result](validation/2026-09-05-migration-lifecycle-container-test.md).
The first discovered live guard expired into its exact automatic rollback and
was verified and cleaned without host drift; see the
[attempt record](validation/2026-09-05-host-attempt-1.md). The retained exact
generation-four GC root was valid retry input, not an ownership collision. The
second attempt survived the deliberate daemon restart and a real reboot, then
was confirmed after a fresh Tailscale SSH connection; see the
[retained host record](validation/2026-09-05-host-attempt-2.md).

For the post-migration fleet/front-door regression, run
`scripts/test-post-tailscale-integration.sh` as the declared user. It composes
the read-only plan test, root-assisted disposable Nix-bootstrap and Tailscale
lifecycles, and the live no-op staged-apply test behind one command.

The reviewed live operator is `scripts/dgx-tailscale`. `plan` is read-only.
`migrate` reruns the exact disposable test, creates a private snapshot, arms a
persistent ten-minute rollback, and launches the daemon handoff in a detached
systemd worker. It never reboots the host. After the intentional SSH disconnect,
`status` must first report `AWAITING_REBOOT`; after a separately authorized
reboot and fresh connection it can report `AWAITING_CONFIRMATION`. Only then
does `confirm` remove the rollback guard. There are no phrase-matching prompts.

```bash
./scripts/dgx-tailscale plan
./scripts/dgx-tailscale migrate
# Reconnect, inspect status, separately authorize and perform one reboot.
./scripts/dgx-tailscale status
./scripts/dgx-tailscale confirm
```

Use `rollback` while the guard is armed. If the timer already restored the apt
unit, use `cleanup-rolled-back` only after `status` reports the verified rollback.
Neither path removes the apt package, its repository, or mutable node state.

`migrate` is now a completed one-time operation on `sparkle-01`; do not rerun it
while generation four is exact. For a new host, do not run it until independent
local console access has been verified. The deliberate daemon restart will
terminate the current Tailscale SSH connection. The apt package and repository
remain installed on `sparkle-01` as inactive rollback material; their removal
is a separate cleanup decision. Follow
[`tailscale.md`](../../.agents/skills/dgx-spark-ops/references/tailscale.md) for
the migration and validation gates.
