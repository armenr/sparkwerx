# Maintainer handoff: factory GNOME workstation and model trials

Review target: `feat/deadspark-system-setup`, based on upstream `fd5cf97`.
Prepared 2026-10-07 for review against `armenr/sparkwerx:main`; published through
the `D3adByte/sparkwerx` fork. This document is the entry point for a human or
AI reviewer. Publication is not host deployment or permission to start models.

The branch adds a separate Nix user-package workflow for a factory-GNOME Spark.
It preserves NVIDIA's OS, driver, CUDA, Docker and desktop ownership, and keeps
native Tailscale and OpenSSH in place. Retained package generations provide
package rollback; they are not OS snapshots or application-data backups.

## Review map

| Area | Code and reason | Evidence |
| --- | --- | --- |
| Workstation packages | [operator](../scripts/dgx-workstation), [profile](profiles.nix), [declaration](hosts.json): guided selection, build, review, save, activation and rollback | [contract](README.md), [history](VALIDATION.md), `dev/test_workstation*.py`, `dev/workstation_nix_integration.py` |
| Bootstrap | [separate input root](bootstrap/README.md): installer 2.35.2 and a healthy VPN with optional Tailscale SSH off | `dev/workstation-bootstrap/`, dated native ARM64 lifecycle results in VALIDATION.md |
| Pending edits | `spark finish` and exact candidate checks: preserve unrelated files, identify blockers, reject stale previews | Guided regression tests and September 25 recovery evidence |
| Standalone inference | [pinned workload](../workloads/huihui-qwen38/README.md): private address bindings, external credentials, retained caches, API probes | Its separate VALIDATION.md; tests do not establish every model's agent reliability |
| Model shutdown | [vllm_stop](../scripts/vllm_stop): selected local Docker containers; newer wrapper coordinates with GPUStack first | `dev/test_vllm_stop.py`; manager failures stop the operation before Docker mutation |
| GPUStack trial | [workload](../workloads/gpustack/README.md): pinned ARM64 containers, Nix-built controls, private worker bind, GB10 memory accounting | Its September 25 VALIDATION.md and `dev/test_gpustack.py`; global profile integration remains pending |
| Test cleanup | [runner](../scripts/dev-container): init, deadline, exit/signal cleanup and private source copy | `dev/container_lifecycle.py`; September 28 zombie correction |
| Desktop speech | [user override](speech-dispatcher.conf): keep working speech modules while skipping the failed optional MBROLA backend | September 28 evidence; manually applied to this user, not a fleet default |

Start with [what changed and why](CHANGES.md), then the workstation operator
and its tests. Review the two workloads independently from package setup.
The original pilot's root-generation and headless lifecycle remain separate.
The new `nixpkgs-workstation` input does not advance the existing root, apps,
development, or pilot bootstrap pins. No global unfree exception was added.

## Actual deployment versus code in this branch

Read-only inspection on 2026-10-07 found the Spark checkout clean at `4802336`,
user profile generation 5 active, and no pending recovery journal. That profile
contains `spark` and the earlier standalone `vllm_stop`, but not `gpustack-spark`.
The GPUStack server and worker were running from the earlier trial setup.
Later model deployments chosen by the owner are not frozen into this branch.

The GPUStack trial's Nix profile integration is included in this review
candidate. It is proposed code, not a claim of live
activation. Do not infer current model state from a dated record showing zero
instances. The owner controls model downloads and starts from the UI.

## Known limits and follow-ups

- **nvtop remains unresolved.** `spark install nvtop` selected
  `nvtopPackages.nvidia`, which was rejected by the locked package set's
  `cuda-merged-12.9` unfree dependency. Preserve that guard. A reviewed adapter
  using the factory driver's monitoring library is a possible follow-up, not
  an implemented fix. The failed guided build restored the selection; nvtop is
  absent from the current declaration.
