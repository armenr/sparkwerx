# Desktop modes

The fleet needs one reversible host-level mode switch, not a collection of
loosely related booleans:

`dgx.desktop.mode = "headless" | "gnome" | "hyprland" | "kde"`

The enum and its Home Manager package composition are implemented. Exact
root-level `headless` and factory-`gnome` controller candidates are also built
and policy-checked, but their disposable lifecycle and guarded live switch are
not yet approved. Until those gates pass and a controller is activated,
changing the user option evaluates a different Home profile but cannot change
what the host boots or stop factory desktop services. See the
[candidate record](2026-09-05-desktop-controller-candidates.md).

## Mode behavior

| Mode | Graphical boot/session | Desktop services and portals | Armen graphical overlay | Recovery/access |
| --- | --- | --- | --- | --- |
| `headless` | Boot to `multi-user.target`; GDM and graphical sessions inactive | Desktop portals, desktop-specific user services, and graphical autostarts inactive | Not linked into the active Home Manager profile | `tailscaled` remains enabled; factory desktop packages remain on disk |
| `gnome` | Boot graphically through factory GDM into Ubuntu GNOME | Use the factory GNOME session and its matching portal stack | Active after its own approval | Normal local desktop; Tailscale remains independent |
| `hyprland` | Boot graphically through GDM; select the pinned Nix Hyprland session | Use only the reviewed Hyprland/GTK portal combination | Active after its own approval | Factory GNOME session remains available locally as fallback |
| `kde` | Boot graphically; initially reuse GDM unless testing proves another display manager necessary | Use only the reviewed Plasma/KDE portal combination | Active after its own approval | Factory GNOME session remains available during pilot |

Only one mode owns the default session, portal selection, and graphical
autostarts at a time. Ghostty is the shared terminal in `gnome`, `hyprland`,
and `kde`; it is absent from the active `headless` profile. Installed desktop
packages may coexist on disk; that costs disk space, not idle RAM. The selected
mode controls what runs after root integration exists.

The exported pilot Home profile is now active as retained user-layer
`headless` generation one after guarded activation, real rollback, and fresh
reactivation. The actual host remains in factory GNOME: no code in the current
Home Manager layer disables GDM or changes the default target. User-profile
composition and the future host desktop-mode controller remain separate.

## What headless means

Once the root controller exists, headless is a reversible runtime state, not an
Ubuntu-desktop uninstall:

- the graphical target and display manager are inactive;
- GNOME, Hyprland, KDE, XDG portals, and graphical autostarts do not run;
- the graphical part of every user overlay is inactive;
- terminal access, networking, Nix, approved compute workloads, and
  `tailscaled.service` remain available from `multi-user.target`;
- factory GNOME packages stay installed so `gnome` can be restored without
  reconstructing the vendor OS.

Some workloads, especially Isaac, may have their own validated headless render
mode. That is a workload setting and does not silently change the host desktop
mode.

## Why XDG is not in the minimal base

`xdg.enable` in the locked Home Manager version manages the XDG base-directory
environment variables such as `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and
`XDG_STATE_HOME`. It is not itself a desktop daemon and does not materially eat
RAM. We keep it out of the small CLI base because enabling it makes Home
Manager take ownership of environment behavior before a profile needs that
ownership.

The XDG features that matter to the package graph or desktop behavior are
separate:

- `xdg.mime.enable` defaults to true on Linux in Home Manager. It adds
  `shared-mime-info`, two directory-sentinel derivations, and profile-build
  commands that regenerate the shared MIME and desktop databases. It does not
  choose default applications or run a persistent daemon.
- `xdg.mimeApps.enable` writes a read-only `mimeapps.list` and therefore takes
  ownership of default applications and file associations.
- `xdg.userDirs.enable` takes ownership of user-directory definitions.
- `xdg.portal.enable` adds portal packages, configuration, environment, and
  user services for file pickers, opening URLs, screenshots, screen sharing,
  and secrets.

The implemented policy therefore sets both `xdg.enable` and `xdg.mime.enable`
false in `headless`, and true in graphical profiles. It leaves
`xdg.mimeApps.enable`, `xdg.userDirs.enable`, and `xdg.portal.enable` false
until a specific role owns them. This is why headless evaluates to only the
three selected base tools plus Home Manager's intrinsic session-variable
package. Home Manager's user-systemd layer is disabled in this profile, so even
its otherwise generic `tray.target` is absent. Graphical profiles explicitly
show the additional MIME and user-systemd machinery in the manifest.

Hyprland's Home Manager module normally enables its portal implicitly. This
repository sets its `portalPackage` to `null`; the independent
`dgx.desktop.hyprland.portal.enable` option is the only way to add the reviewed
Hyprland/GTK portal graph.

## Switching contract

A future switch command must:

1. show the current and proposed mode;
2. show the root units, session files, portals, packages, and user profiles that
   change;
3. verify the target closure and ARM64 build before host mutation;
4. preserve Tailscale and an independent recovery path;
5. retain factory GNOME and the previous Nix generation;
6. require explicit activation approval;
7. validate the new login/session or headless boot;
8. expose one documented rollback command.

Switching into headless can terminate local GUI sessions. Switching display
manager or portal state can break screen sharing, file pickers, and Electron
apps. These effects must be stated before activation; a repository build does
not authorize the switch.

## Implementation hold points

- Pass the root-assisted disposable `headless -> gnome -> headless` lifecycle
  without changing the live host.
- Build the guarded live switch/rollback operator around the two candidate
  targets without introducing contradictory booleans.
- Keep host-level systemd/GDM ownership separate from Home Manager.
- Review Ghostty's measured graphical closure before building it, then validate
  it under factory GNOME and each approved Wayland mode.
- Review and build the Hyprland portal independently from Hyprland.
- Test `headless -> gnome -> hyprland -> gnome -> headless` on `sparkle-01`
  before adding KDE or rolling out to another Spark.
- Add KDE only after its package, portal, GDM/session, closure, and rollback are
  reviewed independently.
