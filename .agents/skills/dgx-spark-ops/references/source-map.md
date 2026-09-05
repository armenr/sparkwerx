# Authoritative source map

Use this file as a breadcrumb index, not as cached proof that a component is
current. Open the relevant source during every online audit and cite the page
that supports the current claim.

## Source precedence

For DGX Spark compatibility, use this order:

1. NVIDIA's DGX Spark catalog and the matching playbook.
2. The playbook's exact source commit and referenced NGC artifact.
3. The upstream project's official release notes or tags.
4. Community reports only for diagnosing gaps; never use them alone to approve
   an update.

For Nix configuration, use the official Nix/Nixpkgs/Home Manager source followed
by this repository's lock file and local build evidence.

Do not treat search snippets, mutable branch heads, blog summaries, or a
container registry's `latest` tag as a release decision.

## DGX and workload sources

| Topic | Primary source |
| --- | --- |
| Spark playbook catalog | https://build.nvidia.com/spark |
| Versionable playbook source | https://github.com/NVIDIA/dgx-spark-playbooks |
| Open WebUI with Ollama | https://build.nvidia.com/spark/open-webui |
| vLLM | https://build.nvidia.com/spark/vllm |
| SGLang | https://build.nvidia.com/spark/sglang |
| llama.cpp | https://build.nvidia.com/spark/llama-cpp |
| LM Studio/llmster | https://build.nvidia.com/spark/lm-studio |
| Local CLI coding agents | https://build.nvidia.com/spark/cli-coding-agent |
| ComfyUI | https://build.nvidia.com/spark/comfyui |
| LLaMA Factory | https://build.nvidia.com/spark/llama-factory |
| Unsloth | https://build.nvidia.com/spark/unsloth |
| NeMo fine-tuning | https://build.nvidia.com/spark/nemo-fine-tune |
| AI Workbench RAG | https://build.nvidia.com/spark/rag-ai-workbench |
| RAPIDS/cuDF/cuML | https://build.nvidia.com/spark/cuda-x-data-science |
| Isaac Sim and Isaac Lab | https://build.nvidia.com/spark/isaac |
| NCCL across Sparks | https://build.nvidia.com/spark/nccl |
| Switched multi-Spark topology | https://build.nvidia.com/spark/multi-sparks-through-switch |

When a catalog page exposes tabs, inspect Overview, Instructions,
Troubleshooting, supported hardware/models, prerequisites, rollback, and last
updated date. Follow its source link to the playbook assets instead of copying a
`curl ... main | bash` command.

## Nix and configuration sources

