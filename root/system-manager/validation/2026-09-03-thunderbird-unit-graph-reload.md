# Thunderbird Snap unit-graph reload — 2026-09-03

## Result

**PASS.** A guarded `systemctl daemon-reload` acknowledged the exact unit-graph
change caused by the completed factory Thunderbird Snap refresh. All seven
protected factory/access services kept the same fragment, main PID, and
active-enter timestamp. No service was restarted, and exact live System Manager
generation three remained unchanged.

This was not a System Manager activation, recovery arming, or reboot.

## Cause and refusal

The first direct rerun of the revised disposable reboot-recovery test correctly
refused before entering its container because
`dgx-setup-canary.service` reported `NeedDaemonReload=yes`. Read-only diagnosis
found:

- completed Snap change 14 had refreshed Thunderbird from revision 1229,
  version `154.0-2`, to revision 1241, version `155.0-1`;
- `/etc/systemd/system/snap-thunderbird-1241.mount` and its enablement links had
  appeared; and
- Netplan had regenerated `/run/systemd/system/netplan-ovs-cleanup.service` and
  its enablement link.

Systemd was `running`, had zero failed units, and every protected service was
active. The pending reload was unit-file cache drift, not a service failure.
This is the same class of expected vendor unit-graph change previously observed
after the factory Firefox Snap refresh.

## Guarded acknowledgement

The operator ran:

```console
sudo ./scripts/reload-systemd-and-test-root-recovery.sh
```

The executed helper SHA-256 was
`f869cfd985face8d9e9a4fff65a85e63b5877ceb4af9dde3b8ce17e9d635c338`.

The one-shot helper required host `sparkle-01`, exact Thunderbird revision
1241, and `NeedDaemonReload=yes` on all seven protected units. Before the reload
it captured `FragmentPath`, `MainPID`, and
`ActiveEnterTimestampMonotonic` for:

- `nix-daemon.service`;
- `tailscaled.service`;
- `gdm.service`;
- `docker.service`;
- `dgx-dashboard.service`;
- `dgx-dashboard-admin.service`; and
- `nvidia-persistenced.service`.

It then ran exactly `systemctl daemon-reload`, compared the complete continuity
snapshot byte-for-byte, required `NeedDaemonReload=no`, required systemd
`running` with zero failed units, and required the exact classifier
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`.

The observed guard output was:

```text
PASS|daemon_reload|all protected processes/fragments/start-times unchanged; exact generation three retained
```

Only after that PASS did the helper invoke the separately scoped disposable
reboot-recovery lifecycle test. It completed with `TEST_STATUS=0`.

## Post-state

- Exact generation three remained selected, upstream-rooted, directly retained,
  active, and boot-linked.
- All seven protected services remained active and reload-clean.
- No recovery GC root, state directory, service, timer, or enablement link was
  created on the host.
- No host reboot occurred.

The helper is deliberately one-shot evidence for Thunderbird revision 1241. A
later unit-graph change requires fresh diagnosis; do not weaken or generalize
its exact preconditions merely to make it rerunnable.
