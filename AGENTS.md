# Sparkwerx: agent instructions

Read [docs/agent-guide.md](docs/agent-guide.md) for task routing and
[docs/status.md](docs/status.md) for the latest recorded checkpoint.
Inspect the actual host before treating that checkpoint as current.

## Scope and workflow

- Use [`dgx-spark-ops`](.agents/skills/dgx-spark-ops/SKILL.md) for this fleet's
  Nix, DGX, Tailscale, desktop, update, workload, and recovery work.
- An audit, explanation, or plan is read-only. An implementation request
  authorizes its normal repository work and relevant tests, not unrelated
  deployment, service changes, account changes, cleanup, or reboot.
- Continue approved work without milestone-by-milestone permission rituals.
  Stop for a real missing decision, failed safety check, unavailable privilege,
  or a change outside the requested scope. Prefer tested operator scripts to
  long copy/paste sequences.
- Read [decisions](docs/decision-register.md) before changing selections or
  ownership and the [software manifest](docs/software-manifest.md) before
  realizing new packages or workloads. Selected does not mean installed.
- Don't rename the checkout, `dgx-*` commands, or `dgx-setup` state paths
  as a branding change. Snapshot paths depend on them.

## Front doors

| Task | Entry point |
| --- | --- |
| Read-only declaration/host comparison | `./scripts/dgx-setup plan [HOSTNAME]` |
| Initial setup of a declared new host | `./scripts/dgx-setup converge [HOSTNAME]` |
| Nix-only bootstrap/adoption | `./scripts/dgx-setup bootstrap [HOSTNAME]` |
| Retained pilot configuration application | `./scripts/dgx-setup apply [HOSTNAME]` |
| User profile | `./scripts/dgx-home`; later updates use `update-headless` |
| Fresh-host root lifecycle | `./scripts/dgx-fleet-bootstrap` |
| Historical pilot access/desktop status | `./scripts/dgx-tailscale status`, `./scripts/dgx-desktop status` |
| Optional remote-desktop preparation | `./scripts/dgx-remote-desktop plan`, `./scripts/dgx-remote-desktop check` |

Only `plan` and `status` are inspection routes. Do not invent subcommands;
check the implementation and [operations guide](docs/operations.md).

