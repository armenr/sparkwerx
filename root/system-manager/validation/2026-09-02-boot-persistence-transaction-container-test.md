# Boot-persistence transaction container test — 2026-09-02

## Result

**PASS.** The exact generation-two to generation-three transaction passed all
failure-injection, boot-persistence, reboot-rollback, and cleanup checks inside
the disposable Ubuntu `systemd-nspawn` container.

No registration, activation, candidate retention, boot link, service change,
or reboot occurred on `sparkle-01`.

## Exact evidence

| Field | Value |
| --- | --- |
| Verified at | `2026-09-02T10:11:07Z` |
| Repository base commit | `63a117712fddb5abb89c7229ea54a28fb6a3e866` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Transaction SHA-256 | `53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288` |
| Test source SHA-256 | `0e1118a1516367d6ca683b00d92e7b2c84bcd7af37983ca99144e4b97639465c` |
| Root wrapper SHA-256 | `b8fb9cf853f42ea96876ca21afbf458a4932b8279e70ecab2db54d7d7e107122` |
| Derivation | `/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv` |
| Output | `/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction` |
| Output hash | `sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn` |
| Output deriver | exact derivation above |
| Exit status | `0` |

Command run by the operator:

```console
sudo ./scripts/test-root-boot-persistence-transaction.sh
```

The warning about `auto-allocate-uids` came from the wrapper's preliminary
read-only evaluations, which enable only `nix-command flakes`. The actual test
build explicitly enabled `auto-allocate-uids` and `cgroups`, satisfied the
derivation's `uid-range` requirement, executed the container, and produced the
valid output above. Dirty-tree warnings were expected because the exact test
implementation had not yet been committed.

## Passed subtests

The daemon build log records completion of all 13 subtests:

1. unretained boot candidate refused;
2. exact generation-two pre-state verified;
3. unknown profile entry refused and preserved;
4. foreign upstream-root collision refused and preserved;
5. post-registration failure restored generation two;
6. post-activation failure removed the boot edge and restored generation two;
7. successful apply selected generation three and installed one boot edge;
8. duplicate apply refused and preserved generation three;
9. rollback refused a foreign root before live mutation;
10. first fresh container start automatically started the boot-persistent
    manager target and canary service;
11. rollback after that start restored exact no-boot generation two;
12. second fresh container start proved the manager target and canary service
    no longer start automatically;
13. cleanup restored empty, unregistered System Manager state.

The test also kept the protected files unchanged, preserved all earlier
generations and pilot roots until cleanup, kept `/run/current-system` absent,
kept the service inventory fixed at three units, and verified the exact tracked
file set in both generations.

## Host postflight

The root wrapper compared the real host state before and after the test. An
independent post-test audit then returned:

```text
STATE=ACTIVE_REGISTERED_GENERATION_TWO_RETAINED
GEN3_ROOT=ABSENT
BOOT_LINK=ABSENT
```

Therefore the disposable test changed only Nix-store/cache/build artifacts on
the host. The live System Manager profile, activation, direct roots, services,
and boot behavior remain generation two.

## Remaining boundary

This PASS authorizes no live change. Generation-three host retention,
registration, activation, rollback-timer arming, boot linkage, and any real
host reboot still require explicit operator authorization. The later
[guarded live activation plan](2026-09-02-boot-persistence-live-plan.md) now
defines exact snapshot and activation helpers, but neither has run. Its
transient rollback does not survive reboot, so live activation and the first
real reboot remain separately authorized milestones.