| Topic | Primary source |
| --- | --- |
| Official community installer and Nix upgrade command | https://github.com/NixOS/nix-installer#upgrading-nix |
| Official installer releases and ARM64 assets | https://github.com/NixOS/nix-installer/releases |
| Repository bootstrap source/planner pin | [bootstrap/nix/source.json](../../../../bootstrap/nix/source.json) |
| Declarative fleet host selections | [fleet/hosts.json](../../../../fleet/hosts.json) |
| Read-only fleet planner | [scripts/dgx-setup](../../../../scripts/dgx-setup) |
| Guarded Nix install/adoption implementation | [scripts/bootstrap-nix.sh](../../../../scripts/bootstrap-nix.sh) |
| Receipt-driven fresh-install rollback | [scripts/rollback-fresh-nix-bootstrap.sh](../../../../scripts/rollback-fresh-nix-bootstrap.sh) |
| Root-assisted disposable bootstrap lifecycle | [scripts/test-nix-bootstrap-lifecycle.sh](../../../../scripts/test-nix-bootstrap-lifecycle.sh) |
| Exact bootstrap lifecycle PASS | [docs/2026-09-03-nix-bootstrap-lifecycle.md](../../../../docs/2026-09-03-nix-bootstrap-lifecycle.md) |
| Fleet-plan implementation evidence | [docs/2026-09-03-fleet-plan.md](../../../../docs/2026-09-03-fleet-plan.md) |
| `nix upgrade-nix` behavior | https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-upgrade-nix.html |
| Nix 2.35.1 `upgrade-nix` implementation | https://github.com/NixOS/nix/blob/2.35.1/src/nix/upgrade-nix.cc |
| Linux multi-user upgrade/restart procedure | https://nix.dev/manual/nix/latest/installation/upgrading.html |
| Default stable-binary pointer used by `upgrade-nix` | https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/tools/nix-fallback-paths.nix |
| Nix releases | https://github.com/NixOS/nix/releases |
| Nix 2.35.2 ARM64 release artifact | https://releases.nixos.org/nix/nix-2.35.2/nix-2.35.2-aarch64-linux.tar.xz |
| Official Nix 2.35.2 release flake | https://github.com/NixOS/nix/tree/2.35.2 |
| Repository Nix diagnosis and custom candidate | [root/nix/README.md](../../../../root/nix/README.md) |
| Stable Nixpkgs branch | https://github.com/NixOS/nixpkgs/tree/nixos-26.05 |
| Matching Home Manager branch | https://github.com/nix-community/home-manager/tree/release-26.05 |
| Hyprland releases | https://github.com/hyprwm/Hyprland/releases |
| Hyprland v0.56.2 Glaze packaging fix | https://github.com/hyprwm/Hyprland/commit/91f29f23bb691462f8aa6171b964069aebc37910 |
| Official Codex CLI install/update guidance | https://developers.openai.com/codex/cli/ |
| Codex stable release metadata | https://releases.openai.com/codex/channels/latest |
| Official Codex configuration reference | https://learn.chatgpt.com/docs/config-file/config-reference |
| Current Codex package/build evidence | [docs/2026-09-03-codex-cli-package.md](../../../../docs/2026-09-03-codex-cli-package.md) |
| System Manager matching stable branch | https://github.com/numtide/system-manager/tree/release-26.05 |
| Repository System Manager canary/runbook | [root/system-manager/README.md](../../../../root/system-manager/README.md) |
| Exact current System Manager container-test evidence | [root/system-manager/validation/2026-08-24-container-test.md](../../../../root/system-manager/validation/2026-08-24-container-test.md) |
| Original retained System Manager host-canary evidence | [root/system-manager/validation/2026-09-01-host-canary-attempt-3.md](../../../../root/system-manager/validation/2026-09-01-host-canary-attempt-3.md) |
| Historical retained registered/live generation-one authority | [root/system-manager/validation/2026-09-01-first-registration-host-attempt-3.md](../../../../root/system-manager/validation/2026-09-01-first-registration-host-attempt-3.md) |
| System Manager registration lifecycle design | [root/system-manager/validation/2026-09-01-registration-test-plan.md](../../../../root/system-manager/validation/2026-09-01-registration-test-plan.md) |
| Exact System Manager registration-test result | [root/system-manager/validation/2026-09-01-registration-container-test.md](../../../../root/system-manager/validation/2026-09-01-registration-container-test.md) |
| Guarded first-registration transaction result | [root/system-manager/validation/2026-09-01-first-registration-transaction-container-test.md](../../../../root/system-manager/validation/2026-09-01-first-registration-transaction-container-test.md) |
| Guarded generation-switch transaction plan | [root/system-manager/validation/2026-09-02-generation-switch-transaction-plan.md](../../../../root/system-manager/validation/2026-09-02-generation-switch-transaction-plan.md) |
| Exact guarded generation-switch transaction result | [root/system-manager/validation/2026-09-02-generation-switch-transaction-container-test.md](../../../../root/system-manager/validation/2026-09-02-generation-switch-transaction-container-test.md) |
| Guarded generation-switch live plan (executed, retained) | [root/system-manager/validation/2026-09-02-generation-switch-live-plan.md](../../../../root/system-manager/validation/2026-09-02-generation-switch-live-plan.md) |
| Historical retained registered/live generation-two authority | [root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md](../../../../root/system-manager/validation/2026-09-02-generation-switch-host-attempt-1.md) |
| Guarded boot-persistence transaction plan | [root/system-manager/validation/2026-09-02-boot-persistence-transaction-plan.md](../../../../root/system-manager/validation/2026-09-02-boot-persistence-transaction-plan.md) |
| Exact guarded boot-persistence transaction result | [root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md](../../../../root/system-manager/validation/2026-09-02-boot-persistence-transaction-container-test.md) |
| Guarded boot-persistence live plan (executed, retained) | [root/system-manager/validation/2026-09-02-boot-persistence-live-plan.md](../../../../root/system-manager/validation/2026-09-02-boot-persistence-live-plan.md) |
| Historical retained registered/live generation-three authority | [root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md](../../../../root/system-manager/validation/2026-09-02-boot-persistence-host-attempt-1.md) |
| Persistent first-reboot recovery transaction plan | [root/system-manager/validation/2026-09-02-reboot-recovery-transaction-plan.md](../../../../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-plan.md) |
| Exact persistent first-reboot recovery lifecycle result | [root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md](../../../../root/system-manager/validation/2026-09-02-reboot-recovery-transaction-container-test.md) |
| Executed persistent first-reboot live lifecycle plan | [root/system-manager/validation/2026-09-03-reboot-recovery-live-plan.md](../../../../root/system-manager/validation/2026-09-03-reboot-recovery-live-plan.md) |
| Verified first-reboot automatic-rollback authority | [root/system-manager/validation/2026-09-03-reboot-recovery-host-attempt-1.md](../../../../root/system-manager/validation/2026-09-03-reboot-recovery-host-attempt-1.md) |
| Historical restoration-attempt rollback authority | [root/system-manager/validation/2026-09-03-restoration-host-attempt-1.md](../../../../root/system-manager/validation/2026-09-03-restoration-host-attempt-1.md) |
| Current successful generation-three restoration authority | [root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md](../../../../root/system-manager/validation/2026-09-03-restoration-host-attempt-2.md) |
| Frozen root dependency-lane identity proof | [root/system-manager/validation/2026-09-03-root-dependency-lane.md](../../../../root/system-manager/validation/2026-09-03-root-dependency-lane.md) |
| Short no-reboot recovery operator | [scripts/dgx-recovery](../../../../scripts/dgx-recovery) |
| Guarded generation-three restoration helper | [scripts/root-recovery-restore-generation-three.sh](../../../../scripts/root-recovery-restore-generation-three.sh) |
| Thunderbird Snap unit-graph reload disposition | [root/system-manager/validation/2026-09-03-thunderbird-unit-graph-reload.md](../../../../root/system-manager/validation/2026-09-03-thunderbird-unit-graph-reload.md) |
| Sanitized retained-canary classifier | [scripts/audit-root-canary-state.sh](../../../../scripts/audit-root-canary-state.sh) |
| Repository empty-tmpfiles safety patch | [patches/system-manager/skip-empty-tmpfiles.patch](../../../../patches/system-manager/skip-empty-tmpfiles.patch) |
| Narrow fast-moving apps branch | https://github.com/NixOS/nixpkgs/tree/nixpkgs-unstable |

