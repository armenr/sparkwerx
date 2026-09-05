# Headless/factory-GNOME controller candidates — 2026-09-05

## Result

**CURRENT DASHBOARD-AWARE CANDIDATES AND ALL DISPOSABLE LIFECYCLES PASS. FIRST
LIVE ATTEMPT ROLLED BACK CLEANLY; A GUARDED RETRY IS READY FOR SEPARATE
AUTHORIZATION.**

The first root desktop-controller implementation adds only two thin systemd
targets, one selected `default.target` dispatcher, and one non-secret mode
marker on top of exact live System Manager generation four. It does not package,
replace, mask, or edit factory GDM/GNOME.

This document originally recorded pre-live candidate evidence. A later guarded
host attempt reached headless generation five, preserved Nix-managed Tailscale,
then failed closed on an incomplete service classification. Persistent rollback
returned the host to factory GNOME with exact generation four; no reboot was
performed. See the
[host-attempt record](../root/desktop/validation/2026-09-05-host-attempt-1.md).
The corrected two-way Dashboard boundary then passed the complete transaction,
three-reboot mode, persistent rollback, and post-Tailscale integration stack.
See the
[current validation record](../root/desktop/validation/2026-09-05-dashboard-aware-stack.md).

## Host facts that shape the design

Read-only inspection found:

- the factory `/usr/lib/systemd/system/default.target` aliases
  `graphical.target`;
- `/etc/systemd/system/default.target` is absent, so a reviewed override has no
  collision;
- `/etc/systemd/system/display-manager.service` is the factory alias to GDM;
- `gdm.service` is active from `/usr/lib/systemd/system/gdm.service`; and
- the user-facing `dgx-dashboard.service` is wanted by `default.target`, while
  `dgx-dashboard-admin.service` belongs to `multi-user.target`; and
- Tailscale is managed under `system-manager.target`.

The last point matters. System Manager intentionally substitutes a service's
ordinary `WantedBy=multi-user.target` with `system-manager.target`. A headless
isolate that retained only Ubuntu's `multi-user.target` could therefore stop a
Nix-managed access service on a clean future Spark. The new
`dgx-headless.target` explicitly requires both `multi-user.target` and
`system-manager.target`, preserving Tailscale without relying on
`sparkle-01`'s retained apt fallback enablement link.

## Exact candidate surface

