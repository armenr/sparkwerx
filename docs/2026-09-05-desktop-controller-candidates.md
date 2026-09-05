# Headless/factory-GNOME controller candidates — 2026-09-05

## Result

**CANDIDATES BUILT; POLICY AND DISPOSABLE LIFECYCLE PASSED; LIVE SWITCH NOT
YET AUTHORIZED.**

The first root desktop-controller implementation adds only two thin systemd
targets, one selected `default.target` dispatcher, and one non-secret mode
marker on top of exact live System Manager generation four. It does not package,
replace, mask, or edit factory GDM/GNOME.

Nothing in this work was activated, registered, rooted, isolated, stopped, or
rebooted on `sparkle-01`. The host remains in factory GNOME with exact
generation four and Nix-managed Tailscale.

## Host facts that shape the design

Read-only inspection found:

- the factory `/usr/lib/systemd/system/default.target` aliases
  `graphical.target`;
- `/etc/systemd/system/default.target` is absent, so a reviewed override has no
  collision;
- `/etc/systemd/system/display-manager.service` is the factory alias to GDM;
- `gdm.service` is active from `/usr/lib/systemd/system/gdm.service`; and
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
| Headless candidate | `/nix/store/20qw0af0jwfqi5spgg3b1nrc0yydhlc1-system-manager` | 312,130,992 bytes |
| Factory-GNOME candidate | `/nix/store/rri20h082q9qkcvwdg1zarp7i46nscy2-system-manager` | 312,130,960 bytes |

The headless delta is 5,536 bytes and the GNOME delta is 5,504 bytes. Both
reuse the entire existing closure; neither adds a desktop package, global
package, portal, user service, or daemon.

The selected candidate owns exactly these four additional paths:

- `/etc/dgx-setup/desktop-mode`;
- `/etc/systemd/system/default.target`;
- `/etc/systemd/system/dgx-headless.target`; and
- `/etc/systemd/system/dgx-gnome.target`.

`dgx-headless.target` requires `multi-user.target` and
`system-manager.target`, conflicts with `graphical.target`, and is isolatable.
`dgx-gnome.target` requires factory `graphical.target` plus
`system-manager.target`, conflicts with the headless target, and is isolatable.

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

The fourth run, from repository commit `e80dec6979663dcffd80834294dd0405e744e3f9`,
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

## Next gate

The guarded live operator and its immutable ten-minute rollback bundle are now
implemented. Separately run and record its exact disposable lifecycle through
`sudo ./scripts/test-desktop-switch-lifecycle.sh`. That proof includes
same-boot rollback, confirmation, headless reboot recovery, Nix-managed
Tailscale continuity, and an unchanged host boundary. It does not itself
authorize profile registration, target isolation, GUI termination, a live
desktop switch, or reboot on `sparkle-01`.
