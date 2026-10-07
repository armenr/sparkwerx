# Factory GNOME workstation: what changed and why

This branch adapts Sparkwerx for a second DGX Spark whose owner wants to keep
the factory desktop and existing access setup, while making additional tools
easy to install, reproduce, update, and roll back. Its starting point is
upstream commit `fd5cf97`. The declared host is `spark-9667`, user `deadspark`,
ARM64 Ubuntu/DGX OS with NVIDIA GB10.

The practical goal is to avoid package experiments forcing an OS reinstall or
factory reset. Isolation and tested recovery reduce that risk; package
generations are not full-system snapshots or backups of application data.

## Ownership decisions

| Layer | Owner and behavior on this workstation |
| --- | --- |
| DGX OS, kernel, firmware, driver, system CUDA | NVIDIA/factory package lifecycle |
| Docker, Container Toolkit, Dashboard | Existing installation; no replacement |
| GNOME/GDM and desktop applications | Kept installed and running |
| Tailscale VPN and OpenSSH | Existing native services; existing configuration retained |
| Optional Tailscale SSH feature | Off, independently of the running VPN |
| Nix daemon and runtime | Guarded official installer/runtime 2.35.2 |
| Additional user tools | Dedicated Nix package profile managed by `spark` |
| Existing Kitty/Zsh configuration and APT tools | Existing files/packages; not taken over by Home Manager |
| AI models and workloads | Outside this change; no model containers or listening services added |

The original pilot's headless convergence, root generations, managed Tailscale,
and personal overlay remain separate. The shared fleet base is still exactly
`ncdu`, `lazydocker`, and `devbox`. Management helpers are this workstation's
explicit selections, not new mandatory fleet tools.

## Package architecture

[`hosts.json`](hosts.json) declares the account, architecture, factory desktop,
and extra package attributes. [`profiles.nix`](profiles.nix) composes the
existing base through Home Manager but exposes only its package output.

The operator **does not execute Home Manager activation**. It does not replace
dotfiles, create Home Manager user services, or use the ordinary
`~/.nix-profile`. Instead, it switches this dedicated profile:

```text
~/.local/state/sparkwerx/
  profile             -> active package generation
  profile-N-link      -> retained generation / Nix GC root
  candidate           -> last manual build
  pending.json         activation recovery journal, when needed
```

This boundary allows user-tool changes without routing the host through System
Manager or the headless desktop transition. A conditional line in the existing
`~/.zshrc.local` puts the active package binaries on PATH. The operator backs
up that file before the first change and preserves unrelated content.

The new `nixpkgs-workstation` flake input separates ordinary package updates
from the existing pilot, root, app, and development-tool pins. `spark upgrade`
updates only that input. Packages sourced elsewhere, such as the separately
pinned Devbox adapter, keep their independent source/update lifecycle.

## A guided terminal manager

[`scripts/dgx-workstation`](../scripts/dgx-workstation), exposed as `spark`,
provides a small curses menu and uses the selected `nh` and `fzf` packages for
catalog search and multi-selection. The interaction follows familiar package
helper conventions:

1. Search a package name or description.
2. Filter the results, select one or more with Tab, and press Enter.
3. Build a candidate while the current tools remain available.
4. Review the actual direct-package additions, removals, and versions.
5. Confirm to save a local Git revision and activate the built candidate.

The main menu also offers removal, package updates, searchable generation
history, and status. Advanced retains the individual edit/build/save/apply
steps and recovery controls. Arrow keys or j/k move focus; Esc/q goes back.
Long-running commands show their output rather than hiding progress.

Search queries the selected stable channel's live catalog and filters using
the package's ARM64 platform list. That catalog can be newer than the locked
build, so the final review uses the built manifest. Search also reports an
exact command already available on the machine. For example, Ubuntu already
provided `nmtui`; the owner subsequently selected `networkmanager` in the user
profile as well. This package selection does not install a system service.

The launcher remains attached to the checkout because it needs the declaration
and flake. Before Nix setup, `~/.local/bin/spark` can be a symlink to the
script; after setup, the profile supplies a launcher using pinned Python.
Copying the script by itself into a bin directory would lose that context.

## Recovery behavior

- Guided changes require a clean checkout and hold the profile lock through
  build, review, and activation. A second operation is refused.
- Cancellation or a failed build restores the flow's own declaration/pin
  edits. Intervening edits are preserved for inspection.
