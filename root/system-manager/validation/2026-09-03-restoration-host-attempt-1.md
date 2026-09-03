# Generation-three restoration host attempt 1

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: automatic rollback completed; retry is safe

## Attempt

The first restoration used private snapshot `20260903T042141Z` and the
hash-pinned helper from repository commit `e8e7261`. The helper armed its
ten-minute transient generation-two rollback before mutating the host.
Generation three was registered, selected, activated, and linked at boot at
approximately `2026-09-03T04:21:47Z`. The automatic generation-three
postflight succeeded: System Manager state, protected services, GPU,
sanitized Tailscale SSH state, and protected-file checks were healthy.

The final input was `KEEP RESTORED GENERATION THRE`, missing the last `E`.
The old helper treated that harmless typo as a failed retention confirmation
and deliberately left the rollback armed. A second invocation correctly
refused to start a new restoration while generation three was already live.

At approximately `2026-09-03T04:31:48Z`, the timer ran the exact snapshot copy
of `root-boot-persistence-transaction.sh rollback-boot`. It restored exact
registered/live no-boot generation two, selected generation two, removed only
the generation-three numbered profile link and managed boot edge, and kept all
three direct pilot roots. The transient timer and service then unloaded. The
later manual `systemctl stop` therefore returned `Unit ... not loaded`, which
is the expected spent-timer state rather than a failure.

Independent post-attempt checks classified the host as
`ACTIVE_REGISTERED_GENERATION_TWO_TRIPLE_RETAINED`, with systemd `running`, no
failed units, healthy NVIDIA GPU reporting, healthy Tailscale SSH, absent
persistent recovery surface, and no restoration countdown. This restoration
attempt did not reboot the host.

## Durable correction

The restoration helper now:

- accepts one Enter after the operator verifies local-console access; there is
  no phrase to type;
- performs two full automatic postflight passes and disarms the transient
  rollback automatically only after both pass; and
- recognizes an exact generation-three state with its exact active restoration
  timer as an interrupted in-flight transaction, reloads and validates the
  newest root-owned snapshot, repeats postflight, and finishes retention.

Any failed postflight still leaves the generation-two rollback armed. A
generation-three state without the exact current snapshot and exact timer is
still rejected as drift. Repository status after this record is
`attempt-one-rolled-back-retry-ready`; the old snapshot is spent evidence and
must not be reused manually.
