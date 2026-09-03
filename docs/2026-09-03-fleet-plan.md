# Declarative fleet plan evidence — 2026-09-03

## Outcome

The repository now has a single machine-readable selection surface and a
non-applying front door:

- `fleet/hosts.json` declares `sparkle-01`, its exact fleet base, the
  `armen -> n0b0dy` mapping, user overlays, desktop mode, optional access role,
  and separately selected/enabled workload state;
- `bootstrap/nix/source.json` declares the exact official ARM64 Nix installer,
  Linux/systemd planner inputs, and separately desired runtime;
- `flake.nix` derives the exported Home configuration from that declaration;
- `scripts/dgx-setup plan [HOSTNAME]` validates and renders it without applying
  anything; and
- `scripts/update-nix-installer.sh` checks or advances only the checksum-pinned
  installer declaration. It never runs the installer.

## Current pilot selection

| Choice | Declared state |
| --- | --- |
| System | `aarch64-linux` |
| Ring | `pilot` |
| Fleet base | enabled; exactly `ncdu`, `lazydocker`, `devbox` |
| Armen overlay | enabled; Codex and graphical candidates selected |
| Codex defaults | maximally relaxed for Armen in every desktop mode |
| Desktop composition | `headless`; Hyprland portal disabled |
| Host desktop controller | not implemented; factory GNOME remains untouched |
| Tailscale | selected; SSH desired; ownership `migration-pending-apt` |
| Isaac/Omniverse | selected, not enabled |
| LM Studio daemon | not selected, not enabled |

Selection does not imply activation. In particular, the graphical candidates,
desktop controller, Tailscale migration, and Isaac workload remain behind their
independent gates.

## Bootstrap evidence

The source declaration records official `NixOS/nix-installer` 2.35.1,
`nix-installer-aarch64-linux`, 32,536,352 bytes, and SHA-256
`7e6e2f753144d7f19b16a9fce4b354cb0f46d1d47e6908bfb9186c89e0e0e649`.
The update checker queried the official latest GitHub release, downloaded that
exact asset, matched its published digest and size, executed only `--version`,
and reported the pin current. The already installed `/nix/nix-installer`
matches the declaration byte-for-byte, so the pilot plan classifies it for
adoption rather than replacement.

The desired running Nix remains separately pinned at 2.35.2 under `root/nix/`.
The provisioning binary and runtime are deliberately not conflated.

## Safety and validation

The planner intentionally does not provide `apply`. It can use Nix evaluation,
which may fetch missing locked flake sources, but it does not build or install
packages, mutate profiles, activate configuration, restart services, enroll
Tailscale, switch desktops, or reboot.

`scripts/test-dgx-setup-plan.sh` records the Home/profile links and protected
service PID/fragment/start-time tuples before planning, then verifies they are
identical afterward. It also verifies that an unknown host fails, the exact
bootstrap is recognized, selected role gates are shown, the live Home candidate
is current, and no DGX serial field is emitted.

The remaining implementation boundary is explicit: executable Nix
install/adoption and uninstall/rollback, persistent Nix feature policy, unified
guarded apply, Tailscale ownership migration, and host desktop control.
