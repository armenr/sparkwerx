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

- DGX OS is Ubuntu-based `aarch64-linux` with a GB10 GPU and Secure Boot;
- Nix was provisioned by the official NixOS `nix-installer` as a multi-user
  daemon installation, even though Devbox triggered it;
- `/nix/var/nix/profiles/default` resolves through root's Nix profile;
- the built-in `nix upgrade-nix` candidate can be older than installed Nix;
- Hyprland is pinned and build-tested for ARM64 but remains disabled;
- no Home Manager profile or GDM Hyprland session has been activated;
- Docker, Compose, and NVIDIA Container Toolkit are vendor-installed;
- the pilot user is not currently a member of the Docker group;
- Tailscale `1.102.3` was manually installed from Tailscale's official apt
  repository, its daemon is enabled at multi-user boot, and Tailscale SSH is
  active; and
- locked stable Nixpkgs exposes older Tailscale `1.98.10`, so replacing the
  apt package directly would be a downgrade.

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
- Run one memory-heavy GPU workload per node by default. Multiple services may
  share a node only after memory and performance validation.
- Treat multi-node networking, QSFP topology, NCCL, and passwordless SSH as
  explicit fleet infrastructure work—not incidental application setup.
- Keep `tailscaled.service` in the headless `multi-user.target` role. Never
  restart it through the fleet's only active Tailscale SSH recovery path.
- Separate build success, activation success, application health, and workload
  correctness as distinct gates.