- **GPUStack remains a host-specific trial.** Its account, hostname, home, UID,
  API endpoint and module paths are intentionally specific to this deployment.
  Package presence starts no service. Do not copy these defaults to a second
  host without an explicit adaptation and validation plan.
- **Network claims have a scope.** The trial restricts management UI and worker
  listeners. Its worker uses host networking to orchestrate inference; review
  the listener arguments and exposure of each model created through the UI.
  The saved Qwen preset requests loopback. This is not a blanket network-policy
  guarantee for arbitrary later models.
- **Serving evidence is separate.** Scheduler previews and a ready worker do
  not prove model/context fitness, throughput, tool reliability or physical
  reboot recovery. The user subsequently ran Ornith; that is not a repeatable
  test of every model or of the new shutdown integration.
- **Shutdown requires a reachable scheduler when configured.** The new
  `vllm_stop` refuses to claim success if GPUStack's API is unavailable. Native
  processes, arbitrary custom images without the workload label, and other
  external supervisors remain outside its standalone scope.
- **Finish runtime retention during deployment.** Build and activate the new
  user profile through the normal reviewed package lifecycle, retain the trial
  control closure under a durable Nix root, and verify global controls before
  retiring temporary paths. Publishing this branch performs none of those steps.
- **Keep workload data external.** Credentials, downloaded weights, databases,
  caches and private network bindings do not belong in Git or the Nix store.
  Back up GPUStack data before upgrades; a previous image is not a database
  downgrade procedure. No version refresh is part of this publication.

## Validation and reproduction

The dated [workstation evidence](VALIDATION.md) retains the original bootstrap,
profile recovery, PTY, guided install and cleanup results. The workload evidence
records their distinct hardware/API checks. Historical results are not relabeled
as new passes.

Fresh publication checks on 2026-10-07:

- Full `./scripts/dev check` passed in the isolated ARM64 Nix container:
  lint/format, documentation, 99 Python tests (one existing environment skip),
  the systemd whole-record parser regression, and complete flake evaluation
  with `--no-build`. This evaluated lifecycle-test derivations; it did not run
  their host-transition scenarios or activate any profile.
- Implementation is recorded in `4f687a5`, with validation-runner corrections
  in `8172f56` and `847e0ff`. The first runner attempt exposed copied Git
  ownership; private copies now belong to the container user without a global
  Git safety exception. A subsequent run exceeded the 4 GiB cap (confirmed by
  Docker's OOM event); the complete retry passed with 8 GiB.
- The explicit Docker lifecycle regression passed Git access, reaping 30
  deliberately orphaned children, success/failure exit status, deadline and
  SIGTERM cleanup. The test has no GPU or host Docker socket mount.
- Comparison with upstream confirmed existing dependency nodes and original
  root/bootstrap/module/package sources unchanged. The only additional flake
  input is `nixpkgs-workstation`. Scoped credential-pattern and whitespace
  checks passed; generated bytecode remains ignored.
- Final documentation updates were checked separately after the complete run.
  No model was downloaded, started or stopped, and no live profile or service
  was changed during publication validation.

On an authorized ARM64 development host with the pinned workspace available:

```bash
./scripts/dev check
```

With the documented cached Nix Docker image, `./scripts/dev-container` runs the
same check in an isolated container. `python3 dev/container_lifecycle.py` is a
separate explicit Docker test. Neither command activates host packages or starts
models. Follow [development](../docs/development.md) for limits and dependencies.

## Instructions for the next AI reviewer

Read [AGENTS.md](../AGENTS.md) and the [agent guide](../docs/agent-guide.md).
Review the branch diff, exact pins, tests and deployment distinctions above.
Do not run `setup`, `apply`, `converge`, model startup, or service migration
as part of code review. Do not weaken the CUDA/unfree policy to get nvtop past
evaluation. Preserve unrelated user edits and use the current lifecycle's
recovery operator if a real transaction is pending. Merging this branch does
not authorize deployment, OS changes, model downloads, or cleanup of user data.
