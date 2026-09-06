# First-reboot recovery transaction container test — 2026-09-02

## Result

**PASS.** The current exact persistent first-reboot recovery lifecycle passed
collision, failure-injection, preboot arming and cancellation, automatic
rollback, confirmed retention, and final cleanup checks inside the disposable
Ubuntu `systemd-nspawn` container.

No recovery root, state, unit, timer, profile change, activation, service
operation, or reboot occurred on `sparkle-01`. Immediately before the test, one
separately guarded host `systemctl daemon-reload` acknowledged the completed
Thunderbird/Netplan unit-graph change without restarting a protected service.

## Exact evidence

| Field | Value |
| --- | --- |
| Verified at | `2026-09-02T20:13:44Z` |
| Repository base commit | `4d662ea33ebadd340812c13cebf34b367d849e85` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Boot transaction | `/nix/store/qq2601mm69xilwhiyr8sipl381w17jnc-root-boot-persistence-transaction.sh` |
| Recovery transaction SHA-256 | `b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9` |
| Post-boot auditor | `/nix/store/skzn5n9f2ld8lji3ccvpfjmy6r0nk1bw-audit-root-canary-state.sh` |
| Post-boot auditor SHA-256 | `19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12` |
| Production bundle | `/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery` |
| Production bundle derivation | `/nix/store/h4qaivg6jpf1fbgz8v8dmdi0j3xmgmps-dgx-root-reboot-recovery.drv` |
| Test bundle | `/nix/store/70f15lgla6432wxrkx0swxzsj117ynla-dgx-root-reboot-recovery-test` |
| Test source SHA-256 | `522f1a04a581a7092c607ae1ce5358d80eb2322b78c30ca8f18f368abdf85f42` |
| Root wrapper SHA-256 | `5ee76a5fa8dee0ed67400719c82e12992620fd0acf10aa87d5f8136736eb6f4a` |
| Derivation | `/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv` |
| Output | `/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction` |
| Output hash | `sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8` |
| Output SRI hash | `sha256-6L764R+eF0PEVkWfYOOYW/shBYrHUzY2qvDJW1co8Ww=` |
| Output deriver | exact derivation above |
| Exit status | `0` |

Command run by the operator:

```console
sudo ./scripts/reload-systemd-and-test-root-recovery.sh
```

The dirty-tree warnings were expected because the reviewed implementation was
under validation before commit. The preliminary read-only evaluations enabled
only `nix-command flakes`, which produced the harmless
`auto-allocate-uids` warning. The actual local-store build explicitly enabled
`auto-allocate-uids` and `cgroups` and executed the root-only container test.

The direct test invocation immediately before this run had refused host drift:
an automatic factory Thunderbird Snap refresh from revision 1229 to 1241 had
generated a new mount unit, and Netplan had regenerated one unit, leaving
`NeedDaemonReload=yes`. The one-shot wrapper required exact Thunderbird
revision 1241, captured each of the seven protected services' fragment, PID,
and active-enter timestamp, ran only `systemctl daemon-reload`, and proved all
captured values byte-identical with `NeedDaemonReload=no` before starting the
disposable test. It restarted no service and performed no recovery mutation.
The exact disposition is recorded in
[the unit-graph reload record](2026-09-03-thunderbird-unit-graph-reload.md).

## Passed subtests

The daemon build log records successful completion of all 13 subtests:

1. production and accelerated bundles matched after normalizing their exact
   self paths, with only the ten-minute versus 30-second timer delay differing;
2. a foreign recovery-root collision was preserved and refused;
3. a foreign state-parent mode was preserved and refused;
4. a foreign recovery-unit collision was preserved and refused;
5. an injected failure after recovery-root creation removed only partial work;
6. an injected failure after recovery-state creation removed only partial work;
7. an injected failure after unit installation removed only partial work;
8. arming enabled but did not start recovery on the current boot, while
   duplicate arm, same-boot confirmation, and same-boot rollback were refused;
9. exact same-boot disarm removed the complete recovery surface without
   changing generation three, after which exact re-arming succeeded;
10. the next isolated boot automatically restored exact registered/live no-boot
   generation two when confirmation was absent;
11. exact verified cleanup removed the retained rollback evidence;
12. another generation-three boot confirmed before the deadline retained exact
    booted generation three and completely disarmed recovery; and
13. final cleanup restored empty, unregistered System Manager state.

The test used two disposable restarts, kept the four protected host-style files
unchanged, preserved foreign collisions, verified exact profile/root/managed
file surfaces at each transition, and proved both rollback and confirmation
remove persistent timer enablement.

## Earlier disposable attempts

Attempt one stopped at an over-strict test assertion that compared services
containing different, correct self-referential bundle paths. Attempt two passed
automatic rollback and reached the confirmed-reboot branch, where it exposed a
real verifier distinction: `sysinit-reactivation.target` is activation-only and
is inactive after a clean boot. The final implementation hash-pins an explicit
post-boot auditor requiring the manager target and canary active, the sysinit
target inactive, and every static profile/root/managed-file invariant exact.
Same-boot checks remain unchanged and strict.

Attempt three then passed the exact 12-subtest predecessor. A subsequent live
workflow review found that an operator who armed recovery but canceled the
maintenance window had no exact supported way to disarm without rebooting. The
current transaction and 13th subtest add that same-boot cancellation path. The
third attempt remains historical evidence for its exact predecessor but no
longer matches the current transaction/test derivation.

That predecessor used recovery transaction SHA-256
`1cbc0c67fa25005a0271ed6e183e047663a7f5dee80fcdaa82e7c032fee06888`
and test-source SHA-256
`d107f04184bd582e71af4273c7c979d60b5c0570a5a98c6f106ff3a9d7d961e5`.
It passed at `2026-09-02T13:39:12Z` as derivation
`/nix/store/1jidbq39jy4xqngsybdla16535wwm6dl-container-test-dgx-root-canary-reboot-recovery-transaction.drv`,
with output
`/nix/store/x147g1l7haxqhvrwpvhpajwiiphmal70-container-test-dgx-root-canary-reboot-recovery-transaction`
and Nix hash
`sha256:122gr5rhzqicxm8ndgbd3vpkjsgrybg75a2y6ni459ajm4p5jg05`. Preserve that as
superseded historical proof, not as current authorization evidence.

Both earlier attempts were disposable-only and left the host unchanged.

## Host postflight

The root wrapper classified the real host before and after the passing test.
Independent post-test observation returned:

```text
STATE=ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED
dgx-root-reboot-recovery.service LoadState=not-found ActiveState=inactive
dgx-root-reboot-recovery.timer   LoadState=not-found ActiveState=inactive
```

All five recovery paths were absent. Therefore the test changed only Nix-store
and build-cache artifacts on the host. The live manager remains exact retained
generation three and the real host has not rebooted.

## Remaining authorization boundary

This PASS authorizes no host recovery installation and no reboot. Hash-pinned
snapshot, arm, same-boot disarm, status, post-boot confirmation,
rollback-verification, and cleanup helpers are now reviewed around this tested
transaction; see the
[live recovery plan](2026-09-03-reboot-recovery-live-plan.md). A fresh private
snapshot and explicit snapshot-bound recovery-arming authorization are required
before those helpers may touch the host. An actual reboot remains a second,
separate explicit authorization after arming and preboot verification succeed.
No recovery helper contains a reboot action.
