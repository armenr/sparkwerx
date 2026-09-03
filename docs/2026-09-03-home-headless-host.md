# First headless Home activation host result

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: passed, real rollback passed, exact reactivation retained

## Current state

The exact Home Manager generation
`/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation` is
selected, rooted, active, and retained as generation one. Its installed user
environment is
`/nix/store/6cdhd5n7m5agcrnr8pg6jxkpsadmfpba-user-environment`.

Current visible commands are:

- `~/.local/bin/codex`: Nix-managed Codex CLI 0.153.0;
- `~/.nix-profile/bin/ncdu`: 2.9.2;
- `~/.nix-profile/bin/lazydocker`: 0.25.2; and
- `~/.nix-profile/bin/devbox`: 0.18.0.

The active profile contains no Home Manager CLI, Chromium, Ghostty, Hyprland,
LM Studio, or Zed. Its exact home files are `~/.local/bin/codex` plus inert
`.cache/.keep` and `.local/state/.keep` links. The headless-forbidden
`~/.config/environment.d/10-home-manager.conf` and
`~/.config/systemd/user/tray.target` paths are absent.

## Attempts and rollback proof

The first live invocation stopped before snapshot creation or activation when
the user process correctly could not write under the root-owned `raw/`
inventory tree. Commit `741025f` moved Home snapshots to the distinct ignored,
user-owned `private/` tree and made snapshot errors immediately fatal.

The next transaction created private snapshot `20260903T120400Z`, armed its
ten-minute timer before mutation, activated exact generation one, passed two
postflights, and automatically disarmed the timer. The real snapshot rollback
was then invoked deliberately. It removed only the exact Home profile/root and
three links, restored the manual Codex 0.152.0 launcher, preserved the config,
and returned a passing absent-profile status.

A fresh transaction then created snapshot `20260903T120519Z`, repeated the
same activation and two postflights, and retained generation one. Independent
status afterward resolved Codex to 0.153.0 and all three base commands to the
Home user profile. The transient timer reports `LoadState=not-found` and
`ActiveState=inactive`; no rollback is armed. Both private snapshots remain as
local rollback/evidence inputs and are excluded from Git.

## Preserved boundaries

Both activation postflights and the real rollback verified:

- exact System Manager generation three stayed registered, live, rooted, and
  boot-linked;
- Tailscale stayed running/online with Tailscale SSH enabled;
- GDM, Docker, both DGX Dashboard services, NVIDIA persistence, and Tailscale
  kept their original process identities and unit fragments;
- account group membership did not change, so lazydocker gained no Docker
  daemon permission;
- the apt Tailscale package/service remained the live owner;
- the factory GNOME session and host desktop mode did not change; and
- no sudo action, reboot, `/etc` mutation, user service, portal, or graphical
  application activation occurred.

The retained standalone Codex release tree is intentionally not deleted yet.
It remains a rollback input while the new launcher is exercised, even though
it no longer wins command resolution.