The separate remote-desktop `check` command is read-only too. Read
[remote desktop](docs/remote-desktop.md) before remote graphics work. The chosen
target is Sunshine/Moonlight over Tailscale, not RDP as the primary experience.
Its current artifacts are preparation only; no activation operator exists, and
the selection must stay dormant while headless. Do not treat network-policy
tests as GPU/capture or end-to-end streaming proof.
`scripts/test-remote-desktop-graphics.sh` runs synthetic hardware checks as the
normal user, without a compositor or listener. Its GPU evidence is separate
from the virtual-display helper's fake-session and config-parser tests. Real
Hyprland DRM/GBM and Grim readback now have separate hardware evidence;
Sunshine's changing-frame capture remains integration work.
`scripts/test-remote-desktop-session.sh` is the separately authorized temporary
GPU/capture diagnostic for the current pilot. Read its
[contract](docs/remote-desktop.md#temporary-capture-test-on-the-pilot) first.
It starts real Hyprland briefly inside a private transient service, not through
the root desktop controller. Its 150-second deadline and host postflight must
remain intact. The [4k120-preset hardware run passed](remote-desktop/validation/2026-09-06-temporary-capture-host.md);
that means configured 120 Hz and verified colors, not measured 120 FPS streaming.
`scripts/test-remote-desktop-sunshine.sh` selects a separate diagnostic bundle
that also starts Sunshine under the same isolation. Read its
[startup-test contract](docs/remote-desktop.md#temporary-sunshine-startup-test).
Sunshine's startup probe encodes dummy images: its final encoder messages are
not proof of changing-frame capture, a working server, or Moonlight streaming.
Keep TCP/UDP and input denied; don't turn this probe into a deployment path.
Use `scripts/test-remote-desktop-session.sh check-kms` before retrying capture. The pilot has
NVIDIA's `nvidia-drm-options-modeset0` package; don't remove its override or
reload GPU modules as an incidental fix. KMS changes require a separate host
configuration and boot plan. The test rejects loaded `modeset=N` before launch.
That preparation is now selected: read [the KMS plan](docs/nvidia-kms.md).
`scripts/dgx-kms plan`, `check`, and `status` inspect only. Its optional
`arm --console-ready` stages a one-boot entry; `cancel` revokes that entry and
selection. Both are host changes, never reboot commands. Read the KMS plan
before using them; independent keyboard/display/power recovery is required.
The trial consumes and reads back a GRUB marker before adding the KMS argument.
Failed marker I/O uses the original arguments. The pilot's
[first KMS boot](root/graphics/validation/2026-09-06-kms-test-boot.md) consumed
the marker and loaded KMS; failure/repeated-selection cases remain offline tests.
The trial entry/snapshot/code remain, with no confirmation timer. Do not re-arm,
cancel, or reboot as incidental cleanup; inspect current status first.
Preserve factory GNOME/Xorg as the alternate to local/remote Hyprland. A
recognized GRUB header is not proof of boot-time environment write capability.

Fresh-host convergence is headless-only, requires the explicit supported user
mapping, never reboots, and uses two root generations. It passed the full
integration gate at `cc1069cbce87974a545095b3361b78837d618437`; functional
changes require that gate again. Read
[the lifecycle contract](docs/fresh-host-convergence.md) before deploying.

## Preserve these decisions

- NVIDIA owns DGX OS, firmware, kernel, driver, system CUDA, Docker, Container
  Toolkit, and factory packages. Do not replace them through Nix or generic installers.
- Permanent fleet base: exactly `ncdu`, `lazydocker`, `devbox`.
  Repository tools stay in dev shells unless separately selected.
- Ghostty is shared-graphical, never headless. XDG/MIME/portals and Home Manager
  CLI/manpages remain role-specific; headless emits no Home Manager user units.
- Armen's overlay is explicit. Keep his Codex package, disabled startup updater,
  and accepted permissive defaults; preserve mutable auth, plugins, MCP,
  preferences, trust, and history. Do not extend that policy to unrelated users.
- Chromium, Zed, and LM Studio are built candidates, not active profiles.
  Keep their sandbox/GPU/portal gates. Never bypass Chromium's sandbox or
  globally relax AppArmor. Preserve Zed's updater-disable wrapper and LM
  Studio's byte-identical Deno CLI; its Electron fallback remains unresolved.
- No global `allowUnfree = true`; the exact current exception is `lmstudio`.
  No VS Code, Google Chrome, NIM, AI Enterprise, 1Password desktop, or LM Link
  unless the user changes the recorded selection.
- `lazydocker` does not grant Docker access. Devbox does not own Nix upgrades.
  Keep the installer pin separate from the runtime; diagnose downgrade candidates.
- Keep `nixpkgs-root` and System Manager separate from ordinary package updates.
  Preserve private Nix 2.35.2, rejection of stale Nix/real `userborn`, the
  exact-version empty-tmpfiles patch, and its unmanaged-rule regression test.

## Current pilot and recovery

Recorded `sparkle-01` state: generation five, headless, boot-linked, with
Nix-owned Tailscale inherited from generation four. All five numbered
generations and direct pilot roots are retained. The latest record has no
armed recovery or transition guard. Read
[the current evidence](root/desktop/validation/2026-09-05-confirmed-headless-integration.md).

- Do not replay old canary, registration, generation-switch, boot-persistence,
  or restoration helpers. Their snapshots/preconditions are spent.
- Read [the root runbook](root/system-manager/README.md) before root changes,
  and the skill's [Tailscale reference](.agents/skills/dgx-spark-ops/references/tailscale.md)
  before access changes. A Tailscale restart can end this session.
- Preserve Tailscale identity, SSH, and multi-user startup. Keep apt fallback.
  Preserve factory GDM; headless stops the Dashboard GUI, not Dashboard Admin.
- Never bypass a guard by deleting timers, roots, links, or state. Check the
  operator's current status and use its exact recovery path.
- A healthy idle Nix daemon can sit behind an active listening socket.
  Diagnose `NeedDaemonReload`; don't replay a spent Snap-specific helper.
- Preserve root test wrappers' `--store local`, temporary feature flags, and
  `NIX_USER_CONF_FILES=/dev/null`. Don't persist those flags just to run a test.
  A cosmetic warning is not a test failure; the exit status and exact output are.
- Builds and container tests do not authorize live activation or reboot.
  Reboots and retiring fallback/generations need explicit scope and a current plan.

## Privacy and documentation

Never commit or print credentials, raw Tailscale status/preferences, node IDs,
tailnet addresses, cookies, or private inventory. Keep root snapshots under
`inventory/<host>/raw/`, user snapshots under `inventory/<host>/private/`,
and models/application data outside Git and the Nix store.
The KMS trial operator instead keeps its private boot snapshot under
`/var/lib/dgx-setup/kms-trial`, with canceled trials in `kms-trial-history`;
these are recovery material, not files to copy into the repository.

Use plain language, distinguish recorded evidence from live observation, and
label commands by their effects. Keep dated records intact except for clear
wording corrections; do not rewrite old test results as new passes.
Run `python3 scripts/check-docs.py` for documentation changes.

## Development and releases

Read [development](docs/development.md) for the shared Nix workspace, pre-commit,
CI, and Release Please. Run `./scripts/dev check` before a PR. No Prettier.
Use a Conventional Commit PR title; squash merging supplies the release history.
Do not merge a release PR merely to test the automation: merging it publishes.

Keep `nixpkgs-devtools` updates separate from installed package/root pins.
Do not mass-format historical recovery scripts; their lint exceptions are
exact-file hashes in `dev/legacy-checks.json`. Changed files must pass and shed
their exceptions. CI never authorizes activation, and the DGX is not a CI runner.
