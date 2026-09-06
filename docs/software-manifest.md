# Pre-install software manifest

This is the lightweight SBOM and approval gate for software above the NVIDIA
factory substrate. Its job is practical: show what a profile would add, why it
is wanted, where it comes from, how large and active it is, and how to undo it
before anything is installed.

This is not a license registry. Record free/unfree status only when it affects
Nix evaluation, redistribution, or the installation method.

Read [current status](status.md) for what's active now and
[configuration](configuration.md) for how selections are made. Versions and
closure sizes below are dated measurements, not a claim to track today's
upstream automatically. Historical root milestones describe the state at each
milestone; the retained pilot is now generation five with Nix-owned Tailscale
and headless mode.

## Optional remote desktop

Sunshine/Moonlight over Tailscale is selected for the pilot and defaults off for
other consumers. Sunshine uses the locked `nixpkgs-apps` package (GPL-3.0-only),
including its pinned upstream FFmpeg build dependency. It adds no global unfree
exception, Moonlight client, or replacement NVIDIA driver. The package and
network/configuration templates are preparation artifacts, not an activated
Home/root role. Selection in `headless` installs and starts nothing. See
[remote desktop](remote-desktop.md) for the remaining capture, graphics/input,
credential, and service-lifecycle work.

The realized ARM64 Sunshine 2026.516.143833 candidate has a 793.6 MiB complete
Nix closure (much of it shared with other candidates); its own output is
22.8 MiB. Realization only populated the Nix store, not the active profile.

Encoder diagnostics use the locked apps lane's `ffmpeg-headless` 9.0.1 binary
output as a temporary test tool, not a profile package. Its libraries are
already in the candidate closure; the binary output adds about 315 KiB of
downloads / 862 KiB unpacked on the pilot. Tests use generated video, a private
temporary directory, and the existing factory CUDA/NVENC driver libraries.
An accompanying small EGL pbuffer probe uses the locked root lane's free
GLVND development library and compiler; it renders two private test colors
through the factory NVIDIA EGL driver without opening a display or compositor.
They install no CUDA toolkit, driver, service, listener, or permissions. A
successful FFmpeg encode is not proof of Sunshine capture or streaming.

## Status of this snapshot

Package/version evidence date: **2026-09-03 online audit**

Root-canary operational evidence updated: **2026-09-03**

Manual-install provenance inventory updated: **2026-09-02**

