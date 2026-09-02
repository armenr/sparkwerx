# Retained System Manager generation two — host attempt 1

Date: 2026-09-02

Status: **generation two retained, registered, selected, and live; rollback
disarmed; generation one retained**

## Authority and exact inputs

Armen created the private snapshot
`inventory/sparkle-01/raw/system-manager-generation-switch/20260902T083437Z`
and explicitly authorized that snapshot:

> I verified the local console and authorize the System Manager generation-one
> to generation-two pilot using snapshot 20260902T083437Z.

The clean repository authority was commit
`df6f53c7403c468722cdd709c7c9b1d568612592`. The reviewed inputs were:

| Input | Exact value |
| --- | --- |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Transaction SHA-256 | `ea1a6ddc509eef4ac80aa165e29a6612d1f1b59b93681cdf813ee8b1ff6d8cdd` |
| Passed transaction test | `/nix/store/0llhzgyraq4gr7m4agbv8wbvs7xdcql2-container-test-dgx-root-canary-generation-switch-transaction.drv` |
| Passed test output | `/nix/store/l5s5m3q4bd338jflq1abycajwxrfbj5v-container-test-dgx-root-canary-generation-switch-transaction` |
| Passed output hash | `sha256:01zxs9x67jgp5ifskcvkr8lihddw886ysqcqgaaw3v6dr9f18766` |

The snapshot helper reported exact registered/live generation one, no
generation-two root, and no host mutation. The private snapshot remains
root-owned, mode `0700`, untracked, and is not reproduced in this repository.

## Direct post-switch observation

The switch surface changed at `2026-09-02T08:38:17Z`. A read-only audit at
`2026-09-02T08:43:41Z` observed:

- `system-manager -> system-manager-2-link`;
- `system-manager-1-link ->` exact generation one;
- `system-manager-2-link ->` exact generation two;
- `system-manager-current ->` exact generation two;
- `dgx-setup-root-canary-pilot ->` exact generation one;
- `dgx-setup-root-canary-generation-two-pilot ->` exact generation two;
- exact version-1 manager state with five managed paths and three service keys;
- all five live managed links resolving to generation-two payloads;
- canary marker `registration-test-generation=2`;
- all forbidden PATH, wrapper, userborn, `/run/current-system`, and
  `default.target` boot-link paths absent; and
- the repository classifier returning
  `ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`.

The generation-switch rollback timer and service were both unloaded and
inactive. No rollback-service journal entry existed for the switch window, so
the rollback service did not run.

Systemd was `running` with zero failed units. The seven protected
factory/access services remained active from their original fragments with no
pending daemon reload: `nix-daemon`, `tailscaled`, `gdm`, `docker`,
`dgx-dashboard`, `dgx-dashboard-admin`, and
`nvidia-persistenced`. The managed canary service and both managed targets
were active. The GPU reported `NVIDIA GB10`, driver `580.173.02`, and a
responsive P8 state. Sanitized Tailscale state remained
`backend=Running;online=true;WantRunning=true;RunSSH=true`. Both Nix client
and daemon reported 2.35.2.

## Confirmation evidence boundary

The terminal transcript was not pasted into the repository session; Armen
reported completion as `done`. The exact retained generation-two state plus
an unloaded rollback timer is nevertheless compatible only with the reviewed
wrapper's successful confirmation path: it accepts exactly
`KEEP GENERATION TWO`, repeats full postflight, and only then stops the timer.
This record does not invent verbatim wrapper output; it distinguishes that
code-and-state inference from the direct read-only observations above.

## Retained boundary

This milestone did not create boot persistence, reboot the host, add a real
managed service, broaden System Manager ownership, change desktop mode, or
migrate Tailscale. Generation one is still registered and directly retained as
the exact rollback generation. Both direct pilot roots are recovery anchors
and must remain.

Do not rerun the one-time snapshot or live switch helpers against this
post-state. Do not remove either profile generation or pilot root, select
generation one, deactivate generation two, add a boot edge, or reboot as
incidental cleanup. Each is a separate reviewed milestone with fresh
preflight, recovery, and authorization.
