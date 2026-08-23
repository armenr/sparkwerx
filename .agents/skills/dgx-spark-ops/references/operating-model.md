# Operating model

## Purpose

Preserve NVIDIA DGX OS as the supported hardware layer while managing userland,
configuration, workload definitions, and fleet differences reproducibly.

This repository is the source of truth for desired configuration. It is not a
replacement operating system and must not silently take ownership of vendor
components.

## Ownership boundaries

| Layer | Owner | Update path |
| --- | --- | --- |
| Firmware, boot chain, kernel, NVIDIA driver, system CUDA | NVIDIA DGX OS and DGX Dashboard | Dashboard and NVIDIA release guidance |
| Docker engine and NVIDIA Container Toolkit | NVIDIA DGX OS | Dashboard/vendor packages |
| Nix daemon installation | Official NixOS `nix-installer` plus reviewed bootstrap | Root Nix profile with guarded upgrade |
| Non-NixOS root integration | This repository after pilot approval | Pinned System Manager canary with reviewed state, registration, and rollback |
| Fleet access: Tailscale package, daemon unit, and headless enablement | This repository after migration | Pinned Nix package plus reviewed root configuration; control-plane policy remains separate |
| Exact permanent fleet CLI base | This repository | Locked `ncdu`, `lazydocker`, and current `devbox` packages |
| Desktop mode and desktop-specific XDG/portal/session configuration | This repository plus reviewed root integration | One of headless/GNOME/Hyprland/KDE |
| Shared graphical terminal | This repository | Ghostty in graphical modes; absent from headless |
| Named personal tools and dotfiles | This repository | Explicit user overlays; `armen` is not a fleet default |
| Nixpkgs, Home Manager, individually approved CLI tools | This repository | Locked flake inputs and validation |
| CUDA-heavy AI application userlands | Pinned NVIDIA/upstream OCI images | Reviewed image/tag/digest update |
| Models, caches, databases, media, logs | Persistent workload storage | Backup/retention policy, not package updates |
| Per-host workload selection | Host roles in this repository | Reviewed fleet rollout |

Do not make the same component belong to two layers. In particular, do not
install another system CUDA toolkit, NVIDIA driver, Docker engine, or NVIDIA
Container Toolkit through Nix.

## Composition and personal scope

Compose `factory -> exact CLI base -> host services -> one desktop mode ->
shared graphical role -> named user overlays -> workload/project roles`. The
[decision register](../../../../docs/decision-register.md) controls selections
and the [software manifest](../../../../docs/software-manifest.md) controls
what may proceed to closure review.

Ghostty is shared across GNOME, Hyprland, and KDE, but is inactive in headless
mode. On the pilot, `armen` maps to `n0b0dy@sparkle-01`; its personal
graphical tools never become a common default. Isaac is a workload, not a
personal application bundle.

## Nix and containers

Nix and containers are complementary:

- Nix owns tools, configuration, wrappers, development shells, evaluation, and
  pins for source repositories.
- Containers own vendor-validated combinations of CUDA user-space libraries,
  Python, PyTorch, framework wheels, and application dependencies.
- DGX OS supplies the kernel driver and GPU device interface used by those
  containers.

Use a native Nix package when it is well-supported on `aarch64-linux`, does not
duplicate the vendor GPU stack, and its build can be validated. Use a pinned
container when NVIDIA's Spark playbook validates that path or the CUDA/Python
matrix is otherwise fragile. Use a pinned vendor source-build workflow when
that is the current Spark-supported route, as with Isaac.

The LM Studio desktop app and headless `llmster` daemon are different roles.
Selecting one does not select, expose, or autostart the other.

Devbox is a client of the existing Nix runtime. Managing the `devbox` package
does not give its bootstrap installer ownership of Nix or define the Nix
upgrade procedure.

A container is reproducible only when its architecture-specific digest is
recorded. A Compose file using `:latest` or `:main` is still mutable.

## Mutable state

Do not place these in the Nix store or bake them into application images:

- model weights and Hugging Face caches;
- Ollama model data;
- Open WebUI chat/database state;
- ComfyUI models, inputs, outputs, and custom user workflows;
- training datasets, checkpoints, adapters, and experiment logs;
- RAG indexes and databases;
- credentials or registry tokens;
- Tailscale node identity and daemon state under `/var/lib/tailscale`; and
- Tailscale enrollment keys, tailnet policy, and device approvals.

The intended fleet convention is a reviewed persistent root such as
`/srv/dgx`, divided by workload. Until that host directory is approved, use an
explicit user-owned path and document it. Never invent a storage location during
an update audit.

## Current pilot lessons

