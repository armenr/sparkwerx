# Pre-install software manifest

This is the lightweight SBOM and approval gate for software above the NVIDIA
factory substrate. Its job is practical: show what a profile would add, why it
is wanted, where it comes from, how large and active it is, and how to undo it
before anything is installed.

This is not a license registry. Record free/unfree status only when it affects
Nix evaluation, redistribution, or the installation method.

## Status of this snapshot

Evidence date: **2026-08-24**

The versions below came from the current 2026-08-23 lock, exact upstream pins,
and current official vendor sources. Stable Nixpkgs was advanced to its current
branch head. Devbox 0.18.0 and Tailscale 1.102.3 plus its inert unit tree were
built with `--no-link` and inspected. The patched System Manager 1.1.0 inert
root canary and closure policy were also built and inspected without host
activation. The first disposable-container activation failed closed on upstream
global tmpfiles behavior; after the exact-version patch, the exact current
activation/deactivation derivation passed and clean postflight proved the host
untouched. System Manager was not registered or activated on the host, Tailscale
was not restarted or replaced, and the desktop was not switched.

Hyprland and its portal had already been build-tested earlier in the pilot.
Their existing local store closures were measured read-only; they were not
rebuilt in Phase 1.

| Layer | Item | Intent | Current evidence | Gate before build/install |
| --- | --- | --- | --- | --- |
| Fleet base | Exact role | REQUIRED | Implemented as exactly `ncdu`, `lazydocker`, and `devbox`; old `fd`, `jq`, and `ripgrep` remain dev-shell-only | Review the measured three-root closure and activation collision report |
| Fleet base | ncdu | SELECTED | Stable pin `ncdu` 2.9.2 is current, free, and ARM64-available | Build only as part of an explicitly approved base build |
| Fleet base | lazydocker | SELECTED | Stable pin `lazydocker` 0.25.2 is current, free, and ARM64-available; the module adds only a user package | Do not add Docker group membership, socket ACLs, a service, or autostart |
| Fleet base | Devbox | SELECTED; BUILD-PASSED | Exact adapter pins current upstream 0.18.0 source and Go vendor hashes because both Nixpkgs branches still expose 0.17.5. Built ARM64 binary reports 0.18.0; 8-path runtime closure is 65.8 MiB NAR | Never invoke Devbox's bootstrap installer or let Devbox replace/update Nix; retain adapter until stock catches up |
| Dev shell | Git, jq, nixfmt-tree, ripgrep | Repository work only | Direct versions are Git 2.55.0 and ripgrep 15.2.0 from apps, jq 1.8.2 and nixfmt-tree 2.5.0 from stable; manifest-only, never permanent | Keep out of the user profile unless separately selected |
| Factory desktop | Ubuntu GNOME/GDM | Recovery and future `gnome` host mode | Factory-owned, installed, and still running | Never replace or remove during another desktop pilot |
| Desktop role | Hyprland | Optional `hyprland` mode | v0.56.2 is pinned and ARM64 build-tested; Home Manager profile is evaluable and inactive | Review graphics bridge, GDM entry, portal choice, and rollback |
| Desktop role | KDE Plasma | Supported future mode | Enum value exists; no package set or root integration is selected | Approve role, closure, portal, display-manager integration, and ARM64 test |
| Shared graphical role | Ghostty | SELECTED terminal for every graphical mode | Stable pin `ghostty` 1.3.1 is current, free, and ARM64-available; its large GTK/GStreamer closure is quantified below | Decide whether the roughly 1.1 GiB Ghostty closure is acceptable, then validate GTK/GPU behavior; keep out of headless |
| Armen graphical overlay | Chromium | SELECTED browser | Apps pin exposes `chromium` 151.0.7922.173 on ARM64/free; not wired into the overlay | Recheck security candidate, closure, extension policy, and NVIDIA graphics behavior |
| Armen graphical overlay | Zed | SELECTED editor | Apps pin exposes `zed-editor` 1.16.1 on ARM64/free, matching the reviewed upstream release; not wired | Inspect closure and test Vulkan/Wayland/portal behavior |
| Armen graphical overlay | LM Studio desktop | SELECTED model manager | Apps pin exposes `lmstudio` 0.4.21-2 on ARM64/unfree, matching vendor 0.4.21; not wired | Keep the one exact unfree exception, inspect closure/model paths, and validate GB10 acceleration |
| Armen graphical overlay | ChatGPT desktop | SELECTED; currently manual | Existing Debian installation is migration input; repository pin is absent | Verify official artifact/provenance, ARM64 support, update behavior, collisions, and rollback |
| Armen graphical overlay | 1Password for Firefox | SELECTED; currently manual | Existing extension is migration input; version and pin are not captured | Choose reproducible extension policy without storing account/browser state |
| Armen graphical overlay | 1Password for Chromium | SELECTED | Not yet declared | Choose reproducible extension policy without storing account/browser state |
| Access overlay | Tailscale/Tailscale SSH | ACCEPTED; PACKAGE/UNITS BUILD-PASSED; activation OPEN | Apt 1.102.3 remains live. Repository pins current stable official ARM64 1.102.3 tarball and checksum; copied binaries are byte-identical, static, and form a one-path 67.7 MiB runtime closure. Inert three-unit tree adds 2,640 NAR bytes and references that package. Stable/apps stock are only 1.98.10/1.102.2 | Do not replace/restart the live daemon over Tailscale SSH; validate the selected root-manager candidate and pass console, rollback, state/identity, reboot, and reconnect gates |
| Root runtime | Nix | CURRENT; ACTIVATED/VERIFIED | Active client and daemon are 2.35.2 from the exact signed-cache path under `root/nix/`; default environment is `9lznxxcs…-user-environment`. The installer artifact and separately rooted rollback environment retain 2.35.1. Default fallback target 2.34.8 remains blocked | For each future release/host, re-run exact provenance, downgrade, profile, daemon, and rollback gates; do not garbage-collect the retained 2.35.1 environment yet |
| Root integration | System Manager | SELECTED; PATCHED RUNTIME/POLICY/CONTAINER TEST PASSED; host activation OPEN | Exact 1.1.0 pin on matching `release-26.05`; inert ARM64 closure is 109 paths / 230.0 MiB. Its exact-version `skip-empty-tmpfiles` patch prevents global factory-rule processing when the managed set is empty. It adds no global package, port, boot link, user, wrapper, PATH hook, or NVIDIA/Tailscale/desktop ownership. Its private wrapper is verified Nix 2.35.2; Nix 2.34.8 and real `userborn` are closure-rejected. The exact patched disposable activation/deactivation test passed and clean postflight found no host artifact | Inspect collisions/state, establish independent console/timed rollback, and request separate canary activation approval |
| Workload | LM Studio `llmster` | OPEN, separate from desktop app | NVIDIA's Spark playbook currently uses the headless daemon | Do not infer selection; decide service, API exposure, models, storage, and update pin |
| Workload | Isaac Sim/Lab | SELECTED | NVIDIA's Spark playbook calls for a source build on GB10 and at least 50 GB for build artifacts/dependencies | Pin playbook and source commits, enumerate downloads, estimate full disk use, then build without activation |
| Workload | Omniverse robotics/simulation platform | SELECTED; exact app/component scope OPEN | Isaac Sim is built on Omniverse; additional desired Omniverse tooling is not yet enumerated | Start with the pinned Isaac path, then manifest each additional app, Kit component, service, and data requirement separately |
| Workload | NVIDIA NIM / AI Enterprise | NOT SELECTED | None | Do not add, evaluate, or deploy |
| Editor | Visual Studio Code | NOT SELECTED | The policy check proves both package sets reject it under the unfree predicate | Do not add; Zed is the selected editor |

