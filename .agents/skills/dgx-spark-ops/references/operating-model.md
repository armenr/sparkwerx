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
- System Manager 1.1.0 is the selected root-manager candidate; its exact
  five-path/three-service canary is retained active. Exact generation one, the
  upstream extra GC root, and the pilot GC root are also retained; no boot link
  exists. Its 109-path / 230.0 MiB closure is forced to private Nix 2.35.2,
  rejects Nix 2.34.8 and real `userborn`, and owns only the canary/control and
  registration surfaces documented in `root/system-manager/README.md`;
- the first root-local disposable activation exposed System Manager 1.1.0's
  global empty-list tmpfiles behavior without touching the host; the candidate
  now carries an exact-version skip patch and an unmanaged-rule regression
  sentinel, and any version change requires patch reassessment;
- the exact patched disposable activation/deactivation derivation passed on
  2026-08-24, including the unmanaged tmpfiles sentinel, protected-file hashes,
  bounded state, rollback, and clean host postflight; any derivation change
  invalidates that evidence;
- three separately authorized low-level host canaries activated within the exact
  five-path/three-service boundary: two timed rollbacks completed successfully,
  and the third passed local-console confirmation and remains active with the
  exact bounded version-1 state under `/var/lib/system-manager/state`. A later,
  separately guarded transaction registered and retained exact generation one
  without changing that activation;
- low-level activation does not itself retain the store output. A live pilot
  must first create the manifest-declared direct root at
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot`. It is distinct from the
  later upstream generation registration and must remain alongside its profile
  links and `system-manager-current` root until a separately verified
  deactivation/registration rollback milestone;
- source inspection found System Manager 1.1.0 registration is non-transactional:
  its Nix profile can advance before a later extra-GC-root collision fails, and
  selecting a generation changes neither live activation nor that extra root.
  The exact two-generation disposable lifecycle derivation passed on
  2026-09-01 with a hash-valid output and clean host postflight. That pass
  authorized only transaction design; the later live registration required its
  own snapshot, rollback, authorization, repeated postflight, and independent
  console confirmation;
- a marker-only generation-two candidate and exact generation-switch
  transaction passed their distinct eleven-subtest disposable failure-injection
  derivation with a hash-valid output and clean host postflight. A later
  separately authorized live pilot used fresh snapshot `20260902T083437Z`,
  repeated postflight, and local-console confirmation to retain exact
  registered/live generation two. Generation one remains registered and
  directly retained, both pilot roots remain, and no boot link exists;
- the 2026-09-01 reboot audit confirmed the prior rollback state and healthy
  factory/access services; a factory Firefox Snap refresh one minute later
  changed the unit graph and correctly invalidated the earlier preflight until
  a daemon reload and full recheck passed without restarting protected
  services; the later third attempt is now the retained live state;
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
- The exact System Manager container tests and retained host canary passed.
  Preserve exact live generation two, registered generation one, all three
  profile links, the upstream generation-two root, both direct pilot roots, the
  five-path/three-service activation surface, and the no-boot boundary until a
  separately approved next milestone. The reviewed generation-two live pilot
  completed from a now-spent snapshot; rerun, rollback, cleanup, or reboot each
  requires separate authority. Rollback preserves both direct pilot roots.
  Never let it own host Nix, users, wrappers, global PATH, boot links, or factory
  services or process global factory tmpfiles rules when its managed set is
  empty; preserve the exact-version patch, regression sentinel,
  current-test match, exact registration links, and all three retention roots.
- Run one memory-heavy GPU workload per node by default. Multiple services may
  share a node only after memory and performance validation.
- Treat multi-node networking, QSFP topology, NCCL, and passwordless SSH as
  explicit fleet infrastructure work—not incidental application setup.
- Keep `tailscaled.service` in the headless `multi-user.target` role. Never
  restart it through the fleet's only active Tailscale SSH recovery path.
- Separate build success, activation success, application health, and workload
  correctness as distinct gates.