The dated inventory under `inventory/sparkle-01/` is evidence, not an eternal
fact. Re-audit before acting. The initial 2026-08-23 pilot established:
- repository-only Phase 1 pins stable Nixpkgs separately from the narrow apps
  input and uses current Devbox 0.18.0 through an exact source/vendor adapter,
  without invoking its installer;
- the evaluated headless role is exactly `ncdu`, `lazydocker`, and `devbox`,
  with XDG/MIME/portal, manpage, Home Manager CLI, and graphical roles off;
- the flake's `lib.dgxProfileManifests.aarch64-linux` output and
  `./scripts/check.sh` are the canonical no-build profile audit;
- Ghostty is current but its cache closure is roughly 1.1 GiB, so its build
  remains behind explicit graphical-role approval;

- DGX OS is Ubuntu-based `aarch64-linux` with a GB10 GPU and Secure Boot;
- Nix was provisioned by the official NixOS `nix-installer` as a multi-user
  daemon installation, even though Devbox triggered it;
- the guarded pilot rollout moved `/nix/var/nix/profiles/default` and the
  daemon to Nix 2.35.2, while the installer-created root-user 2.35.1 profile
  remains a separate GC-rooted rollback anchor;
- System Manager 1.1.0 is the selected but inactive/unregistered root-manager
  candidate; its 109-path / 230.0 MiB canary is forced to private Nix 2.35.2,
  rejects Nix 2.34.8 and real `userborn`, and owns only the canary/control
  surface documented in `root/system-manager/README.md`;
- the first root-local disposable activation exposed System Manager 1.1.0's
  global empty-list tmpfiles behavior without touching the host; the candidate
  now carries an exact-version skip patch and an unmanaged-rule regression
  sentinel, and any version change requires patch reassessment;
- the exact patched disposable activation/deactivation derivation passed on
  2026-08-24, including the unmanaged tmpfiles sentinel, protected-file hashes,
  bounded state, rollback, and clean host postflight; any derivation change
  invalidates that evidence;
- low-level System Manager activation would create a state record under
  `/var/lib/system-manager/state`, while generation profile/GC-root registration
  is separate; neither has occurred on the pilot;
- the built-in `nix upgrade-nix` target is a manually maintained literal store
  path with no downgrade guard; it still proposes 2.34.8 over active 2.35.2;
- Hyprland is pinned and build-tested for ARM64 but remains disabled;
- no Home Manager profile or GDM Hyprland session has been activated;
- Docker, Compose, and NVIDIA Container Toolkit are vendor-installed;
- the pilot user is not currently a member of the Docker group;
- Tailscale `1.102.3` was manually installed from Tailscale's official apt
  repository, its daemon is enabled at multi-user boot, and Tailscale SSH is
  active; and
- locked stable/apps Nixpkgs expose older Tailscale `1.98.10`/`1.102.2`, so the
  repository now pins and build-validates official stable `1.102.3`; the apt
  service still owns the live daemon and identity.

The Tailscale versions above are dated baseline evidence. Re-audit them and read
[the dedicated Tailscale reference](tailscale.md) before changing ownership.

Do not add Docker group membership casually. Access to the Docker daemon is
effectively root-equivalent and belongs in the reviewed host bootstrap.

## Fleet invariants

- Pilot changes on one Spark before fleet rollout.
- Keep GNOME available as the recovery desktop during every graphical pilot.
- In headless mode, stop desktop/display/portal services but retain factory
  packages and `tailscaled.service`.
- Keep the permanent base limited to `ncdu`, `lazydocker`, and `devbox`.
- Keep Ghostty shared across graphical modes and absent from headless.
- Keep user overlays explicit; never infer Armen's overlay for another user.
- Honor the non-selections in the decision register instead of re-proposing
  nearby catalog products.
- Keep old Nix generations, old container digests, and prior configuration
  revisions until validation is complete.
- The exact System Manager container test passed; keep the candidate inactive
  and unregistered until a separately approved host canary passes. Never let it
  own host Nix, users, wrappers, global PATH, boot links, or factory services or
  process global factory tmpfiles rules when its managed set is empty; preserve
  the exact-version patch, regression sentinel, and current-test match.
- Run one memory-heavy GPU workload per node by default. Multiple services may
  share a node only after memory and performance validation.
- Treat multi-node networking, QSFP topology, NCCL, and passwordless SSH as
  explicit fleet infrastructure work—not incidental application setup.
- Keep `tailscaled.service` in the headless `multi-user.target` role. Never
  restart it through the fleet's only active Tailscale SSH recovery path.
- Separate build success, activation success, application health, and workload
  correctness as distinct gates.