Upstream versions are observations, not pins. Recheck them at the moment a
packaging change is proposed.

## Phase 1 evaluated profiles

These are evaluated Home Manager package graphs, not activated host modes. The
pilot's exported Home configuration is deliberately staged as user-layer
`headless`, so its first candidate contains the exact CLI base. Factory
GNOME/GDM remains untouched and running because no approved root desktop
controller is active yet.

| Profile | Effective direct Home Manager additions | Missing-output dry-run on this pilot | Complete closure evidence available without a build |
| --- | --- | --- | --- |
| `headless` | `ncdu`, `lazydocker`, Devbox 0.18.0, intrinsic `hm-session-vars.sh` | 6 derivations; 2 missing cache paths; 4.6 MiB download / 12.3 MiB unpacked | Three roots: 21 de-duplicated paths / 142.5 MiB NAR; Devbox is already local, others measured from signed cache metadata |
| `gnome` | Headless base, Ghostty, `shared-mime-info`, and two Home Manager MIME-directory sentinels | 3 derivations; 224 missing paths; 233.2 MiB download / 692.4 MiB unpacked | Ghostty remains dominant; combined profile is not built |
| `hyprland` without portal | GNOME graph plus pinned Hyprland and Xwayland | 5 derivations; 239 missing paths; 235.6 MiB download / 700.6 MiB unpacked | Existing custom Hyprland root: 177 local paths / 584 MiB NAR; this is not a combined-profile total |
| `hyprland` with portal | Hyprland graph plus portal core, Hyprland backend, GTK fallback, and generated portal config | 8 derivations; 271 missing paths; 257.1 MiB download / 839.8 MiB unpacked | Existing custom portal root, including its overridden Hyprland dependency: 349 local paths / 1.7 GiB NAR; this is not a combined-profile total |

