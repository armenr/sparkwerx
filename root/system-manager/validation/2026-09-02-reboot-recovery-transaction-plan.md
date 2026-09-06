# System Manager first-reboot recovery transaction plan — 2026-09-02

## Status and authorization boundary

**CURRENT 13-SUBTEST DISPOSABLE LIFECYCLE PASSED; LIVE HELPERS ARE REVIEWED;
HOST RECOVERY ARMING AND REBOOT ARE NOT AUTHORIZED.**

This record authorizes repository evaluation, inert Nix-store builds, host-side
read-only unit validation, and a root-only disposable `systemd-nspawn`
lifecycle test. It does **not** authorize installing recovery state or units on
`sparkle-01`, creating the recovery GC root, reloading the host systemd daemon,
starting or enabling a host timer, changing the live System Manager state, or
rebooting the host.

The required and currently observed host state is
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`. Generation three is
selected, upstream-rooted, directly retained, live, and linked into
`default.target`; generations one and two remain registered and directly
retained. No first-reboot recovery surface is present on the host.

## Exact reviewed inputs

| Field | Value |
| --- | --- |
| Repository base commit | `4d662ea33ebadd340812c13cebf34b367d849e85` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Boot transaction | `/nix/store/qq2601mm69xilwhiyr8sipl381w17jnc-root-boot-persistence-transaction.sh` |
| Recovery transaction | `scripts/root-reboot-recovery-transaction.sh` |
| Recovery transaction SHA-256 | `b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9` |
| Post-boot state auditor | `/nix/store/skzn5n9f2ld8lji3ccvpfjmy6r0nk1bw-audit-root-canary-state.sh` |
| Post-boot state auditor SHA-256 | `19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12` |
| Production bundle | `/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery` |
| Production bundle derivation | `/nix/store/h4qaivg6jpf1fbgz8v8dmdi0j3xmgmps-dgx-root-reboot-recovery.drv` |
| Production deadline | `OnBootSec=10min` |
| Disposable deadline | `OnBootSec=30s` |
| Disposable test | `root/system-manager/reboot-recovery-transaction-test.nix` |
| Test source SHA-256 | `522f1a04a581a7092c607ae1ce5358d80eb2322b78c30ca8f18f368abdf85f42` |
| Root test wrapper | `scripts/test-root-reboot-recovery-transaction.sh` |
| Root wrapper SHA-256 | `5ee76a5fa8dee0ed67400719c82e12992620fd0acf10aa87d5f8136736eb6f4a` |
| Passed test derivation | `/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv` |
| Passed test output | `/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction` |
| Passed output hash | `sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8` |
| Passed output SRI | `sha256-6L764R+eF0PEVkWfYOOYW/shBYrHUzY2qvDJW1co8Ww=` |
| Passed at | `2026-09-02T20:13:44Z` |

The flake pins the recovery transaction hash and builds the wrapper with the
three exact candidates and exact reviewed boot transaction. The wrapper PATH
pins ordinary utilities from Nix but deliberately resolves `systemctl` from
the factory OS, so host control uses the same systemd implementation as PID 1.

## Recovery surface and lifecycle

Arming may create only these exact temporary host paths:

- `/nix/var/nix/gcroots/dgx-setup-root-canary-reboot-recovery-pilot` pointing
  directly to the exact recovery bundle;
- `/var/lib/dgx-setup/reboot-recovery/state`, root-owned mode `0600`, recording
  the exact generations, bundle, status, and pre-reboot kernel boot ID;
- exact bundle symlinks for `dgx-root-reboot-recovery.service` and
  `dgx-root-reboot-recovery.timer` in `/etc/systemd/system`; and
- one relative enablement symlink below `timers.target.wants`.

`arm` enables the timer but does not start it in the current boot. On the next
boot, `timers.target` starts a monotonic ten-minute timer. Confirmation before
the deadline accepts only `KEEP REBOOTED GENERATION THREE`, re-verifies exact
generation three, and removes the entire recovery surface. If confirmation is
absent, the exact service invokes the tested generation-three to generation-two
rollback, removes the boot link through System Manager activation, disables the
timer, and retains exact rollback evidence. A later verified cleanup accepts
only `CLEAN ROLLED BACK REBOOT RECOVERY`.

Before reboot, exact `disarm-preboot` accepts no free-form argument. The live
wrapper requires the separate phrase `DISARM PREBOOT RECOVERY`; the transaction
then requires the original arming boot ID, the complete exact armed surface,
and unchanged generation three. It removes only that surface, reloads systemd,
requires both recovery units to become `not-found`, and verifies generation
three again. This is the cancellation path for an abandoned reboot window.

Every rollback or confirmation action requires a kernel boot ID different from
the arming boot ID. This prevents an overdue `OnBootSec=` timer, an accidental
manual start, or operator error from rolling back during the pre-reboot boot.
Unknown paths, symlink targets, state fields, modes, candidates, profile
entries, GC roots, managed files, or service state fail closed.

The post-boot verifier is a hash-pinned copy of the normal root-manager state
auditor. It preserves the activation-time invariant for every existing caller,
but its explicit `postboot` mode requires the boot-persistent manager target
and canary service to be active while the reactivation-only sysinit target is
inactive. Recovery paths may be excluded from its normal forbidden-path set
only when the recovery transaction has already verified their exact targets,
state schema, ownership, modes, and loaded-unit state.

## Disposable attempts before the current candidate

The first disposable attempt failed before mutation because the test compared
the two service files byte-for-byte; each correctly embedded its own Nix bundle
path. The corrected test normalizes only those two exact self paths and still
requires all remaining service bytes to match.

The second attempt passed collision handling, all injected-failure cleanup,
pre-reboot arming, same-boot refusal, automatic next-boot rollback, rollback
evidence cleanup, and the second generation-three boot. It then correctly
exposed that `sysinit-reactivation.target` is inactive after a clean boot, as
the earlier boot-persistence test already specified. Reusing the same-boot
activation verifier there was a test/design error; the hash-pinned explicit
post-boot mode above fixes that distinction without weakening same-boot checks.
Both attempts were confined to disposable containers, and independent host
classification remained exact retained generation three.

The third attempt was the exact 12-subtest predecessor and passed both restart
branches. Reviewing the real maintenance sequence then exposed one missing
operator path: safely canceling an armed window when no reboot will occur. Its
PASS remains valid only for that exact predecessor. The current fourth attempt
adds and proves exact same-boot disarm followed by re-arm; it supersedes the
third attempt as the current-match evidence.

## Disposable proof obligations

The root wrapper first requires the real host's exact generation-three state,
an absent recovery surface, and unloaded recovery units. It validates the inert
production unit files using host systemd, then performs all mutations and both
restarts only inside a disposable Ubuntu `systemd-nspawn` container.

The disposable test must prove:

1. after normalizing each bundle's unavoidable self-referential store path,
   production and accelerated bundles differ only in `OnBootSec`;
2. foreign recovery-root, state-parent, and unit collisions are preserved and
   refused;
3. failures injected after root, state, and unit installation remove only the
   partial recovery artifacts they created;
4. successful arming enables but does not start the timer on the current boot;
5. duplicate arm, same-boot confirmation, and same-boot rollback are refused
   without changing generation three;
6. exact same-boot disarm removes the complete recovery surface without
   changing generation three, after which exact re-arming succeeds;
7. a fresh boot without confirmation automatically restores exact registered,
   active, no-boot generation two after the accelerated deadline;
8. exact verified cleanup removes the retained rollback evidence and recovery
   surface;
9. a second generation-three boot confirmed before its deadline retains exact
   generation three and removes the recovery surface;
10. final cleanup returns the container to empty, unregistered System Manager
   state; and
11. the declared manager surface and protected Nix, passwd, group, and shadow
    files remain unchanged outside the intended transitions.

After the build, the root wrapper reclassifies the real host and refuses
success if a recovery path appeared, a recovery unit remained loaded, or the
live generation-three state changed.

All eleven obligations passed in derivation `jqmx45mx…`. The daemon log records
13 successful subtests, including exact same-boot disarm, two disposable
restarts, the automatic 30-second rollback branch, the confirmed-retention
branch, and final empty cleanup. The exact evidence is in the
[container-test result](2026-09-02-reboot-recovery-transaction-container-test.md).
Independent host postflight remained
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`; both recovery units
were `not-found` and every recovery path was absent.

## Gate after a passing disposable test

This passing container test authorizes no host mutation and no reboot. The
separately reviewed live snapshot and lifecycle helpers are now hash-pinned and
documented in the
[live plan](2026-09-03-reboot-recovery-live-plan.md). A fresh private snapshot
must bind the exact clean commit, bundle, transaction, passed test output, host
boot ID, protected services, GPU/Tailscale health, and physical-console
recovery evidence. Arming and reboot must then receive distinct, explicit
operator authorizations. No repository recovery helper performs a reboot.