Branches in this table match the repository's current policy. If the repository
moves to a later stable release, update both `flake.nix` and this source map in
the same reviewed change.

## Desktop and personal-application sources

| Topic | Primary source |
| --- | --- |
| Accepted selections and exclusions | [decision register](../../../../docs/decision-register.md) |
| Pre-install package evidence | [software manifest](../../../../docs/software-manifest.md) |
| Desktop-mode behavior | [desktop modes](../../../../docs/desktop-modes.md) |
| Armen overlay boundaries | [user overlays](../../../../docs/user-overlays.md) |
| Ghostty stable releases | https://ghostty.org/docs/install/release-notes |
| Ghostty packaging guidance | https://github.com/ghostty-org/ghostty/blob/main/PACKAGING.md |
| ncdu releases | https://dev.yorhel.nl/ncdu |
| lazydocker releases | https://github.com/jesseduffield/lazydocker/releases |
| Devbox releases | https://github.com/jetify-com/devbox/releases |
| Repository Devbox source/vendor pin | [packages/devbox/source.json](../../../../packages/devbox/source.json) |
| Zed Linux/ARM64 requirements | https://zed.dev/docs/linux |
| Zed releases | https://github.com/zed-industries/zed/releases |
| Repository Zed pin and updater | [packages/zed-editor/source.json](../../../../packages/zed-editor/source.json), [scripts/update-zed.sh](../../../../scripts/update-zed.sh) |
| Current Zed package evidence | [docs/2026-09-03-zed-package.md](../../../../docs/2026-09-03-zed-package.md) |
| LM Studio desktop download/release | https://lmstudio.ai/download |
| LM Studio/llmster on Spark | https://build.nvidia.com/spark/lm-studio |
| Repository LM Studio pin and updater | [packages/lmstudio/source.json](../../../../packages/lmstudio/source.json), [scripts/update-lmstudio.sh](../../../../scripts/update-lmstudio.sh) |
| Current LM Studio package evidence | [docs/2026-09-03-lmstudio-package.md](../../../../docs/2026-09-03-lmstudio-package.md) |
| Chromium release dashboard | https://chromiumdash.appspot.com/releases?platform=Linux |
| Chromium Ubuntu AppArmor/userns guidance | https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md |
| Locked Nixpkgs Chromium SUID module | https://github.com/NixOS/nixpkgs/blob/9387b3fcc0c23c86661636da63faabad4235a0a6/nixos/modules/security/chromium-suid-sandbox.nix |
| Current Chromium package evidence | [docs/2026-09-03-chromium-package.md](../../../../docs/2026-09-03-chromium-package.md) |
| First headless Home activation preflight | [docs/2026-09-03-home-headless-preflight.md](../../../../docs/2026-09-03-home-headless-preflight.md) |
| Retained headless Home host result | [docs/2026-09-03-home-headless-host.md](../../../../docs/2026-09-03-home-headless-host.md) |
| Guarded later-generation Home lifecycle | [docs/2026-09-03-home-headless-update-lifecycle.md](../../../../docs/2026-09-03-home-headless-update-lifecycle.md) |
| Guarded Home operator | [scripts/dgx-home](../../../../scripts/dgx-home) |
| Isaac Sim/Lab on Spark | https://build.nvidia.com/spark/isaac |

