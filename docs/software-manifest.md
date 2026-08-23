# Pre-install software manifest

This is the lightweight SBOM and approval gate for software above the NVIDIA
factory substrate. Its job is practical: show what a profile would add, why it
is wanted, where it comes from, how large and active it is, and how to undo it
before anything is installed.

This is not a license registry. Record free/unfree status only when it affects
Nix evaluation, redistribution, or the installation method.

## Status of this snapshot

Evidence date: **2026-08-23**

The versions below came from read-only evaluation of the repository's locked
`aarch64-linux` package set and current official vendor pages. No package was
built, installed, activated, launched, or added to a profile while collecting
this evidence.

| Layer | Item | Intent | Current evidence | Gate before build/install |
| --- | --- | --- | --- | --- |
| Fleet base | Base cleanup | REQUIRED | Current scaffold has `fd`, `jq`, and `ripgrep`; none remains selected for the permanent base | Remove them from the base module; keep project tools in the dev shell |
| Fleet base | ncdu | SELECTED | Locked `ncdu` 2.9.2 is current, free, and ARM64-available | Inspect its individual and combined base closure |
| Fleet base | lazydocker | SELECTED | Locked `lazydocker` 0.25.2 is current, free, and ARM64-available | Confirm no service, Docker group, socket permission, or autostart change |
| Fleet base | Devbox | SELECTED | Locked `devbox` 0.17.2 is ARM64/free; upstream is 0.17.5 | Do not install the stale lock; pin current Devbox and confirm it consumes rather than replaces the existing Nix runtime |
| Dev shell | Git, jq, nixfmt-tree, ripgrep | Repository work only | Already declared in `devShells.default`; not permanent | Keep out of the user profile unless separately selected |
| Factory desktop | Ubuntu GNOME/GDM | Recovery and `gnome` mode | Factory-owned and currently installed | Never replace or remove during another desktop pilot |
| Desktop role | Hyprland | Optional `hyprland` mode | v0.56.2 is pinned and ARM64 build-tested; inactive | Review graphics bridge, portal closure, GDM entry, and rollback |
| Desktop role | KDE Plasma | Supported future mode | No package set selected or built | Approve role, closure, portal, display-manager integration, and ARM64 test |
| Shared graphical role | Ghostty | SELECTED terminal for every graphical mode | Locked `ghostty` 1.3.1 is current, free, and ARM64-available | Inspect closure and validate GTK/GPU behavior under GNOME and each approved Wayland mode; keep out of headless |
| Armen graphical overlay | Chromium | SELECTED browser | Locked `chromium` 151.0.7922.137 is available and marked free on ARM64 | Recheck security candidate, closure, extension policy, and NVIDIA graphics behavior |
| Armen graphical overlay | Zed | SELECTED editor | Locked `zed-editor` 1.3.6 is ARM64/free; upstream stable is v1.16.1 | Do not install the stale lock; choose a current reproducible pin and test Vulkan/Wayland/portal behavior |
| Armen graphical overlay | LM Studio desktop | SELECTED model manager | Locked `lmstudio` 0.4.15-2 is ARM64/unfree; vendor desktop release is 0.4.21 | Use an exact unfree exception, obtain a current pin, inspect closure/model paths, and validate GB10 acceleration |
| Armen graphical overlay | ChatGPT desktop | SELECTED; currently manual | Existing Debian installation is migration input; repository pin is absent | Verify official artifact/provenance, ARM64 support, update behavior, collisions, and rollback |
| Armen graphical overlay | 1Password for Firefox | SELECTED; currently manual | Existing extension is migration input; version and pin are not captured | Choose reproducible extension policy without storing account/browser state |
| Armen graphical overlay | 1Password for Chromium | SELECTED | Not yet declared | Choose reproducible extension policy without storing account/browser state |
| Access overlay | Tailscale/Tailscale SSH | ACCEPTED; currently manual | Official apt `tailscale` 1.102.3 is migration input; locked Nixpkgs was older at baseline | Follow the dedicated anti-downgrade, recovery, identity-preservation, and reboot gates |
| Workload | LM Studio `llmster` | OPEN, separate from desktop app | NVIDIA's Spark playbook currently uses the headless daemon | Do not infer selection; decide service, API exposure, models, storage, and update pin |
| Workload | Isaac Sim/Lab | SELECTED | NVIDIA's Spark playbook calls for a source build on GB10 and at least 50 GB for build artifacts/dependencies | Pin playbook and source commits, enumerate downloads, estimate full disk use, then build without activation |
| Workload | Omniverse robotics/simulation platform | SELECTED; exact app/component scope OPEN | Isaac Sim is built on Omniverse; additional desired Omniverse tooling is not yet enumerated | Start with the pinned Isaac path, then manifest each additional app, Kit component, service, and data requirement separately |
| Workload | NVIDIA NIM / AI Enterprise | NOT SELECTED | None | Do not add, evaluate, or deploy |
| Editor | Visual Studio Code | NOT SELECTED | None | Do not add; Zed is the selected editor |

Upstream versions are observations, not pins. Recheck them at the moment a
packaging change is proposed.

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

## Current unfree boundary

The accepted default is deny. Based on the current locked metadata:

- `ncdu`, `lazydocker`, `devbox`, and `ghostty`: free;
- `chromium`: free;
- `zed-editor`: free;
- `lmstudio`: unfree, exact exception required if chosen;
- ChatGPT: packaging path not yet selected, so no exception is approved.

Do not broaden the predicate “for convenience.” If an approved closure fails
because some other package is unfree, stop and present that exact dependency
and why it entered the graph.