| Mode | System Manager output | Closure size |
| --- | --- | --- |
| Current generation-four rollback boundary | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` | 312,125,456 bytes |
| Superseded first-attempt headless candidate | `/nix/store/20qw0af0jwfqi5spgg3b1nrc0yydhlc1-system-manager` | 312,130,992 bytes |
| Intermediate Dashboard-conflict headless candidate | `/nix/store/3rnw3fnaazga52ms8mz613s6czvdkz8a-system-manager` | 312,131,232 bytes |
| Intermediate Dashboard-conflict factory-GNOME candidate | `/nix/store/j3153lsxpflz7rappri3l7qczd2g91m2-system-manager` | 312,131,200 bytes |
| Current two-way Dashboard headless candidate | `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager` | 312,131,456 bytes |
| Current two-way Dashboard factory-GNOME candidate | `/nix/store/i8224bkma5f805ncarwpfmbnd9yc1dn9-system-manager` | 312,131,424 bytes |

The current headless delta is 6,000 bytes and the current GNOME delta is 5,968
bytes. Both reuse the entire existing closure; neither adds a desktop package,
global package, portal, user service, or daemon. The small increase is the
documented two-way Dashboard orchestration in the shared immutable target tree.

The selected candidate owns exactly these four additional paths:

- `/etc/dgx-setup/desktop-mode`;
- `/etc/systemd/system/default.target`;
- `/etc/systemd/system/dgx-headless.target`; and
- `/etc/systemd/system/dgx-gnome.target`.

`dgx-headless.target` requires `multi-user.target` and
`system-manager.target`, conflicts with `graphical.target`, the GNOME mode
target, and the factory Dashboard GUI service, and is isolatable.
`dgx-gnome.target` requires factory `graphical.target` plus
`system-manager.target`, wants the existing factory Dashboard GUI service,
conflicts with the headless target, and is isolatable. The `Wants=` edge is
non-fatal and does not transfer package or unit ownership to Nix.

System Manager does not implement unit aliases. A direct immutable link to a
mode target is not equivalent: systemd loads its contents under the lookup name
`default.target`, leaving the named mode target inactive. The module therefore
supplies a tiny immutable `default.target` dispatcher which explicitly requires
and orders itself after the selected generated mode target. Removing the role
removes the `/etc` override and exposes Ubuntu's original `/usr/lib` graphical
default again.

Systemd classifies the immutable Nix-store destination as a linked unit because
it is outside the normal unit search path. While the controller is present,
`systemctl get-default` therefore reports the lookup name `default.target`.
This is not used alone as the mode classifier: the dispatcher dependency and
the independently managed `/etc/dgx-setup/desktop-mode` marker must agree, and
the selected named target must be active after boot. When the controller is
removed, `systemctl get-default` again reports the factory `graphical.target`
alias.

Activation changes only persistent declaration. It deliberately does not
isolate a runtime target or terminate a GUI session by surprise; the eventual
guarded switch operator owns that separately visible action.

## Completed static checks

- Both full ARM64 System Manager candidates built successfully.
- The desktop-controller policy check passed.
- Each generated dispatcher has exact `Requires=` and `After=` dependencies on
  its selected named mode target.
- Generated targets have the exact dependency/conflict/`AllowIsolate`
  contract.
- Neither candidate declares `gdm.service` or `display-manager.service`.
- Both candidates retain generation four's exact four-entry active-service
  map; the mode targets exist only in the immutable unit tree.
- Both retain the exact Nix-managed Tailscale service and empty global package
  set.
- Importing the disabled module leaves the current generation-four output
  byte-for-byte identical.
- The disposable test script passed Nix evaluation, Python type/lint
  generation, Bash syntax, Nix formatting, and ShellCheck.

## Disposable feedback incorporated

The first root-local run stopped after declaration because the test expected
`systemctl get-default` to report the final target basename. Read-only replay
against the candidate unit tree proved that systemd reports the linked lookup
name `default.target`; the test now checks that behavior separately from mode
selection.

The second run passed declaration and runtime headless isolation, then rebooted
successfully into the intended headless dependency graph with Tailscale active.
It exposed the deeper alias limitation: systemd loaded the target file under
the name `default.target`, so `dgx-headless.target` itself was inactive. The
direct alias was replaced with the dispatcher described above. Both failures
were inside the disposable container; the wrapper's before/after host boundary
checks passed and no live-host controller path was created.

The third run passed the complete headless boot, GNOME declaration/isolation/
boot, and GNOME-to-headless return. During final controller removal, System
Manager exited successfully but logged a non-fatal error while trying to stop
the already-unloaded inactive `dgx-gnome.target`. The targets now remain in the
managed immutable unit tree but outside System Manager's active-service map.
This makes declaration and removal persistence-only operations and leaves all
runtime target transitions to the future guarded desktop operator.

The historical fourth run, from repository commit
`e80dec6979663dcffd80834294dd0405e744e3f9`,
passed all ten lifecycle subtests at `2026-09-05T11:23:31Z`. It exercised three
disposable reboots and proved headless persistence, GNOME persistence, both
runtime directions, controller removal, factory fallback, unchanged
Nix-managed Tailscale access, and an unchanged live host.
The [exact validation record](../root/desktop/validation/2026-09-05-mode-lifecycle-container-test.md)
contains the complete authority boundary and failed-feedback history.

| Evidence | Exact value |
| --- | --- |
| Test derivation | `/nix/store/qv3v6lglnqigqa60qs3zg4x5qkcy6hsw-container-test-dgx-desktop-mode-lifecycle.drv` |
| Test output | `/nix/store/58ca2p4a20hfsvy5is4dzk0g5zs60rqg-container-test-dgx-desktop-mode-lifecycle` |
| Output hash | `sha256-+/qYifYr8D2anu1gDOqkx43Cb9oaa461uR+45rX4PoE=` |
| Nix-base32 hash | `109yz2sydf0zp6sqwsqsv9pw53f7lkm0qq7dksd3vw1bys4riypv` |
| Container reboots | 3 |
| Host mutation | None |

The first Dashboard-aware combined rerun proved the transaction-level
headless stop and GNOME restart behavior, then exposed that the vendor
`default.target.wants` link could still start the Dashboard on a cold headless
boot. The explicit headless conflict fixed that path.

The next combined rerun proved the corrected cold headless boot and advanced
through GNOME declaration. Its direct `systemctl isolate dgx-gnome.target`
transition then left the Dashboard inactive because a named-target isolate
does not traverse `default.target.wants`. The GNOME target now has a non-fatal
`Wants=dgx-dashboard.service` edge. Together, the conflict and want express
the intended mode boundary without replacing, masking, or packaging the
factory service. Both findings occurred only inside disposable containers.

The final run from repository commit
`abb852d320a01192236d862336bf60c31943714a` passed all three corrected desktop
lifecycles and the required post-Tailscale live no-op integration. Its exact
derivations, outputs, hashes, candidates, and authority boundary are recorded
in the
[Dashboard-aware stack validation](../root/desktop/validation/2026-09-05-dashboard-aware-stack.md).

## Current gate result and next host boundary

The old guarded lifecycle remains useful historical evidence, but it omitted a
factory Dashboard fixture and is not current authority. The corrected suite
now proves all of the following:

- `dgx-dashboard.service` stops with GDM in headless mode and starts with
  factory GNOME, including same-boot rollback and reboot recovery;
- `dgx-dashboard-admin.service`, Docker, NVIDIA persistence, and Nix-managed
  Tailscale preserve their intended continuity;
- the transaction, three-reboot mode lifecycle, and persistent guarded switch
  all pass in disposable containers; and
- the post-Tailscale live integration remains a no-op.

`sparkle-01` still retains the superseded first-attempt headless candidate at
the normal headless pilot root. On the next guarded switch, the operator first
preserves that exact output at
`/nix/var/nix/gcroots/dgx-setup-desktop-headless-pre-dashboard-pilot`, then
atomically selects the corrected candidate at the normal pilot root. A fresh
Spark with no historical candidate skips this rollover entirely, and does not
need the old output in its Nix store.

The regression and exact evidence gate are complete. `scripts/dgx-desktop` is
now eligible for a separately authorized live retry. The proof does not itself
authorize a switch or reboot; the host remains on exact generation four with
factory GNOME until the guarded operator is explicitly invoked.
