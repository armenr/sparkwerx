# System Manager boot-persistence transaction plan — 2026-09-02

## Status and authorization boundary

**DISPOSABLE TRANSACTION AND TWO-RESTART TEST PASSED; LIVE CHANGE NOT AUTHORIZED.**

This record authorizes repository evaluation, inert Nix-store builds, and the
root-only disposable `systemd-nspawn` test. It does **not** authorize creating
the generation-three host retention root, registering or activating generation
three, adding a boot link on `sparkle-01`, arming a live rollback timer, or
rebooting the host.

The current host state remains
`ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`: generation two is selected,
upstream-rooted, directly pilot-rooted, and active; generation one remains
registered and directly pilot-rooted; boot linkage is absent.

## Exact inputs

| Field | Value |
| --- | --- |
| Required host state | `ACTIVE_REGISTERED_GENERATION_TWO_RETAINED` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Transaction | `scripts/root-boot-persistence-transaction.sh` |
| Transaction SHA-256 | `53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288` |
| Disposable test | `root/system-manager/boot-persistence-transaction-test.nix` |
| Test wrapper | `scripts/test-root-boot-persistence-transaction.sh` |
| Test derivation | `/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv` |
| Test output | `/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction` |
| Test output hash | `sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn` |
| Test state | passed at `2026-09-02T10:11:07Z` |

## Reviewed generation-three delta

Generation three inherits generation two. Policy evaluation and direct output
inspection establish this exact delta:

- the canary payload adds only `boot-persistence-generation=3`;
- the managed service JSON is byte-identical to generation two;
- the global package set remains empty;
- `system-manager.linkCurrentSystem` remains false;
- the generated systemd tree adds exactly one symlink and its parent directory:
  `default.target.wants/system-manager.target -> ../system-manager.target`;
- no Nix, user/group, wrapper, PATH, Tailscale, GDM, Docker, NVIDIA, dashboard,
  port, or mutable application-state ownership is added.

This is declarative System Manager ownership. The repository never creates the
boot link by hand. Activating generation three adds it through the tracked
`/etc` state; reactivating generation two removes it through that same state.

## Transaction boundary

The transaction accepts the three exact System Manager outputs and has four
actions:

- `verify-before`: require exact selected/rooted/live no-boot generation two;
- `apply-boot`: register generation three, verify generation three selection
  and the upstream root, activate it, and verify the one exact boot edge;
- `verify-after`: require exact selected/rooted/live boot generation three;
- `rollback-boot`: activate generation two first, then select generation two,
  remove only the exact generation-three profile link, and atomically restore
  the upstream root to generation two.

All three dedicated pilot roots must already point directly to their exact
candidates. The transaction never creates, changes, or removes those roots.
Unknown profile entries, unknown GC-root targets, non-symlink collisions,
candidate drift, service-inventory drift, marker drift, or boot-edge drift fail
closed.

## Disposable proof obligations

The root-only wrapper first classifies the real host as exact retained/live
generation two and requires the generation-three host root to be absent. The
test then performs every mutation only inside a disposable Ubuntu
`systemd-nspawn` filesystem.

The test must prove:

1. an unretained generation-three candidate is refused;
2. an unknown profile entry is preserved and refused;
3. a foreign upstream-root collision is preserved and refused;
4. injected failures after registration and after activation restore exact
   generation two and remove the boot edge;
5. a successful transaction creates exactly generation three plus the one
   tracked boot link while preserving generations one/two and all pilot roots;
6. duplicate apply is refused without mutation;
7. rollback refuses a foreign root before changing live state;
8. after stopping the managed runtime and restarting the container, the boot
   link starts `system-manager.target` and `dgx-setup-canary.service` while the
   reactivation-only sysinit target remains inactive;
9. rollback after that restart restores generation two and removes the boot
   edge;
10. after a second container restart, neither the manager target nor canary
    service starts automatically;
11. final cleanup returns the disposable filesystem to empty, unregistered
    System Manager state;
12. `/etc/nix/nix.conf`, passwd, group, shadow, and the bounded ownership
    surface remain unchanged throughout.

The wrapper reclassifies the real host afterward and fails if its state changed
or if a generation-three retention root appeared.

## Gates after a passing disposable test

A passing test still does not authorize a host boot link or reboot. The
[separate guarded live activation plan](2026-09-02-boot-persistence-live-plan.md)
now exists and is hash-pinned, but neither helper has run and its existence
grants no host authority. It contains:

- a fresh private snapshot bound to the exact repository commit, candidate,
  transaction hash, and passed test derivation/output;
- exact protected-service and access checks, including Tailscale SSH and a
  verified physical console;
- an exact generation-three pilot root created before registration;
- a timed rollback armed before activation and independent of Tailscale;
- local-console confirmation before disarming rollback;
- a separate guarded reboot window with post-boot classification and an
  automatic rollback path that remains usable if networking does not return.

The activation wrapper deliberately performs no reboot because its transient
rollback timer cannot survive one. Until a fresh exact snapshot receives
explicit authorization, generation three remains an inert Nix-store candidate
only. A first real reboot remains a separate persistent-recovery plan and
authorization even after a successful live activation.
