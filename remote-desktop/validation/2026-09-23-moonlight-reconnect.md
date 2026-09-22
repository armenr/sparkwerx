# Moonlight lag and frozen reconnect

## Observed run

Armen ran `dgx-moonlight-trial start 4k120` after the
[DRM selector correction](2026-09-22-moonlight-drm-enumeration.md), from commit
`d5d35af`. The exact container gate passed, the launcher selected the NVIDIA
`card0` / `renderD128` pair, and status reached `READY_FOR_PAIRING`.

The private snapshot is `20260922T205756Z-e1eafea49450`. Armen reported mouse
lag, then no interaction or rendering after reconnecting. His redacted inspector
output recorded:

- three client connections and three disconnections;
- H.264, HEVC, and AV1 NVENC startup success;
- 355 valid canvas timing windows, with the last at 1776.493 seconds;
- the shown canvas windows at roughly 114–120 submissions/callbacks per second;
- two host-processing means of 46.15 and 45.62 ms;
- host send-path means of 0.07 and 0.06 ms;
- completed cleanup, but generic supervisor exit messages;
- 117 omitted Sunshine diagnostic records.

Canvas submissions do not establish streamed or displayed FPS. The host
processing statistic covers capture-timestamp-to-packet processing and queues,
not only NVENC. Send-path timing is not network round-trip latency. The earlier
MacBook's 32.44 FPS overlay measurement is a different run, not a measurement
of this one.

## What the code explains, and what it does not

The old inspector keeps only the first and last 20 Sunshine diagnostics. The
missing middle can contain reconnect failures. A continuing canvas does not
prove that the capture/encode/transport/input path is healthy.

The trial child exits its loop roughly 20 seconds before the outer 30-minute
deadline; the worker and guardian can observe that exit and emit generic
failure messages. The final canvas sample is consistent with that sequence.
Those messages alone do not prove an earlier compositor crash or explain a
frozen reconnect. This investigation has not changed the shutdown implementation.

The reconnect cause remains unresolved. No extra capability, device permission,
encoder setting, driver replacement, or desktop switch was applied as a guess.

## Read-only report

`scripts/dgx-moonlight-trial diagnose [SNAPSHOT_NAME]` uses a separate
`moonlight-trial-report` Nix output. It reads existing root-private logs, emits
only allowlisted timeline events and redacted error/warning groups, and counts
truncation separately for each section. Error groups retain occurrence counts
and first/last log-relative times; canvas statistics include all valid windows.

The report reads only the three cleanup booleans from `finished.json`. It does
not re-run host postflight, so these are recorded cleanup checks, not new live
health evidence. It rejects symlinked evidence, wrong ownership/modes, and
non-regular files. Each log read has a 16 MiB ceiling and reports omitted prefix
bytes. Authentication/pairing lines and arbitrary input/debug payloads are not
returned.

The report imports no trial controller and adds no package pin, profile entry,
service, listener, GPU session, or host setting. The previously tested trial and
offline diagnostic outputs remain the comparison baseline. The operator still
needs to run the report against the saved private evidence to expose the
reconnect timeline; no additional streaming trial is needed for that step.

## Validation

- All 17 new parser/private-file tests passed both locally and inside the Nix
  report policy build. Cases cover three connection cycles, errors hidden among
  repeated warnings, redaction, clock reversal, truncation, missing evidence,
  read-only operation, and rejection of unsafe paths/files.
- `./scripts/dev check` passed: 284 tests with six skips, documentation,
  formatting/linting, and flake evaluation. No privileged lifecycle or GPU test
  was rerun for this read-only addition.
- The packaged report's help and front-door invalid-argument checks passed.
- Report output:
  `/nix/store/4phmsygfs2a4fbgnf2l0cd8pl33la7xj-sparkwerx-moonlight-report`.
- The existing trial output remains
  `/nix/store/m0p2fxb4j77a5144qw9ay9pm6qcbq9j0-sparkwerx-moonlight-trial`;
  its exact lifecycle recipe remains
  `/nix/store/1y5ml1wy30hd1wmxgpyhm7b131qbnhj8-container-test-dgx-moonlight-trial-lifecycle.drv`.
  The trial gate/policy, normal Sunshine, and offline capture/startup/frames
  output paths also match the pre-edit baseline.
