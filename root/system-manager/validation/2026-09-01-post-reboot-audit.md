# System Manager post-reboot audit — 2026-09-01

This is read-only evidence collected after `sparkle-01` rebooted. It verifies
that the second canary's timed rollback left no active or boot-persistent System
Manager configuration and that the protected factory/access services returned
healthy. Evidence collection changed no package, profile, link, unit file,
service process, repository pin, or host configuration. After detecting the
unrelated factory Snap event disclosed below, Armen ran one
`systemctl daemon-reload` to reread the generated unit graph; it restarted no
protected service.

## Result

**PASS for rollback and reboot health; HOLD for a new activation.** The machine
is healthy and the canary is inactive and unregistered. The initial automatic
preflight passed every machine-readable check. One minute later, the factory
Snap/Netplan machinery changed the systemd unit graph, so a second preflight
correctly stopped on a pending daemon reload. Armen acknowledged that graph with
`systemctl daemon-reload`; no protected service restarted, and the final
automatic preflight passed.

| Field | Observed value |
| --- | --- |
| Initial audit window | `2026-09-01T09:13:05Z`–`2026-09-01T09:13:52Z` |
| Drift detected | `2026-09-01T09:30:53Z` preflight |
| Resolution verified | `2026-09-01T09:52:05Z` preflight |
| Host | `sparkle-01` |
| Boot time | `2026-09-01 13:08:38 +04` |
| Kernel | `6.17.0-1031-nvidia` |
| System state | `running`; zero failed units |
| Default target | `graphical.target` |
| Local seat | `seat0` graphical, active session 2 |
| Repository | Clean `main` at `cd2e8e5` |
| Corrective host operation | One daemon reload; no service restart |

## Canary and registration state

All five declared canary paths are absent:

- `/etc/dgx-setup/canary`;
- `/etc/systemd/system/dgx-setup-canary.service`;
- `/etc/systemd/system/sysinit-reactivation.target`;
- `/etc/systemd/system/system-manager.target`; and
- `/etc/systemd/system/system-manager.target.wants/dgx-setup-canary.service`.

The state file is root-owned, mode 0644, and contains the exact empty version-0
record: no managed files and no services. The upstream System Manager profile
and generation GC root are absent. Global PATH hooks, boot linkage, userborn,
wrappers, and `/run/current-system` are also absent.

The exact candidate remains valid in the Nix store, and the deliberate pilot
root still points directly to it:

```text
/nix/var/nix/gcroots/dgx-setup-root-canary-pilot
  -> /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager
```

The canary target/service and transient rollback timer/service are unloaded and
inactive. The retained root is storage retention only; it does not activate or
register System Manager.

## Runtime health

Nix client and store tools report 2.35.2. The default profile still resolves to
`/nix/store/9lznxxcs35sn5zs899hfpyk2v1jcxpn5-user-environment`.
`nix-daemon.service` was active with no pending reload during the initial
audit and remained active throughout the later unit-graph drift and reload.

During the initial audit, all seven protected units were active with
`NeedDaemonReload=no` and retained their expected factory or existing
fragments:

- `nix-daemon.service`;
- `tailscaled.service`;
- `gdm.service`;
- `docker.service`;
- `dgx-dashboard.service`;
- `dgx-dashboard-admin.service`; and
- `nvidia-persistenced.service`.

After the daemon reload, all seven again reported `NeedDaemonReload=no`.
Their original start timestamps were unchanged and each reported
`NRestarts=0`, proving the reload did not restart them.

The GPU query reported NVIDIA GB10, driver 580.173.02, P8, and 35–37°C.
Tailscale 1.102.3 remains apt/unit-owned from
`/usr/lib/systemd/system/tailscaled.service`, active, enabled for
`multi-user.target`, backend `Running`, online, with `WantRunning=true` and
`RunSSH=true`. No raw Tailscale status or preference output was written to
repository evidence.

## Factory unit-graph drift after the initial pass

At `2026-09-01T13:14:03+04`, Ubuntu's Snap machinery began an automatic Firefox
refresh from revision 8762 (154.0-1) to revision 8801 (154.0.1-1). At
`13:14:30+04`, it created and mounted
`/etc/systemd/system/snap-firefox-8801.mount` and its target links. Filesystem
timestamps show Netplan also generated its normal runtime
`/run/systemd/system/netplan-ovs-cleanup.service` unit and dependency link in
the same second.

Those factory-generated unit-path changes happened after the initial preflight.
The seven protected services remained active and their fragment files were
unchanged, but systemd then reported `NeedDaemonReload=yes`. The second
preflight at `2026-09-01T09:30:53Z` therefore failed closed on all seven
protected-unit checks. At that point, no daemon reload or service restart had
been performed.

Armen then ran the requested `sudo systemctl daemon-reload`. The command
reread the generated unit graph without restarting any protected service. At
`2026-09-01T09:52:05Z`, all seven reload flags were `no`, the system remained
`running` with zero failed units, and the complete automatic preflight passed.

This was not System Manager drift and did not reactivate the canary. It was a
same-window race that reinforces the rule: clear and explain any pending daemon
reload, then rerun the full preflight immediately before snapshot and
activation.

## Rollback correlation and limits

The retained journal confirms that attempt 2's timer launched exact
deactivation at `2026-08-24T07:17:29Z` and completed successfully one second
later. The current empty state and absent paths therefore predate this reboot;
the reboot did not merely hide an active canary.

The initial automatic preflight passed against the exact candidate and recorded
non-SSH transport plus an available graphical seat. The middle preflight
recorded SSH transport and the same graphical seat, then correctly left
activation on `HOLD` because of the pending daemon reload. The final preflight
passed every machine-readable check after the reload. The manual console,
fresh-snapshot, timed-rollback, and explicit-authorization gates must still be
completed in the activation window.

This was a local operational audit, not an online dependency/update audit.
It did not claim that the dated package candidates in the software manifest
remain the newest upstream releases. Armen manually rechecked the second
snapshot's protected-file manifest after timed deactivation; `sha256sum -c`
reported `OK` for `/etc/nix/nix.conf`, `/etc/passwd`, `/etc/group`, and
`/etc/shadow`.