The repository lock is packaging evidence, not proof that a desktop package is
current. Compare it with the vendor source on every package proposal. Keep LM
Studio desktop separate from `llmster`. Start Omniverse validation with the
pinned Isaac build, then itemize each additionally selected robotics app or Kit
component. Do not follow adjacent VS Code, NIM, or AI Enterprise catalog entries
unless the decision register changes.

## Tailscale and fleet-access sources

| Topic | Primary source |
| --- | --- |
| Stable package artifacts and checksum convention | https://pkgs.tailscale.com/stable/ |
| Release changelog | https://tailscale.com/changelog |
| Security bulletins | https://tailscale.com/security-bulletins |
| Tailscale SSH behavior and limitations | https://tailscale.com/docs/features/tailscale-ssh |
| Security best practices | https://tailscale.com/docs/reference/best-practices/security |
| Upstream source and developer flake caveat | https://github.com/tailscale/tailscale/blob/main/flake.nix |
| Repository package and unit policy | [Tailscale operations reference](tailscale.md) |
| Guarded live migration operator | [scripts/dgx-tailscale](../../../../scripts/dgx-tailscale) |
| Exact migration transaction | [scripts/root-tailscale-migration-transaction.sh](../../../../scripts/root-tailscale-migration-transaction.sh) |
| Persistent rollback bundle | [root/tailscale/migration-bundle.nix](../../../../root/tailscale/migration-bundle.nix) |
| Current disposable migration proof | [root/tailscale/validation/2026-09-05-migration-lifecycle-container-test.md](../../../../root/tailscale/validation/2026-09-05-migration-lifecycle-container-test.md) |

Use `tailscale version --json --upstream --track stable` as a machine-readable
official availability check, then confirm meaningful changes in the changelog
and security bulletins. The stable package page publishes architecture-specific
artifacts and explains its checksum URLs.

Do not treat the upstream repository's development flake, a Git branch head, or
an apt cache as the approved fleet package. For a temporary custom derivation,
use the exact stable ARM64 artifact and checksum. Recheck locked
`pkgs.tailscale` first and retire the custom adapter as soon as the stock
package is a validated non-downgrade.

Never capture unfiltered local status/preferences or tailnet policy while
following these sources.

## Container sources

Use the image source specified by the current NVIDIA playbook. For NVIDIA images,
verify the tag in NGC. For GHCR or Docker Hub images, verify against the
upstream project's official package/release page.

For every image record:

- registry/repository;
- readable source tag;
- architecture (`linux/arm64`);
- immutable manifest digest;
- playbook commit or upstream release that selected it;
- date and command used to resolve the digest.

A multi-architecture index digest and its ARM64 child-manifest digest are not
interchangeable. Record which one Compose actually pulls and compare like with
like.

Do not pull an image merely to check whether its digest changed. Prefer a
registry-inspection tool. Authentication may be required for NGC; never print
the token or persist it in the repository.

## Update breadcrumbs

For any component:

1. Record the local installed/pinned value before browsing.
2. Open the primary source above.
3. Identify the latest published candidate and its release/update date.
4. Read compatibility, architecture, CUDA/driver, and migration notes.
5. Follow the exact artifact or source link and resolve an immutable revision.
6. Compare candidate versus pin without changing the pin.
7. Classify it as current, available-but-unvalidated, incompatible/hold,
   manually managed, or unknown.
8. Only after explicit approval, change the pin and run the relevant validation
   gate.

Availability is not applicability. Applicability is not successful validation.
Successful validation is not authorization to activate.
