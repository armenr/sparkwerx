# Desktop headless host attempt 1 — 2026-09-05

## Result

**SAFE ROLLBACK COMPLETE; FACTORY GNOME RETAINED.**

The guarded operator successfully reached exact System Manager generation five
and headless mode without a reboot. Nix-managed Tailscale stayed online with
the same node identity, the GPU health check passed, and systemd remained
healthy. Confirmation correctly stopped when the postflight found that a
service classified as continuity-protected had changed.

The operator's persistent rollback then restored exact generation four,
factory `graphical.target`, GDM, and the DGX Dashboard. The rollback guard was
removed only after an exact one-shot verifier established that the Dashboard
restart was the sole expected process/timestamp difference. The generation-five
candidate GC root remains retained for a future reviewed retry.

## Exact host evidence

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Snapshot | `inventory/sparkle-01/raw/desktop-mode-switch/20260905T134345Z` |
| Starting/rollback generation | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` (generation four) |
| Headless candidate | `/nix/store/20qw0af0jwfqi5spgg3b1nrc0yydhlc1-system-manager` (generation five) |
| Headless state reached | Yes |
| Reboot performed | No |
| Tailscale | Running, online, SSH enabled, identity unchanged |
| Final desktop | Factory GNOME/GDM |
| Final systemd health | `running`, zero failed units |
| Guard cleanup | Passed; rollback surface absent |
| Candidate retention | Exact generation-five pilot root retained |

The cleanup helper was deliberately ephemeral and snapshot-specific:
`/tmp/dgx-desktop-cleanup-expected-dashboard-restart.sh`, SHA-256
`e96b728c0571da1efd38aa24c8e427ef9350834ce6cd65649cd9110292a15706`.
It accepted only the exact private snapshot, repository commit, generation,
service fragments, Tailscale identity, and expected Dashboard-only restart.
Its successful result was:

```text
PASS|preflight|factory rollback exact; only expected Dashboard PID/timestamp changed
PASS|cleanup|guard removed; generation four/factory GNOME retained; headless candidate root retained
SNAPSHOT=/home/n0b0dy/Development/DGX-setup/inventory/sparkle-01/raw/desktop-mode-switch/20260905T134345Z
```

## Cause

`dgx-dashboard.service` is the user-facing factory Dashboard. Its factory unit
is wanted by `default.target`, so isolating the reviewed headless target
correctly stops it along with GDM. Returning to factory GNOME correctly starts
it again, necessarily producing a new PID and activation timestamp.

The operator incorrectly included that GUI service in the same-PID continuity
set with mode-independent infrastructure. The disposable fixtures modeled GDM
but omitted the real Dashboard unit and its `default.target` dependency, so the
earlier tests could not expose the classification error.

`dgx-dashboard-admin.service` is different: it belongs to
`multi-user.target`, remains useful in headless mode, and must remain in the
continuity-protected set with Docker and `nvidia-persistenced.service`.

## Corrected contract and gate

- `dgx-dashboard.service`: factory-owned, active in GNOME, inactive in
  headless; its restart is expected when returning to GNOME.
- `dgx-dashboard-admin.service`: factory-owned, active and continuity-protected
  in both modes.
- Docker and `nvidia-persistenced.service`: active and continuity-protected in
  both modes.
- GDM and the Dashboard GUI are captured in the private switch snapshot for
  forensics but are not required to retain a same-boot PID across a mode
  transition.

The old disposable proofs are superseded until all three desktop lifecycle
tests pass with a factory Dashboard fixture. No live retry is authorized by
this record. Use only `scripts/dgx-desktop` after current evidence is recorded;
never activate a raw candidate or isolate a target directly on the host.

## Follow-up disposable feedback

The first Dashboard-aware combined rerun passed the 12-subtest transaction
test, including same-boot Dashboard stop/restart behavior. Its mode-lifecycle
test then failed only inside the container on the first headless reboot:
Ubuntu's persistent `default.target.wants/dgx-dashboard.service` edge started
the GUI service alongside the headless dispatcher.

The corrected headless target therefore explicitly conflicts with the existing
factory `dgx-dashboard.service`. A conflict is required—not package removal,
unit replacement, or a mask—because the factory wants edge remains installed.
The non-required GUI start job is discarded when headless is selected, while
the independent Dashboard admin daemon remains under `multi-user.target`.

That target correction produces a new immutable generation-five candidate.
The next guarded switch atomically moves the main candidate root to the
corrected output while preserving the superseded candidate at
`/nix/var/nix/gcroots/dgx-setup-desktop-headless-pre-dashboard-pilot`. The
rollover is not a live activation and occurs only after current lifecycle
evidence passes and the persistent factory rollback is being installed.

The next combined disposable run proved that corrected cold headless boot,
then exposed the complementary named-target transition: directly isolating
`dgx-gnome.target` does not traverse the vendor
`default.target.wants/dgx-dashboard.service` link. The GNOME orchestration
target now non-fatally wants the existing Dashboard GUI service. The complete
two-way contract is therefore: headless conflicts with the GUI, while GNOME
wants it. Nix still owns neither vendor unit nor package. This second finding
also occurred only inside the disposable container. The final corrected
combined run passed and is recorded in the
[Dashboard-aware stack validation](2026-09-05-dashboard-aware-stack.md), so
the test/evidence block is cleared. A live retry still requires separate
authorization and the guarded operator.
