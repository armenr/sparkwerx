# System Manager first-reboot recovery transaction plan — 2026-09-02

## Status and authorization boundary

**DISPOSABLE LIFECYCLE TEST PASSED; HOST RECOVERY ARMING AND REBOOT ARE NOT
AUTHORIZED.**

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
| Repository base commit | `50dfa97957044b587f9a79019b06e0f404fe8fce` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Boot transaction | `/nix/store/qq2601mm69xilwhiyr8sipl381w17jnc-root-boot-persistence-transaction.sh` |
| Recovery transaction | `scripts/root-reboot-recovery-transaction.sh` |
| Recovery transaction SHA-256 | `1cbc0c67fa25005a0271ed6e183e047663a7f5dee80fcdaa82e7c032fee06888` |
| Post-boot state auditor | `/nix/store/skzn5n9f2ld8lji3ccvpfjmy6r0nk1bw-audit-root-canary-state.sh` |
| Post-boot state auditor SHA-256 | `19cac3ba416dc3705c9dc1a996afb82840e8f4bc2d657a78f969f3f42cfddb12` |
| Production bundle | `/nix/store/k45k76fgwl29in8wdipna5srwsnxx34y-dgx-root-reboot-recovery` |
| Production bundle derivation | `/nix/store/hds5flgrdgjm0rgkhrhm0sl0bv99d0bx-dgx-root-reboot-recovery.drv` |
| Production deadline | `OnBootSec=10min` |
| Disposable deadline | `OnBootSec=30s` |
| Disposable test | `root/system-manager/reboot-recovery-transaction-test.nix` |
| Test source SHA-256 | `d107f04184bd582e71af4273c7c979d60b5c0570a5a98c6f106ff3a9d7d961e5` |
| Root test wrapper | `scripts/test-root-reboot-recovery-transaction.sh` |
| Root wrapper SHA-256 | `5ee76a5fa8dee0ed67400719c82e12992620fd0acf10aa87d5f8136736eb6f4a` |
| Passed test derivation | `/nix/store/1jidbq39jy4xqngsybdla16535wwm6dl-container-test-dgx-root-canary-reboot-recovery-transaction.drv` |
| Passed test output | `/nix/store/x147g1l7haxqhvrwpvhpajwiiphmal70-container-test-dgx-root-canary-reboot-recovery-transaction` |
| Passed output hash | `sha256:122gr5rhzqicxm8ndgbd3vpkjsgrybg75a2y6ni459ajm4p5jg05` |
| Passed at | `2026-09-02T13:39:12Z` |

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
6. a fresh boot without confirmation automatically restores exact registered,
   active, no-boot generation two after the accelerated deadline;
7. exact verified cleanup removes the retained rollback evidence and recovery
   surface;
8. a second generation-three boot confirmed before its deadline retains exact
   generation three and removes the recovery surface;
9. final cleanup returns the container to empty, unregistered System Manager
   state; and
10. the bounded manager surface and protected Nix, passwd, group, and shadow
    files remain unchanged outside the intended transitions.

After the build, the root wrapper reclassifies the real host and refuses
success if a recovery path appeared, a recovery unit remained loaded, or the
live generation-three state changed.

All ten obligations passed in derivation `1jidbq39…`. The daemon log records 12
successful subtests, including two disposable restarts, the automatic
30-second rollback branch, the confirmed-retention branch, and final empty
cleanup. The exact evidence is in the
[container-test result](2026-09-02-reboot-recovery-transaction-container-test.md).
Independent host postflight remained
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`; both recovery units
were `not-found` and every recovery path was absent.

## Gate after a passing disposable test

This passing container test authorizes no host mutation and no reboot. Before any
real first reboot, the repository still requires separately reviewed and
hash-pinned host snapshot, arm, post-boot confirmation, rollback-verification,
and cleanup helpers. A fresh private snapshot must bind the exact clean commit,
bundle, transaction, passed test output, host boot ID, protected services,
GPU/Tailscale health, and physical-console recovery evidence. Arming and reboot
must then receive distinct, explicit operator authorizations; the reboot helper
must never infer reboot authority from recovery arming.