`nix build --dry-run` reports only outputs missing from the pilot's current
store, so its totals vary with local store state and are not total closure
sizes. The cache figures above came from signed `cache.nixos.org` metadata for
the immutable roots. The local Hyprland figures came from already-realized
pilot artifacts.

Ghostty is the dominant new graphical cost. Its root alone reports roughly
369 MiB compressed download and 1.1 GiB NAR closure. The dependency list is
predominantly GTK, GStreamer, audio/video codecs, fonts, and graphics
libraries. Evaluation found no Ghostty autostart, service, socket, or permission
change.

The Devbox build fetched a Go/compiler build toolchain because upstream 0.18.0
is not yet in the binary cache; those build-time paths are not its runtime
closure. The output is a 16.1 MiB root NAR with an 8-path, 65.8 MiB closure and
no service or autostart. No Home Manager profile was installed or activated.

The Tailscale source archive is 35,733,085 bytes with published SHA-256
`a0fa1b154af8c61f862a2259f559f7396d96c0225f4a863eae2333e1546bbe25`.
The output contains only the byte-identical `tailscale` and `tailscaled`
binaries. The generated daemon, optional wait-online service, and online target
all passed `systemd-analyze verify`. The daemon unit preserves the current
state/socket paths and `multi-user.target`; the two online-wait artifacts remain
opt-in and all three are unlinked. The active service still has
`/usr/lib/systemd/system/tailscaled.service` as its fragment and
`/usr/{bin,sbin}` binaries.

The root-manager canary pins System Manager 1.1.0 at revision
`05e08c6dd739d7f3204e71322594bb8095334cfb` and uses the official Nix
2.35.2 release flake for its private engine wrapper. Its 109-path, 230.0 MiB
runtime closure contains no Nix 2.34.8 and no real `userborn`. The evaluated
surface materializes exactly five filesystem entries: `/etc/dgx-setup/canary`,
three systemd control/canary units, and their target-wants dependency symlink.
It is not boot-linked and owns no host Nix configuration, package, users,
wrappers, PATH hook, port, Tailscale, Docker, GDM, or NVIDIA service.

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

Low-level activation would write
`/var/lib/system-manager/state/system-manager-state.json`; deactivation removes
the managed links/units and leaves an empty state record. No profile or GC root
has been registered. The helper supplies temporary root-local
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

The separately scoped root-manager source, closure policy, operational state,
and registration status are exported as:

```bash
nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxRootManagerManifest.aarch64-linux
```

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
- [Zed Linux and ARM64 requirements](https://zed.dev/docs/linux)
- [Zed releases](https://github.com/zed-industries/zed/releases)
- [LM Studio downloads and current release](https://lmstudio.ai/download)
- [NVIDIA LM Studio/llmster Spark playbook](https://build.nvidia.com/spark/lm-studio)
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