The independently refreshable user/package pins were updated and rechecked
against official sources on 2026-09-03. Stable Nixpkgs is locked at current
`nixos-26.05` head `a3116115851d...`; the apps lane is locked at current
`nixpkgs-unstable` head `9387b3fcc0c2...`; Home Manager is locked at current
`release-26.05` head `65258d5c65a2...`. The live root lane intentionally stays
at its separately proven `nixpkgs-root` revision `a9e6d84f9c2f...`. The
guarded update proved every root candidate, recovery bundle, policy, and test
derivation stayed byte-for-byte exact before building all user profiles and
selected package outputs with `--no-link`. Devbox 0.18.0, Tailscale 1.102.3
plus its inert unit tree, Codex CLI 0.153.0, Chromium 152.0.7977.75, Zed
1.18.0, and LM Studio 0.4.23-1 were built and inspected. All three graphical
applications remain candidate-only and are absent from every Home Manager
profile. The exact 52-path / 696.8 MiB headless Home generation was then
activated, rolled back to the byte-exact pre-Home state, and freshly activated
again through its guarded transaction. It is retained as generation one with
no user-systemd units; see the
[host result](2026-09-03-home-headless-host.md). The
patched System Manager 1.1.0 inert
root canary and closure policy were also built and inspected without host
activation. The first disposable-container activation failed closed on upstream
global tmpfiles behavior; after the exact-version patch, the exact current
activation/deactivation derivation passed and clean postflight proved the host
untouched. The first later live canary activated within its exact boundary and
then rolled back cleanly on its timed guard after a verifier false positive. A
second live canary passed corrected automatic postflight and rolled back on the
same guard after the exact human retention confirmation was accidentally not
entered. A later reboot audit confirmed the canary surface absent, exact empty
state, no registration, retained exact candidate, and healthy protected
services. A subsequent factory Firefox Snap refresh temporarily set a pending
systemd daemon reload. Armen acknowledged the generated unit graph without a
protected-service restart, and the full preflight passed again. A third live
canary then passed the complete guarded flow and was retained after independent
local-console confirmation. System Manager is active only on the exact
five-path/three-service surface and owns no Tailscale or desktop state. At that
activation milestone it remained unregistered and not boot-linked. The exact
two-generation disposable registration lifecycle test subsequently passed with
clean independent host postflight; it performed no host registration. The
separate guarded
first-generation transaction, private snapshot, timed rollback wrapper, and
failure-injection container test were then completed through the exact
disposable PASS with clean host postflight. The first live wrapper invocation
then failed closed during protected-service preflight, before its rollback
timer or registration transaction, because its parser associated a property
with the next systemd unit. The parser is corrected and regression tested; the
old snapshot is retired. A second attempt refused a snapshot 407 seconds beyond
the hard age limit and again changed nothing. Attempt 3 then retained exact
generation one using corrected commit `0f03d01` and fresh snapshot
`20260901T201613Z` after an armed registration-only rollback, repeated
postflight, and independent local-console confirmation. Current state is
`ACTIVE_REGISTERED_RETAINED` at that milestone: generation one, its upstream
extra root, and its pilot root resolved to the exact candidate. No activation,
boot linkage, service restart, Tailscale replacement, or desktop switch
occurred.
The distinct guarded generation-switch transaction then passed all eleven
failure-injection, exact-switch, rollback, and cleanup subtests inside its
disposable container. Its valid output and clean independent host postflight
prove generation one remained registered/live and the host generation-two root
remained absent. The resulting live wrapper, private snapshot helper, and
whole-record systemd parser were then policy-pinned. Armen created fresh
snapshot `20260902T083437Z`, verified the local console, and authorized that
exact snapshot. The wrapper retained, registered, selected, and activated
generation two, repeated postflight, and disarmed rollback before its service
ran. Current state is `ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`: generation
two is selected, upstream-rooted, directly retained, and live; generation one
and its original pilot root remain retained. No boot linkage, protected-service
change, Tailscale replacement, or desktop switch occurred.
The exact generation-two to generation-three boot-persistence transaction then
passed all 13 failure-injection, apply/rollback, two-restart, and cleanup
subtests inside a disposable container. Its valid output and independent host
postflight prove the real host remained exact live generation two, with the
generation-three pilot root and boot link absent at that test milestone. The
separate guarded live activation then used explicitly authorized fresh snapshot
`20260902T110421Z`. It retained, registered, selected, and activated exact
generation three, passed postflight twice, received local-console confirmation,
and disarmed rollback before its service ran. The distinct
13-subtest/two-restart persistent recovery lifecycle then passed inside a
disposable container. Its separately authorized real-host run survived the
first reboot and correctly restored exact generation two when the ten-minute
confirmation deadline expired. Snapshot-bound rollback verification and exact
cleanup passed. The first no-reboot restoration reached healthy generation
three, but a typo in the old retention phrase left the exact timer armed; it
safely restored generation two. The corrected retry used one pre-mutation
Enter, completed two successful postflights, automatically disarmed rollback,
and restored current state
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`. All three numbered
generations and direct pilot roots remain, generation three is selected/
upstream-rooted/live, its one declarative boot edge exists, and the recovery
surface is absent. Updated hash-pinned helpers accept Nix's normal socket-idle
postboot state and expose a short operator route but no reboot action.
That was the exact pre-migration authority. The later guarded Tailscale
transaction added generation four, preserved generations one through three as
rollback anchors, survived its real reboot and fresh SSH reconnect, and is now
the inherited access boundary. The corrected guarded desktop transaction then
added generation five and retained headless mode without rebooting. All five
generations and direct roots remain; generation five is selected, upstream-
rooted, live, and boot-persistent with Nix-managed Tailscale unchanged.

Hyprland and its portal had already been build-tested earlier in the pilot.
Their existing local store closures were measured read-only; they were not
rebuilt in Phase 1.

| Layer | Item | Intent | Current evidence | Gate before build/install |
| --- | --- | --- | --- | --- |
| Fleet base | Exact role | REQUIRED; ACTIVE | Exactly `ncdu`, `lazydocker`, and `devbox` are active through Home generation one; old `fd`, `jq`, and `ripgrep` remain dev-shell-only | Update only through `scripts/dgx-home update-headless`; its disposable rollback passed |
| Fleet base | ncdu | CURRENT; ACTIVE | Stable pin `ncdu` 2.9.2 is current, free, ARM64-available, and visible from the Nix user profile | Keep in the exact fleet base unless deliberately removed |
| Fleet base | lazydocker | CURRENT; ACTIVE | Stable pin `lazydocker` 0.25.2 is current and active; account groups/socket ACLs are unchanged, so it grants no Docker daemon permission | Do not add Docker group membership, socket ACLs, a service, or autostart |
| Fleet base | Devbox | CURRENT; NIX-MANAGED ACTIVE | Exact adapter pins current upstream 0.18.0 source and Go vendor hashes because both Nixpkgs branches still expose 0.17.5. The active ARM64 binary resolves through `~/.nix-profile`; its 8-path runtime closure is 65.8 MiB NAR. The old `/usr/local/bin/devbox` copy remains on disk but no longer wins normal command resolution | Never invoke Devbox's bootstrap installer or let Devbox replace/update Nix; retain the adapter until stock catches up and treat removal of the old copy as separate cleanup |
| Dev shell | Git, jq, nixfmt-tree, ripgrep | Repository work only | Direct versions are Git 2.55.0 and ripgrep 15.2.0 from apps, jq 1.8.2 and nixfmt-tree 2.6.0 from stable; manifest-only, never permanent | Keep out of the user profile unless separately selected |
| Fleet operator | `scripts/dgx-setup` | COMPLETE FOR RETAINED DECLARED STATE; FRESH-HOST CONVERGENCE VALIDATED | From clean commit `cc1069cbce87974a545095b3361b78837d618437`, the complete 2026-09-06 gate passed exact Home rollback, clean Nix bootstrap/rollback/adoption, optional Tailscale, factory generation one, three container reboots, headless generation two, persistent rollback, and `sparkle-01` plan/apply/converge no-op checks. The resumable `converge` lane never reboots and recognizes the historical pilot without changing it. See [fresh-host convergence](fresh-host-convergence.md) and [exact evidence](2026-09-06-fresh-host-convergence-integration.md) | Use only on a supported ARM64 DGX after factory updates, an explicit host declaration, and plan/SBOM review. Any functional change must pass the complete gate again; later root-generation updates and enabled workloads remain separate |
| Factory desktop | Ubuntu GNOME/GDM | Recovery and reversible `gnome` host mode | Factory-owned and installed; GDM/graphical target are intentionally inactive under current headless generation five | Never replace or remove; return only through the reviewed guarded desktop operator |
| Root desktop controller | Headless/factory-GNOME targets | ACTIVE; CONFIRMED HEADLESS GENERATION FIVE | The thin controller adds no desktop package or daemon. Attempt one safely rolled back and exposed the Dashboard classification/fixture gap. The corrected transaction, three-reboot mode lifecycle, and persistent rollback lifecycle passed; the separately authorized retry selected and confirmed exact `djp7…` generation five with Tailscale identity/SSH, Dashboard Admin, Docker, and NVIDIA persistence intact. The later complete retained-state suite passed from `9883d6c`, including honest fleet `READY`/`COMPLETE` no-op convergence. Factory GDM and Dashboard GUI are inactive but installed. All five generations/roots remain; no rollback timer is armed; no reboot occurred | Use only `scripts/dgx-desktop` for status or future reviewed transitions; never activate a raw output or isolate directly. A real generation-five reboot, GNOME return, Hyprland activation, and cleanup remain separate. See the [current integration authority](../root/desktop/validation/2026-09-05-confirmed-headless-integration.md), [host result](../root/desktop/validation/2026-09-05-host-attempt-2.md), and [pre-live test evidence](../root/desktop/validation/2026-09-05-dashboard-aware-stack.md) |
| Desktop role | Hyprland | Optional `hyprland` mode | v0.56.2 is pinned and ARM64 build-tested; Home Manager profile is evaluable and inactive | Review graphics bridge, GDM entry, portal choice, and rollback |
| Desktop role | KDE Plasma | Supported future mode | Enum value exists; no package set or root integration is selected | Approve role, closure, portal, display-manager integration, and ARM64 test |
| Shared graphical role | Ghostty | SELECTED terminal for every graphical mode | Stable pin `ghostty` 1.3.1 is current, free, and ARM64-available; its large GTK/GStreamer closure is quantified below | Decide whether the roughly 1.1 GiB Ghostty closure is acceptable, then validate GTK/GPU behavior; keep out of headless |
| Armen graphical overlay | Chromium | CURRENT PIN; BUILD/POLICY PASSED; SANDBOX/ACTIVATION OPEN | Current apps pin exposes official-current `chromium` 152.0.7977.75 on ARM64/free. Its 340-path closure is about 1.7 GiB and has no service/autostart surface. Isolated launch correctly refuses both the non-setuid store helper and AppArmor-blocked user-namespace fallback; it is not in a Home profile | Review [exact evidence](2026-09-03-chromium-package.md); add and independently prove the exact graphical root sandbox role—never `--no-sandbox` or a global userns relaxation—then validate NVIDIA graphics/profile/extension behavior before activation |
| Armen graphical overlay | Zed | CURRENT PIN; BUILD/POLICY PASSED; ACTIVATION OPEN | Official stable `v1.18.0` ARM64 bundle, published digest, and tag commit are pinned directly because the locked Nixpkgs package is 1.17.2. Its 6-path closure is 485.5 MiB; isolated version smoke test created no state; no service/autostart surface exists. It is not in a Home profile | Review [exact evidence](2026-09-03-zed-package.md), then test factory-GNOME Vulkan/NVIDIA and portal/MIME behavior before wiring and activation |
| Armen graphical overlay | LM Studio desktop | CURRENT PIN; BUILD/POLICY PASSED; ACTIVATION OPEN | Official `0.4.23-1` Linux ARM64 AppImage is pinned directly because the locked apps package is 0.4.21-2. Its 9-path closure is 2.4 GiB; no service/autostart/API/model exists. The host-compatible launcher uses the vendor's no-sandbox fallback under Ubuntu's AppArmor user-namespace restriction. It is not in a Home profile | Review [exact evidence](2026-09-03-lmstudio-package.md); explicitly resolve the Electron sandbox caveat, then test factory-GNOME URL/MIME behavior and GB10 acceleration before wiring and activation |
| Armen graphical overlay | ChatGPT desktop | SELECTED; currently manual | Debian package `chatgpt` 26.818.41705 owns the current launcher; repository pin is absent | Verify official artifact/provenance, ARM64 support, update behavior, collisions, and rollback |
| Armen graphical overlay | 1Password for Firefox | SELECTED; currently manual | Existing extension `{d634138d-c276-4fc8-924b-40a0ea21d284}` is version 8.12.32.33; repository policy/pin is absent | Choose reproducible extension policy without storing account/browser state |
| Armen graphical overlay | 1Password for Chromium | SELECTED | Not yet declared | Choose reproducible extension policy without storing account/browser state |
| Access overlay | Tailscale/Tailscale SSH | OPTIONAL PER HOST; CURRENT; NIX-MANAGED ACTIVE ON `sparkle-01` | Repository pins current stable official ARM64 1.102.3; its one-path 67.7 MiB runtime contains byte-identical client/daemon binaries. Exact System Manager generation five inherits the loaded Nix-managed unit and running daemon unchanged from generation four. The guarded migration preserved identity and `RunSSH=true`, survived a deliberate disconnect plus real reboot, and was confirmed after fresh SSH reconnect; the later desktop switch preserved the same access plane. Apt 1.102.3 and its repository remain installed only as inactive fallback material | Audit/update through the pinned source and guarded role. Do not manually restart/replace the service, delete mutable identity, or remove apt fallback without a separate reviewed cleanup |
| Developer tools | Codex CLI + Armen permission policy | CURRENT; NIX-MANAGED ACTIVE | Armen's all-modes overlay pins OpenAI's official 0.153.0 ARM64 release bundle at SHA-256 `076b2b75...99be4`. The 278.2 MiB one-path closure contains `codex`, code-mode host, bundled ripgrep, sandbox helper, and package manifest. Home generation one owns the higher-precedence `~/.local/bin/codex` launcher and disables startup self-update while preserving auth/plugin/MCP/history state; real rollback and reactivation passed. The old standalone 0.152.0 tree is retained but no longer resolves | Continue auditing through `scripts/update-codex.sh`; keep the standalone tree temporarily as rollback input and remove it only through separate cleanup evidence |
| Bootstrap | Official Nix installer | CURRENT PIN; EXACT ADOPTION AND CLEAN-INSTALL LIFECYCLES PASSED; NIX-ONLY FRESH-HOST USE READY | `bootstrap/nix/source.json` pins official `NixOS/nix-installer` 2.35.1 for ARM64 Linux at 32,536,352 bytes and SHA-256 `7e6e2f75...e0e0e649`. The installed `/nix/nix-installer` matches it byte-for-byte. `scripts/update-nix-installer.sh --check` validates latest GitHub metadata/downloaded bytes. `scripts/dgx-setup bootstrap` adopts the pilot with zero mutation. Exact disposable derivation `81pb42...` passed clean install, injected post-runtime failure with receipt rollback to the clean boundary, retry at runtime 2.35.2 with persistent flakes, and second no-mutation adoption; [full evidence](2026-09-03-nix-bootstrap-lifecycle.md) includes the hash-valid output and clean host postflight | Use only `scripts/dgx-setup bootstrap` on a clean committed, declared ARM64 host; keep runtime updates separate and do not infer unified apply or optional-role authority |
| Root runtime | Nix | CURRENT; ACTIVATED/VERIFIED | Active client and daemon are 2.35.2 from the exact signed-cache path under `root/nix/`; default environment is `9lznxxcs…-user-environment`. The installer artifact and separately rooted rollback environment retain 2.35.1. Default fallback target 2.34.8 remains blocked | For each future release/host, re-run exact provenance, downgrade, profile, daemon, and rollback gates; do not garbage-collect the retained 2.35.1 environment yet |
| Root integration | System Manager | GENERATION FIVE LIVE/REGISTERED/BOOT-PERSISTENT HEADLESS; NIX-MANAGED TAILSCALE ACTIVE; ALL FIVE GENERATIONS AND DIRECT ROOTS RETAINED; RECOVERY CLEAN/UNARMED | Exact 1.1.0 pin on matching `release-26.05`; its private wrapper is verified Nix 2.35.2. The foundational canary/recovery tests, real recovery reboot, generation-three restoration, generation-four Tailscale migration/reboot, and generation-five desktop transaction all passed. `system-manager -> system-manager-5-link -> djp7…` and `system-manager-current -> djp7…`; state contains 12 paths/four services; no recovery, migration, or desktop rollback timer is armed | Preserve all five generations and direct roots while broadening ownership one reviewed role at a time. Do not reuse spent helpers, remove a generation/root, reboot, or add another managed service without its current gate |
| Workload | LM Studio `llmster` | OPEN, separate from desktop app | NVIDIA's Spark playbook currently uses the headless daemon | Do not infer selection; decide service, API exposure, models, storage, and update pin |
| Workload | Isaac Sim/Lab | SELECTED | NVIDIA's Spark playbook calls for a source build on GB10 and at least 50 GB for build artifacts/dependencies | Pin playbook and source commits, enumerate downloads, estimate full disk use, then build without activation |
| Workload | Omniverse robotics/simulation platform | SELECTED; exact app/component scope OPEN | Isaac Sim is built on Omniverse; additional desired Omniverse tooling is not yet enumerated | Start with the pinned Isaac path, then manifest each additional app, Kit component, service, and data requirement separately |
| Workload | NVIDIA NIM / AI Enterprise | NOT SELECTED | None | Do not add, evaluate, or deploy |
| Editor | Visual Studio Code | NOT SELECTED | The policy check proves both package sets reject it under the unfree predicate | Do not add; Zed is the selected editor |

Upstream versions are observations, not pins. Recheck them at the moment a
packaging change is proposed. The flake's
`roles.personalGraphicalCandidates` record now names exactly Chromium, Zed,
and LM Studio as selected candidates; it does not add them to any Home Manager
profile or install them.

## Repository development tools

CI and local hooks use a separate `nixpkgs-devtools` input; installed Home and
root packages keep their existing pins. Selected development-only tools are
pre-commit 4.6.2, ShellCheck 0.11.0, shfmt 3.14.0, Ruff 0.16.6, Actionlint
1.7.12, nixfmt 1.4.0, and Python 3.14.7. Upstream release checks were made on
2026-09-06. `dev/sources.json` pins the official pre-commit source distribution
and ARM64-musl Ruff binary because the stock packages still lag those releases.

These tools run in `nix develop` or disposable GitHub runners, not a Home
profile. They add no services, ports, GPU components, or account changes.
Build/download dependencies live in the Nix store; the hook test uses temporary
Git repositories. Local caches and optional repository Git hooks are the other
workspace state. Remove the hook with `./scripts/dev unhook`; revert the
development pin to roll back the tools. Never auto-format hash-pinned host
scripts as incidental cleanup.
See [development](development.md) for the local/CI commands and update procedure.

## Phase 1 evaluated profiles

These are Home Manager package graphs, not host desktop modes. The pilot's
exported user-layer `headless` profile is active as exact generation one. That
Home activation originally left factory GNOME/GDM untouched and running. The
later confirmed root generation five now runs the same Home profile in actual
host-level headless mode, with factory GNOME still installed but inactive.

| Profile | Effective direct Home Manager additions | Build validation | Realized closure |
| --- | --- | --- | --- |
| `headless` | `ncdu`, `lazydocker`, Devbox 0.18.0, Armen's Codex CLI 0.153.0, intrinsic `hm-session-vars.sh`; no Home Manager user-systemd units | ACTIVE generation one; two guarded activations plus disposable and real rollback passed | 52-path / 696.8 MiB activation closure; installed home path is 643.2 MiB. See the [host result](2026-09-03-home-headless-host.md) |
| `gnome` | Headless graph, Ghostty, `shared-mime-info`, and two Home Manager MIME-directory sentinels | Build passed with `--no-link` | Realized generation closure: 1.7 GiB |
| `hyprland` without portal | GNOME graph plus pinned Hyprland and Xwayland | Build passed with `--no-link` | Realized generation closure: 2.3 GiB |
| `hyprland` with portal | Hyprland graph plus portal core, Hyprland backend, GTK fallback, and generated portal config | Build passed with `--no-link` | Realized generation closure: 3.5 GiB |

The closure totals above come from `nix path-info -Sh` on the exact realized
Home Manager generation outputs after the 2026-09-03 Codex package build. They are
store closure sizes, not additional disk-space estimates for another host;
deduplication and its existing store contents will change incremental cost.

Later headless generations are governed by the
[guarded update lifecycle](2026-09-03-home-headless-update-lifecycle.md). The
operator is a true no-op while this table's candidate remains current; it does
not manufacture a generation merely to prove the path.

Ghostty is the dominant new graphical cost. Its root alone reports roughly
369 MiB compressed download and 1.1 GiB NAR closure. The dependency list is
predominantly GTK, GStreamer, audio/video codecs, fonts, and graphics
libraries. Evaluation found no Ghostty autostart, service, socket, or permission
change.

The exact locked Chromium 152.0.7977.75 ARM64 package is built as a
candidate-only 340-path / 1.7 GiB closure. It declares no service, socket,
timer, or autostart, but cannot launch safely on the current non-NixOS host
without a root sandbox integration: its store helper is intentionally not
setuid, while Ubuntu AppArmor blocks its user-namespace fallback. `--no-sandbox`
and global AppArmor relaxation are explicitly rejected. A version-matched
root-owned wrapper or exact-path AppArmor profile must be separately designed
and tested before graphical activation. See the
[package evidence](2026-09-03-chromium-package.md).

The exact official Zed 1.18.0 ARM64 bundle is built as a candidate-only
6-path / 485.5 MiB closure. Its vendor binaries remain byte-for-byte intact and
use the factory Ubuntu glibc plus NVIDIA Vulkan runtime; the wrapper only
disables self-update through Zed's documented environment contract. The
isolated version test created no state, and the output contains no service,
socket, timer, or autostart. Factory-GNOME Vulkan and portal validation remain
open. See the [package evidence](2026-09-03-zed-package.md).

The exact official LM Studio 0.4.23-1 ARM64 AppImage is built as a
candidate-only 9-path / 2.4 GiB closure. It intentionally bridges to the
factory Ubuntu runtime because a Bubblewrap AppImage wrapper cannot create a
user namespace under this host's AppArmor policy. The vendor launcher then
falls back to Electron `--no-sandbox`; that explicit security/runtime caveat,
its launch-time update check, URL-handler behavior, and GB10 acceleration must
be resolved in the graphical gate. It declares no daemon, listener, model, or
autostart. See the [package evidence](2026-09-03-lmstudio-package.md).

The Devbox build fetched a Go/compiler build toolchain because upstream 0.18.0
is not yet in the binary cache; those build-time paths are not its runtime
closure. The output is a 16.1 MiB root NAR with an 8-path, 65.8 MiB closure and
no service or autostart. That no-link build installed or activated no Home
Manager profile; the later guarded Home transaction is recorded separately.

The Tailscale source archive is 35,733,085 bytes with published SHA-256
`a0fa1b154af8c61f862a2259f559f7396d96c0225f4a863eae2333e1546bbe25`.
The output contains only the byte-identical `tailscale` and `tailscaled`
binaries. The generated daemon, optional wait-online service, and online target
all passed `systemd-analyze verify`. The daemon unit preserves the current
state/socket paths and `multi-user.target`; the two online-wait artifacts remain
opt-in. After the guarded real migration and reboot, the active service has
`/etc/systemd/system/tailscaled.service` as its loaded fragment and executes the
pinned Nix package. Apt's byte-identical binaries remain installed but inactive.

The root-manager canary pins System Manager 1.1.0 at revision
`05e08c6dd739d7f3204e71322594bb8095334cfb` and uses the official Nix
2.35.2 release flake for its private engine wrapper. Its 109-path, 230.0 MiB
runtime closure contains no Nix 2.34.8 and no real `userborn`. The evaluated
base surface materializes exactly five filesystem entries:
`/etc/dgx-setup/canary`, three systemd control/canary units, and their
target-wants dependency symlink. Generation three adds only the sixth tracked
boot edge. Neither form owns host Nix configuration, packages, users, wrappers,
PATH hooks, ports, Tailscale, Docker, GDM, or NVIDIA services.

Upstream 1.1.0 globally processes every visible tmpfiles rule when its managed
list is empty. The repository's exact-version `skip-empty-tmpfiles` patch has
SHA-256 `32756de30fd5730ebe60cce6ef89fc924ccd4eb3530e21ceb53fdf6073ba0e9a`.
The manifest and closure policy require that patch, an empty managed set, and
`invokesGlobalTmpfiles = false`; the container test adds an unmanaged rule and
requires it to remain unprocessed.

The first root-local disposable-container activation reached System Manager and
failed closed when the upstream global invocation tried to change journal modes.
That container was destroyed and its host postflight was clean. The exact
patched derivation then passed: the engine skipped global tmpfiles processing,
the unmanaged sentinel remained absent, exactly five paths and three service
keys were managed, protected files were unchanged, and deactivation removed the
canary surface inside the disposable container. The valid output and clean host
postflight are recorded in the
[container validation record](../root/system-manager/validation/2026-08-24-container-test.md).

The later generation-three candidate leaves that package/service ownership
unchanged and adds only its marker plus the tracked
`default.target.wants/system-manager.target` symlink. Its exact transaction
program has SHA-256
`53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288`.
The 13-subtest/two-restart disposable derivation
`/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv`
passed with output
`/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction`
and hash
`sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn`. The
[exact result](../root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md)
records a clean real-host postflight: generation two remained live and no host
boot link or generation-three root appeared.

The current persistent first-reboot recovery transaction has SHA-256
`b1f04f39169cc000b5a532545439693bafd9d6c62d0190e9aac2c231394a6be9`.
Its 13-subtest/two-restart disposable derivation
`/nix/store/jqmx45mxqqz34d4yjh3186xadb2ai6qx-container-test-dgx-root-canary-reboot-recovery-transaction.drv`
passed with output
`/nix/store/p0ywhqdf58h5r83z1pah7arba4rqr0ka-container-test-dgx-root-canary-reboot-recovery-transaction`
and Nix hash
`sha256:0v7i51bmpjghm8v3cly7i82j3ysvk3in17s5av2465wy3zhzmgp8`. The exact
[recovery result](../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md)
records unchanged real-host generation three and a completely absent recovery
surface. The separately reviewed
[live plan](../root/system-manager/validation/2026-09-03-reboot-recovery-live-plan.md)
documents the unarmed snapshot/arming/postboot lifecycle and its independent
reboot-authorization boundary.

Low-level activation writes
`/var/lib/system-manager/state/system-manager-state.json`; deactivation removes
the managed links/units and leaves an empty state record. The original isolated
activation test registers no profile or GC root. Separately, the live host now
has exact generations one through five registered and directly pilot-rooted.
Generation five is selected, upstream-rooted, live, boot-linked, and headless
after the successful retry-safe generation-three restoration, guarded Tailscale
migration, and guarded desktop switch; every recovery/transition surface is
absent and no rollback timer is armed.
The helper supplies temporary root-local
`auto-allocate-uids`/`cgroups` flags and isolates root's personal Nix config
with `NIX_USER_CONF_FILES=/dev/null`; it does not persist daemon settings. Nix
2.35.2 emitted a non-fatal top-level warning about `auto-allocate-uids`, but
the warning was absent from the successful derivation log and the required
UID-range/cgroup test completed. Its test-only plan was 943.7 MiB download /
3.9 GiB unpacked. Nix's UID lock, cgroup tracking, and stale temporary-root
records are disclosed operational bookkeeping, not a manager generation, and
were not manually removed. See the root-manager runbook.

The portal remains an independent option. Selecting Hyprland sets Home
Manager's implicit `portalPackage` to `null`; only
`dgx.desktop.hyprland.portal.enable = true` can add the portal core and the
reviewed Hyprland/GTK backends.

## Machine-readable view

The flake exposes direct role records, exact source revisions, licenses,
derivation/output paths, and de-duplicated effective profile package lists:

```bash
nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxProfileManifests.aarch64-linux
```

The separately scoped root-manager source, closure policy, declared state and
registration paths, and inert-evaluation side-effect flags are exported as:

```bash
nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxRootManagerManifest.aarch64-linux
```

Those booleans describe what flake evaluation/build itself performs; they do
not probe mutable host state. The
[retained generation-two host record](../root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md)
is historical milestone evidence. The
[boot-persistence test record](../root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md)
proves that its disposable test left that then-live state unchanged. The
historical
[retained generation-three host record](../root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md)
and [successful restoration record](../root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md)
are historical recovery authorities. The retained generation-four
[Tailscale record](../root/tailscale/validation/2026-09-05-host-attempt-2.md)
is inherited access-plane authority. Current live-state authority is the
[confirmed generation-five desktop record](../root/desktop/validation/2026-09-05-host-attempt-2.md).

The evaluation-only invariant suite is:

```bash
./scripts/check.sh
```

A future read-only missing-output plan for one profile is:

```bash
nix --extra-experimental-features "nix-command flakes" \
  build --dry-run --no-link \
  .#checks.aarch64-linux.home-base
