# Headless/factory-GNOME controller candidates — 2026-09-05

## Result

**CANDIDATES BUILT AND POLICY-PASSED; DISPOSABLE LIFECYCLE NOT YET RUN.**

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
  generation, Bash syntax, Nix formatting, and ShellCheck. Its actual systemd
  lifecycle needs the root-local container builder and remains the next gate.

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

## Next gate

From a clean commit, run:

```console
sudo ./scripts/test-desktop-mode-lifecycle.sh
```

The wrapper first proves the live host is still exact generation four with
factory GNOME and no controller paths. Only inside a disposable Ubuntu
container it then exercises headless declaration, runtime isolation, reboot,
GNOME declaration, runtime isolation, reboot, GNOME-to-headless return,
controller removal/factory fallback, and a final reboot. It requires
System Manager and Nix-managed Tailscale to survive every transition.

A PASS authorizes design of the guarded live switch transaction. It does not
itself authorize a profile registration, target isolation, GUI termination,
desktop switch, or reboot on `sparkle-01`.
