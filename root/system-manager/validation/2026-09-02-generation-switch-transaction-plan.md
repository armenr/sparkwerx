# Guarded generation-one to generation-two switch — 2026-09-02

## Status

**REPOSITORY DESIGN COMPLETE; DISPOSABLE FAILURE-INJECTION TEST PENDING.**

The live host remains exactly `ACTIVE_REGISTERED_RETAINED`: generation one is
selected, registered, extra-rooted, pilot-rooted, and active. Generation two is
not retained, registered, selected, or active on the host. No boot link exists.

This record authorizes and describes repository evaluation plus the disposable
container test only. It does not authorize creating the generation-two host
retention root, switching the live profile, activating generation two, changing
boot linkage, or rebooting `sparkle-01`.

## Exact design inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Required host state | `ACTIVE_REGISTERED_RETAINED` |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation-two delta | only `registration-test-generation=2` in the harmless canary payload |
| Transaction | `scripts/root-generation-switch-transaction.sh` |
| Transaction SHA-256 | `ea1a6ddc509eef4ac80aa165e29a6612d1f1b59b93681cdf813ee8b1ff6d8cdd` |
| Disposable test | `root/system-manager/generation-switch-transaction-test.nix` |
| Test derivation | `/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv` |
| Expected test output | `/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction` |
| Root-assisted wrapper | `scripts/test-root-generation-switch-transaction.sh` |
| Result | Pending |
| Live switch performed | No |
| Host generation-two retention performed | No |

Generation two inherits the same empty global-package set, exact two etc
entries, exact three System Manager service keys, disabled Nix ownership,
disabled userborn/wrappers/current-system link, empty tmpfiles policy, and no
`WantedBy` boot edge as generation one.

Evaluation-only policy passed with the original activation derivation
`jcrdk9p9…`, registration-lifecycle derivation `m4zm42h6…`, and
first-registration transaction derivation `lxnykcyv…` unchanged. A no-build
plan for generation two plus the new check reported only three missing
derivations: the generated test script, closure metadata, and the isolated test
itself. Generation two was already a valid store output; no host profile, root,
activation, or service path was created.

## Transaction surface

The transaction may operate only on:

- the dedicated selected profile
  `/nix/var/nix/profiles/system-manager-profiles/system-manager`;
- its exact `system-manager-1-link` and `system-manager-2-link`;
- the upstream extra root
  `/nix/var/nix/gcroots/system-manager-current`;
- explicit activation of one of the two exact candidate store outputs; and
- read-only verification of the five-path/three-service live canary.

It requires, but never changes, two direct pilot roots:

- generation one:
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot`; and
- generation two:
  `/nix/var/nix/gcroots/dgx-setup-root-canary-generation-two-pilot`.

It never creates a boot link, changes System Manager ownership, touches a
factory-owned service, edits Nix/users/groups/shadow, adds PATH plumbing,
enables wrappers, or removes either pilot root.

## Exact states

Pre-state:

1. the profile directory contains only `system-manager` and
   `system-manager-1-link`;
2. both resolve exactly to generation one;
3. `system-manager-current` and the generation-one pilot root point directly
   to generation one;
4. the separate generation-two pilot root points directly to generation two;
5. generation one is the exact live five-path/three-service canary; and
6. boot linkage and all broader root-manager paths are absent.

Successful post-state:

1. the directory contains only the selected profile plus exact generation-one
   and generation-two links;
2. the selected profile and upstream extra root point to generation two;
3. both generation links and both pilot roots preserve their exact candidates;
4. generation two is the exact live five-path/three-service canary; and
5. boot linkage remains absent.

Rollback explicitly reactivates generation one when necessary, selects
generation one, removes only the exact generation-two profile link, atomically
synchronizes the upstream extra root back to generation one, and verifies the
full pre-state. Repeating exact rollback is valid.

## Disposable failure matrix

The container check must prove:

1. missing generation-two retention refuses before mutation;
2. an unknown profile entry refuses before mutation;
3. an upstream extra-root collision after preflight exposes partial profile
   advancement, restores the known generation-one profile, and leaves the
   foreign collision untouched;
4. failure after complete generation-two registration restores generation one;
5. failure after generation-two activation restores generation one;
6. a successful switch produces only the exact post-state;
7. duplicate apply refuses without disturbing generation two;
8. rollback refuses a foreign root before changing live activation;
9. exact rollback is idempotent; and
10. disposable cleanup leaves empty version-0 manager state and no registration.

All injected failures are accepted only when
`/run/systemd/container == systemd-nspawn`. The host wrapper builds only the
container check with root-profile Nix, the local store, and process-local
`auto-allocate-uids` plus `cgroups`. It requires
`ACTIVE_REGISTERED_RETAINED` immediately before and after and requires the
host generation-two pilot root to remain absent.

## Execution and authority boundary

After review, the disposable invocation is:

```bash
sudo ./scripts/test-root-generation-switch-transaction.sh
```

That command is not a live switch. If it passes, record the exact derivation,
output, output hash, logs, and independent host postflight in a separate result
record. A pass permits designing the snapshot/timed-rollback/local-console
wrapper; it still does not authorize running that wrapper.

A future live switch requires a new committed design, fresh private root-owned
snapshot, exact two-candidate retention, a ten-minute rollback bound to the
exact transaction, protected-service and Tailscale/GPU postflight, independent
local-console confirmation, and explicit authorization tied to the fresh
snapshot. Stop before that gate.

## Stop conditions

Stop if either candidate, transaction checksum, prior passed test derivation,
registered generation-one surface, live canary payload, protected service,
Tailscale SSH state, GPU/systemd health, pilot root, boot-link boundary, or
repository cleanliness differs from the recorded expectation. Never infer live
switch authority from permission to evaluate, build, or run the disposable
test. Do not reboot while the current retained canary remains intentionally
unlinked from boot.