```

Substitute `home-graphical`, `home-hyprland`, or
`home-hyprland-with-portal`. Removing `--dry-run` is a separate build
authorization.

## Per-item approval record

Before realizing or downloading a selected item, add a reviewed record beside
its module or workload with:

- logical layer, user/host scope, and reason;
- exact Nix attribute or upstream artifact;
- version, source revision, URL, hash, and ARM64 support;
- current candidate comparison and audit date;
- free/unfree evaluation behavior, only as technically relevant;
- expected download size, Nix closure size, and persistent disk requirement;
- system and user services, autostarts, sockets, ports, and network exposure;
- mutable state, model/cache directories, secrets boundary, and backup need;
- graphics/portal/session requirements;
- update procedure, validation test, prior pin, and rollback procedure.

For containers, record the readable tag, multi-architecture index digest, and
the resolved `linux/arm64` child digest. A tag alone is not a pin.

For source builds, record every repository commit, submodule/LFS revision,
downloaded SDK/archive, build toolchain, and output path. A mutable branch or
vendor install script is not a pin.

## Closure review

The practical SBOM for a Nix item is its evaluated package plus the transitive
closure Nix will realize. Before installation:

1. evaluate the exact profile without activation;
2. inspect build/download plans and license evaluation failures;
3. build with `--no-link` only after build approval;
4. export closure paths, package metadata, sizes, and provenance;
5. compare the result with this manifest and flag unexpected services or large
   dependencies;
6. approve installation separately.

A build is not an installation, an installation is not an activation, and an
application launch may create mutable state that also needs explicit approval.

## Evidence breadcrumbs

- [Ghostty stable releases](https://ghostty.org/docs/install/release-notes)
- [ncdu releases](https://dev.yorhel.nl/ncdu)
- [lazydocker releases](https://github.com/jesseduffield/lazydocker/releases)
- [Devbox releases](https://github.com/jetify-com/devbox/releases)
- [Current Chromium package evidence](2026-09-03-chromium-package.md)
- [Zed Linux and ARM64 requirements](https://zed.dev/docs/linux)
- [Zed releases](https://github.com/zed-industries/zed/releases)
- [Current Zed package evidence](2026-09-03-zed-package.md)
- [LM Studio downloads and current release](https://lmstudio.ai/download)
- [NVIDIA LM Studio/llmster Spark playbook](https://build.nvidia.com/spark/lm-studio)
- [Current LM Studio package evidence](2026-09-03-lmstudio-package.md)
- [NVIDIA Isaac Sim/Lab Spark playbook](https://build.nvidia.com/spark/isaac)
- [Repository source map](../.agents/skills/dgx-spark-ops/references/source-map.md)
- [System Manager canary runbook](../root/system-manager/README.md)

## Current unfree boundary

The stable package set explicitly denies unfree packages. The apps package set
also denies unfree by default and permits only the exact Nix package name
`lmstudio`. The policy evaluation confirms that:

- `ncdu`, `lazydocker`, `devbox`, `ghostty`, Chromium, and Zed are free;
- `lmstudio` is the only accepted unfree evaluation exception;
- VS Code remains rejected in both package sets;
- ChatGPT has no selected Nix packaging path, so no exception exists for it.

The exception installs nothing by itself. Do not broaden it “for convenience.”
If an approved closure fails because another package is unfree, stop and
present that exact dependency and why it entered the graph.
