# Guarded live generation-switch plan

Date: 2026-09-02

Status: **repository design complete; live switch not run or authorized**

## Decision boundary

This milestone implements and statically validates the host wrapper for an
exact System Manager generation-one to generation-two pilot. It does not grant
authority to run that wrapper. Repository evaluation, the snapshot-property
regression test, and the disposable transaction test do not retain generation
two or change the live host.

The next live mutation requires all of the following in the same activation
window:

1. a clean committed repository;
2. the physical display, keyboard, and a usable local terminal independently
   verified;
3. a new root-owned, mode `0700` snapshot no more than 1,800 seconds old;
4. review of the snapshot output and exact candidate/test evidence;
5. explicit snapshot-bound authorization from Armen; and
6. the existing remote terminal kept open while local recovery is checked.

No authorization in an earlier canary, registration, or disposable-test
milestone carries across this boundary.

## Exact reviewed inputs

| Input | Exact value |
| --- | --- |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Transaction | `scripts/root-generation-switch-transaction.sh` |
| Transaction SHA-256 | `ea1a6ddc509eef4ac80aa165e29a6612d1f1b59b93681cdf813ee8b1ff6d8cdd` |
| Passed test derivation | `/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv` |
| Passed test output | `/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction` |
| Passed output hash | `sha256:01zxs9x67jgp5ifskcvkr8lihddw886ysqcqgaaw3v6dr9f18766` |
| Snapshot helper | `scripts/snapshot-root-generation-switch.sh` |
| Live wrapper | `scripts/switch-root-canary-generation-pilot.sh` |
| Snapshot parser | `scripts/systemd-snapshot-property.sh` |
| Parser regression | `scripts/test-systemd-snapshot-property.sh` |

The fixed hashes of the four repository helpers are asserted by
`flake.nix`. The snapshot also records the live wrapper and parser hashes and
copies the exact passed transaction plus parser into its private root-owned
directory. The live wrapper executes the copied transaction, not a mutable
transaction path in the working tree.

## Scope and non-scope

The only intended live configuration delta is the harmless canary marker
`registration-test-generation=2`. Generation two otherwise has the same empty
package list, five managed paths, three managed services/targets, disabled
boot link, and rejected root-manager defaults as generation one.

This pilot does not:

- add a boot link or test reboot persistence;
- add, remove, restart, or take ownership of a factory/access service;
- change Nix, Tailscale, Docker, NVIDIA, GDM, users, groups, wrappers, PATH, or
  desktop mode;
- remove generation one or either direct pilot GC root;
- retire the apt-managed Tailscale daemon; or
- authorize a broader root role or a real managed workload.

## Required initial host state

The snapshot helper and live wrapper both fail closed unless the host is exact
`ACTIVE_REGISTERED_RETAINED` generation one:

- `system-manager -> system-manager-1-link ->` exact generation one;
- `system-manager-current ->` exact generation one;
- `dgx-setup-root-canary-pilot ->` exact generation one;
- generation-two profile link and pilot root absent;
- the exact five-path/three-service manager state active;
- no `default.target` boot edge;
- all seven protected factory/access services loaded, active, unrestarted,
  loaded from their original fragments, and needing no daemon reload;
- systemd running with zero failed units;
- a responsive NVIDIA GPU; and
- Tailscale backend running, this node online, `WantRunning=true`, and
  `RunSSH=true`.

The protected service continuity check binds `FragmentPath`, `MainPID`, and
`ActiveEnterTimestampMonotonic` per complete blank-line-delimited systemctl
record. `scripts/test-systemd-snapshot-property.sh` protects against the prior
cross-record parsing bug where systemctl emitted a property before `Id`.

## Private snapshot

The snapshot helper accepts one new directory below:

`inventory/sparkle-01/raw/system-manager-generation-switch/`

It creates that directory root-owned and mode `0700`, then records:

- repository commit and clean-tree state;
- exact candidates, transaction checksum, passed derivation/output/hash, Nix
  version, and kernel;
- exact registration, GC-root, managed-link, and manager-state pre-state;
- hashes of `/etc/nix/nix.conf`, `/etc/passwd`, `/etc/group`, and `/etc/shadow`;
- per-unit protected service continuity fields;
- sanitized systemd, GPU, and Tailscale health only;
- exact root-owned copies of the passed transaction and systemd parser; and
- a checksum manifest and completion marker.

