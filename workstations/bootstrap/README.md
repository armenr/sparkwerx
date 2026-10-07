# Workstation Nix bootstrap

This directory provides a workstation-specific installer pin and bootstrap.
The updater and receipt rollback scripts are reused through relative symlinks.
The scripts locate their inputs relative to their invocation
path. This directory is therefore the bootstrap input root for `spark setup`.

The original pilot installer pin and lifecycle derivations remain unchanged.
The workstation pin selects the official ARM64 installer 2.35.2 and runtime
2.35.2. The normal current-release check, clean Git check, root plan validation,
15-minute rollback timer, protected-service continuity, and exact adoption
checks all still run. No freshness or recovery checks are skipped.

The bootstrap derives from the upstream operator with one policy difference:
healthy, running, online Tailscale may have its optional SSH server disabled
when `sshDesired` is false. When it is true, the SSH feature remains required.
Offline or unreadable Tailscale still fails preflight. The exact VPN/SSH state,
daemon PID, unit, and start time must remain unchanged through installation
and recovery. This operator never changes Tailscale preferences or restarts it.

The selected installer creates `/nix`, the Nix daemon/socket, build accounts,
Nix configuration, and its standard shell hooks. It does not manage factory
drivers, CUDA, Docker, desktop, networking, or boot mode. Root recovery uses
the retained installer and receipt via the existing rollback helper.

Run as the declared user on the actual host:

```bash
spark setup
```

The first phase requests sudo internally. The following package build,
activation, and Zsh integration run as the normal user. If a later phase fails,
rerun setup: the exact Nix installation is adopted without mutation, and the
user-package operator retains its existing recovery behavior. For a pending
user-profile journal, run `spark recover` before retrying.

The disposable test harness lives under
[`dev/workstation-bootstrap`](../../dev/workstation-bootstrap). It runs Ubuntu
24.04/systemd on ARM64 with a private cgroup namespace, no host filesystem or
cgroup bind mounts, and no GPU or Docker socket. It tests real install failure,
systemd-triggered receipt rollback, clean retry, and idempotent adoption.
Its synthetic factory services and GPU output establish preservation behavior;
real hardware checks remain a separate host postflight.