- Activation requires a saved configuration and checks that the candidate
  matches its evaluated output and declared host/account.
- The operator records the old/new outputs before switching. If executable
  postflight fails, it restores the previous profile immediately.
- After a killed activation, `spark recover` uses the retained journal.
  A killed build/review may leave working-tree edits for review in Advanced.
- `spark generations` and `spark rollback NUMBER` restore retained packages.
  Rollback does not rewrite the saved desired selection/pin.
- `spark disable` removes the active profile link while retaining history.
  There is no automatic generation deletion or garbage collection in the UI.

Nix bootstrap has its own receipt-driven rollback and timed recovery. User
package rollback does not uninstall Nix or restore the entire OS. User data,
credentials, models, and application databases remain outside these package
generations and need their own backup policy.

## First-boot issues resolved during setup

### Keep the installed desktop applications

NVIDIA's one-time `nvidia-remove-gnome-software-once.service` had failed because
APT was locked. Its planned cleanup purged GNOME Software and Contacts and
performed autoremove, which also proposed removing older firmware packages.
The owner explicitly chose to keep the desktop applications. They ran a
reviewed helper in their own sudo terminal that recorded the old unit state,
disabled this one removal job, and cleared its stale failure. No packages were
removed. This was an explicit host maintenance decision, not a generic step
silently embedded in package setup.

### Isolate the installer update

The original repository pinned installer 2.35.1; the current-release preflight
required 2.35.2. Rather than rewrite the pilot's tested inputs, the workstation
gets a separate [bootstrap input root](bootstrap/README.md). It reuses the
unchanged updater and receipt rollback helpers and carries a dedicated copy
of the bootstrap operator. The original pilot installer pin stays unchanged.

The installer may create `/nix`, build accounts, daemon/socket units, Nix
configuration, and standard shell hooks. The workstation's user-profile
activation is a later, unprivileged step. Setup preserves the original
freshness, clean-Git, plan, recovery-timer, service, and adoption checks.

### Distinguish Tailscale VPN from Tailscale SSH

The original preflight rejected a healthy running VPN because its optional SSH
server was disabled. The workstation explicitly selects `sshDesired=false`.
Its bootstrap accepts that healthy state while continuing to reject offline
or unreadable state. It verifies exact before/after VPN/SSH settings, daemon
identity, PID, unit, and start time. It neither changes Tailscale preferences
nor restarts networking. The dedicated bootstrap differs from the original
in this policy check, plus shell formatting; keep that copy in view during
future maintenance.

### Terminal definitions across APT and Nix

The Nix Python launcher initially could not find Ubuntu's Kitty terminal
definition, causing `curses.setupterm` to fail. The manager now includes user
and Ubuntu terminfo directories while preserving `TERM` and existing
overrides. Kitty and Ghostty SSH PTYs were exercised. Portable Kitty/Zsh
references live under [`terminal`](terminal); they document the earlier manual
terminal setup and are not a complete dotfile installer or a secret export.

## Validation and current limits

The [validation record](VALIDATION.md) distinguishes unit tests, disposable
container tests, and live observations. It includes native ARM64 package
builds, real Nix generation/recovery checks, and a fresh Ubuntu/systemd
installer failure/receipt rollback/retry/adoption test. The healthy-VPN,
SSH-off case and offline rejection were both covered before actual setup.

On the real Spark, setup completed with the factory desktop, GPU, Docker,
OpenSSH, and Tailscale still healthy. The owner's guided package install and
subsequent pin upgrade created retained user generations 2 and 3.

This is currently a declared-host implementation, not a multi-user onboarding
wizard. The launcher expects `~/Development/DGX-setup`, ARM64, the declared
hostname, UID, account, and home directory. The bootstrap's existing logical
`armen` user key is only a compatibility mapping to `deadspark`; no personal
overlay is enabled. Hardware reboot behavior, arbitrary graphical packages,
and full-system recovery are not established by these user-package tests.

For daily use and exact commands, continue with the
[workstation README](README.md). For changes to the implementation, follow
[repository development](../docs/development.md).

The later [maintainer handoff](REVIEW.md) covers pending-selection repair,
model workload controls, the optional GPUStack trial, test-container cleanup,
and the October 7 publication review. Use it for the latest deployment
distinctions; the earlier setup results above remain historical evidence.
