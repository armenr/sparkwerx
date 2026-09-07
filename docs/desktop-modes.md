# Desktop modes

[Documentation](README.md) · [Status](status.md) · [Roadmap](roadmap.md)

The design is one mode: `headless`, factory `gnome`, `hyprland`, or `kde`.
The complete four-way switching experience is **not implemented yet**.

Armen's selected target is Hyprland for both local and remote use, with factory
GNOME/Xorg kept as the familiar alternate. The [optional KMS trial](nvidia-kms.md)
and [temporary Hyprland capture](../remote-desktop/validation/2026-09-06-temporary-capture-host.md)
passed on the pilot; neither installs a persistent desktop session.

[Remote desktop](remote-desktop.md) is an optional Sunshine/Moonlight role over
Tailscale. It stays dormant in compute-only headless mode. Streaming without a
monitor still needs a graphical session; it is not a reason to start one during
a headless apply.

## What's implemented

| Mode | User composition | Host integration |
| --- | --- | --- |
| `headless` | CLI base and all-modes overlay; no graphical packages or Home Manager user units | Live-confirmed on the pilot; supported final state for fresh-host converge |
| `gnome` | Graphical profile with Ghostty and MIME machinery; personal app activation still separate | Factory stack retained; controller and reversible transitions tested in containers |
| `hyprland` | Pinned candidate; portal is independent | Temporary NVIDIA graphics/readback passed; persistent session and GDM rollout still open |
| `kde` | Mode value exists | No selected Plasma package set or proven host integration |

[`modules/home/desktop.nix`](../modules/home/desktop.nix) controls user
composition. [The root controller](../modules/system/desktop-mode.nix) controls
boot/runtime targets. Changing the Home profile alone cannot stop GDM.

## What headless does

On the confirmed pilot:

- GDM, the graphical target, and the Dashboard GUI are inactive.
- Dashboard Admin, Docker, NVIDIA persistence, and selected Tailscale remain active.
- The Home profile has no graphical packages or Home Manager user-systemd units.
- The default boot dispatcher selects the headless target.
- Factory GNOME/GDM packages stay installed for recovery and later desktop work.

This is not an Ubuntu-desktop uninstall. It also isn't a blanket process
killer: a separately launched application or unmanaged lingering user service
needs its own diagnosis. Don't claim every graphics-related process is absent
without inspecting it.

Installed packages use disk; stopping their services saves runtime resources.
GPU compute does not require a running desktop. A workload's headless rendering
option is a separate workload setting, not a host desktop switch.

## Commands and limits

For the current historical pilot, inspect without switching:

```bash
./scripts/dgx-desktop status
```

The actual command interface is:

```text
plan | headless | status | confirm | rollback | cleanup-rolled-back
```

There is no `gnome`, `hyprland`, or `kde` subcommand. The operator implements
the pilot's initial factory-to-headless transaction and its in-flight recovery.
After a confirmed transition removes its guard, `rollback` is not a general
“turn the desktop back on” command.

The fresh-host route uses `dgx-setup converge` and `dgx-fleet-bootstrap`
instead. It keeps factory GNOME for the first root generation, requires a
separate reboot, then transitions to headless. See
[fresh-host convergence](fresh-host-convergence.md).

A general retained-headless → GNOME → headless operator is remaining work.
Implement and test that route before advertising a toggle. Don't substitute
raw `systemctl isolate`, enable GDM manually, or activate an unreviewed Nix
output on the retained host.

## Why the Dashboard matters

The factory Dashboard GUI has a `default.target.wants` edge, separate from
GDM. Simply avoiding the graphical target is insufficient on a cold boot.

The headless target explicitly conflicts with the existing GUI service. The
GNOME target explicitly wants it, because a direct named-target transition
does not traverse the factory default-target edge. Neither mode replaces,
masks, or owns the factory unit/package.

Dashboard Admin is a different service. Keep it active in both modes. This
distinction caused the first pilot verification failure and is now covered by
the [Dashboard-aware lifecycle tests](../root/desktop/validation/2026-09-05-dashboard-aware-stack.md).

## Why XDG and MIME are separate

`xdg.enable` manages base-directory environment behavior; it is not a daemon
or a meaningful RAM-saving toggle. The minimal profile leaves that ownership
alone until a role needs it.

| Home Manager option | What it adds or owns |
| --- | --- |
| `xdg.enable` | XDG base-directory environment variables |
| `xdg.mime.enable` | Shared MIME data, directory sentinels, and database regeneration—not default apps or a persistent daemon |
| `xdg.mimeApps.enable` | Default application/file-association policy |
| `xdg.userDirs.enable` | User-directory definitions |
| `xdg.portal.enable` | Portal packages, configuration, and user services |

The current module disables XDG/MIME management in headless and enables those
two pieces in graphical profiles. MIME defaults, user directories, and portals
remain independent.

Hyprland's module would normally include its portal implicitly. Sparkwerx sets
`portalPackage = null`; only the separate
`dgx.desktop.hyprland.portal.enable` choice adds the reviewed portal graph.

## What a graphical rollout still needs

Keep factory GNOME available as recovery. Validate the graphics bridge and
version-matched NVIDIA userspace, session entry, file pickers, URL handling,
screen sharing, suspend/wake, Electron apps, and compute continuity. Inspect
the portal closure separately from the compositor.

Ghostty is shared graphical infrastructure, not part of the headless base or
Armen-only overlay. Chromium, Zed, and LM Studio still require their individual
sandbox/GPU/runtime checks before entering a profile.

Evidence: [successful host transition](../root/desktop/validation/2026-09-05-host-attempt-2.md),
[retained-headless integration](../root/desktop/validation/2026-09-05-confirmed-headless-integration.md),
and [candidate details](2026-09-05-desktop-controller-candidates.md).
