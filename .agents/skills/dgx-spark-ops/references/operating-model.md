# Operating model

[Architecture](../../../../docs/architecture.md) ·
[Current checkpoint](../../../../docs/status.md) ·
[Decision register](../../../../docs/decision-register.md)

This is the policy reference, not a chronological pilot log. Read the matching
dated transaction records when changing that transaction.

## Ownership and composition

NVIDIA owns DGX OS, firmware, kernel, NVIDIA driver, system CUDA, Docker,
Container Toolkit, and factory applications. Sparkwerx manages the chosen
software and specific configuration above that layer. Never give a component
two active owners or install a competing system GPU stack.

Compose the exact fleet CLI base, explicit access role, one desktop mode,
shared graphical role, named user overlays, and independent workloads.
A choice in one layer must not silently enable a different one.

- Base: exactly ncdu, lazydocker, and Devbox.
- Repository tooling: dev shells, not permanent profile expansion.
- Ghostty: shared graphical role; absent from headless.
- Armen: explicit per-host mapping; Codex in all modes, personal graphical
  apps separate and currently not activated.
- Tailscale: optional native host role, not a containerized access plane.
- Workloads: selected separately; no automatic model download, listener, or autostart.

The current [configuration limits](../../../../docs/configuration.md#current-limits)
matter: lower-level module options are broader than the tested operator path.
Do not describe arbitrary user/package selection as implemented.

## Package and data rules

Use Nix for supported ARM64 packages, tools, configuration, and source pins.
Use pinned vendor-compatible containers or source builds for CUDA-heavy
applications when the Spark playbook supports that route. Record both the
readable container tag and exact architecture-specific digest.

Review the [software manifest](../../../../docs/software-manifest.md) before
realization or deployment. No global unfree permission: general apps permit
only `lmstudio`. Sunshine has a separate package set permitting only its
required `cuda_nvcc`, `cuda_cudart`, and `cuda_cccl` dependencies. Read the
[adapter and update instructions](../../../../packages/sunshine/README.md)
before changing it; keep factory CUDA and the driver untouched. Honor the
decision register's explicit exclusions.

Keep models, datasets, caches, databases, generated media, credentials,
browser profiles, Tailscale identity, and account state outside Git, Nix store
outputs, and images. `/srv/dgx` is a proposed convention, not a created storage
root or a completed backup policy.

The LM Studio desktop app does not select `llmster`, LM Link, a server, or a
model. Isaac and additional Omniverse components are a separate workload—not
permission to deploy the whole NVIDIA catalog.

## Access and desktop continuity

Tailscale must start at multi-user boot and survive a desktop-mode transition.
A daemon restart can terminate Tailscale SSH; independent console access and
the reviewed timed rollback are required before an access transition.

The current pilot runs Nix-owned Tailscale inherited by headless generation
five. Its apt package/source is deliberately retained fallback, not active
ownership or automatic cleanup material. Read [tailscale.md](tailscale.md)
before changing that role.

Headless retains factory desktop packages but stops GDM and Dashboard GUI.
Dashboard Admin, Docker, NVIDIA persistence, networking, and selected Tailscale
remain independent. Preserve the explicit headless conflict with the GUI's
factory default-target edge and the GNOME target's non-fatal GUI dependency.

Hyprland and its portal have separate selection/validation. Keep GNOME as the
recovery desktop for future graphical pilots. Chromium's sandbox, Zed's
updater/GPU checks, and LM Studio's Electron/Deno behavior remain distinct
activation gates; never solve them by weakening host AppArmor globally.

## Root integration and rollback

Use the documented operator, not raw System Manager or Home Manager activation.
Registration, live activation, boot linkage, and store retention are separate.
Preserve the exact declared files/services, all required roots/generations,
and the previous candidate throughout a transition.

System Manager's root lane remains frozen independently of user packages.
Preserve its private reviewed Nix runtime, rejection of stale Nix and real
userborn, disabled users/wrappers/global PATH/packages, exact-version
empty-tmpfiles patch, and unmanaged-rule regression test. Version changes
require patch reassessment and current exact test evidence.

The historical pilot has five generations; the generic fresh-host workflow has
two. Never replay spent canary/recovery scripts to satisfy a historical
classifier. Use [the appropriate status route](../../../../docs/operations.md#status-checks).

An idle Nix daemon can be healthy behind its exact listening socket. Parse
whole systemd unit records and diagnose pending reloads rather than clearing
them blindly. Preserve root-test local-store execution, temporary flags, and
user-config isolation; don't change daemon configuration to silence a warning.

## Rollout discipline

Pilot on one ARM64 Spark before additional hosts. Distinguish evaluation, build,
container lifecycle, real activation, application health, and workload
correctness. None is proof of all the others.

Keep factory updates, Nix runtime, package pins, root generations, and workload
activation as separate changes with their own rollback. Devbox does not own Nix
maintenance; lazydocker does not grant Docker-group membership.

Prefer one memory-heavy GPU workload per node until coexistence is validated.
Multi-node links, QSFP topology, NCCL, and additional SSH infrastructure require
their own design; they are not incidental application-install steps.