The snapshot contains private host evidence. It must remain untracked and must
not be relaxed from root ownership/mode `0700`. Snapshot creation performs no
retention, registration, activation, daemon reload, or service change. An
incomplete or older-than-30-minute snapshot is unusable.

## Live state machine

| Stage | Exact state |
| --- | --- |
| Initial | Generation one selected, upstream-rooted, pilot-rooted, and live; generation two absent |
| Retain candidate | Create only `dgx-setup-root-canary-generation-two-pilot ->` exact generation two; generation one remains selected/live |
| Arm rollback | Start `dgx-root-generation-switch-rollback.timer`, ten minutes, invoking exact copied transaction action `rollback-switch` |
| Switch | Register generation two, select it, point `system-manager-current` to it, and explicitly activate it |
| Postflight | Generation two selected/upstream-rooted/live; both candidates directly pilot-rooted; generation one preserved; no boot edge |
| Keep | After physical-console verification, accept only `KEEP GENERATION TWO`, rerun full postflight, then stop the rollback timer |
| Roll back | Reactivate generation one, select generation one, restore its upstream root, and remove only exact `system-manager-2-link` |

Rollback deliberately leaves both direct pilot roots. The generation-two pilot
root is a recovery anchor, not litter. Its removal is a later, separately
reviewed exact cleanup after verified rollback or a separately approved stable
generation-two milestone.

## Failure behavior

- Failure before generation-two retention changes nothing.
- Failure after retention but before timer establishment leaves generation one
  live and leaves the exact generation-two root for explicit review/cleanup.
- The wrapper never begins the switch until the rollback timer is active,
  waiting, and its service contains the exact transaction/action/candidates.
- Failure, disconnect, Ctrl-C, wrong confirmation, or confirmation timeout after
  the timer is armed leaves rollback armed.
- Transaction rollback is idempotent across its tested partial registration,
  root synchronization, activation failure, and already-rolled-back states.
- An unknown profile entry, GC root, managed path, manager state, candidate,
  test artifact, repository change, protected-file hash, protected-process
  restart, health failure, or boot edge is a hard stop.

If the timer fires, the expected state is exact registered/live generation one,
no generation-two profile link, and both direct pilot roots retained. A later
postflight must prove that state; it must not infer success merely from timer
inactivity.

## Validation required before any live authorization

- `bash -n` passes for the snapshot helper, wrapper, parser, parser regression,
  and exact transaction.
- The parser regression passes both directly and as the Nix check
  `root-canary-systemd-snapshot-property`.
- `nix flake check --no-build` passes.
- The root-manager policy and exact passed generation-switch transaction
  derivation remain current.
- The four earlier disposable derivations remain exact and hash-valid.
- Read-only host audit still reports `ACTIVE_REGISTERED_RETAINED`, with the
  generation-two pilot root and boot link absent.

## Repository validation result

At `2026-09-02T08:18:54Z`, before any live authorization:

- all five shell programs passed `bash -n`;
- the parser regression passed directly;
- `nix flake check --no-build` passed, including exact unchanged paths for all
  four prior disposable tests;
- the parser regression built as
  `/nix/store/alhrx50awmpplfica5hcl6v0l1fiwf2p-dgx-systemd-snapshot-property-test.drv`,
  producing
  `/nix/store/ygzkhzvqqarqjlp8m3mwmg9b1lyv7xq6-dgx-systemd-snapshot-property-test`
  with hash
  `sha256:1z81jhswv19vzv8y4c8v6wdxflnhqni1z2sib5vd26dhri5k7m1j`;
- the root-manager fixed-hash policy evaluated and built at
  `/nix/store/6wmynp3k1202xznz9ar87r1vqswlzgsd-dgx-root-manager-policy.drv`;
- final helper SHA-256 values were `a82669f4…` (snapshot), `e9432ea7…`
  (live wrapper), `1123fe7e…` (parser), and `d9829ce6…` (parser test); and
- read-only host checks returned exact `ACTIVE_REGISTERED_RETAINED`, with both
  the generation-two pilot root and boot edge absent.

These results changed no registration, root, managed path, service, or boot
state. They validate the repository design only.

After these repository gates pass, stop at the genuine authority boundary:
create no host generation-two root and run no live wrapper until Armen verifies
the local console, reviews a fresh snapshot, and explicitly authorizes that
exact snapshot.
