# GPUStack trial on spark-9667

The owner selected GPUStack's browser model manager and explicitly requested
Nix for this trial. Nix owns the control program and immutable configuration;
GPUStack and GPU inference run in pinned ARM64 containers on factory Docker.
No host Python installer, driver replacement, desktop change, or Tailscale
migration is part of this workload.

The trial pins release 2.2.3, audited on 2026-09-25. Exact registry
metadata is in `source.json`: the ARM64 image is about 1.49 GB compressed.
Allow several GB for extracted application layers and databases, separately
from model weights. The existing Hugging Face cache is retained outside Git
and the Nix store. GPUStack is Apache-2.0; no new Nix unfree exception applies.

The private trial uses separate server and worker state. Management publishes
only explicit loopback/Tailscale bindings. Credentials remain private runtime
files. Containers have no automatic boot startup during the trial. NVIDIA
continues to own the driver, CUDA, Docker and Container Toolkit. Deployment
configuration, device detection, backend compatibility, model start/stop,
and resource release must pass on the real ARM64 host before readiness is
claimed. Upstream GPUStack is not an NVIDIA Spark playbook; its compatibility
is evaluated independently, using the already verified vLLM image where useful.

Rollback stops this workload's managed models through GPUStack, then stops its
worker and server. Preserve its data, the previous vLLM Compose workload,
images, model cache, and Nix generations. Do not delete volumes or reinstall
the OS. Back up the stopped server database volume before future upgrades;
changing the image digest alone may not undo database schema migrations.

## Controls and login

This branch declares `gpustack-spark` in the workstation Nix profile. Once that
candidate is built and activated through the workstation operator, run it as
`deadspark` on the Spark, without sudo:

```bash
gpustack-spark status
gpustack-spark password
gpustack-spark stop-models
```

`password` displays the generated initial admin password only to an interactive
terminal. The username is `admin`; change the password in GPUStack after login.
The control command uses a separate management API key, so changing the login
password does not break it. Credentials live under
`~/.config/sparkwerx/gpustack/` with private permissions, never in Nix or Git.
The UI is at `http://spark-9667:8090` over Tailscale/MagicDNS. Loopback has the
same port for local controls. There is no public or wildcard UI binding.

The explicit lifecycle commands are `up` (server), `initialize` (register/start
worker), and `down` (stop managed deployments, then server and worker).
`configure-models` seeds the selected stopped profile and sets the reviewed
vLLM backend; it does not load weights. Subsequent model-profile UI edits are
preserved. Do not rerun it as routine startup: it reapplies backend defaults.
`vllm_stop` first scales GPUStack vLLM deployments to zero and waits for their
instances to disappear, then handles standalone vLLM containers. A management
API failure returns an error rather than killing containers behind an active
scheduler and reporting false success.

If management credentials exist but GPUStack is offline, `vllm_stop` deliberately
fails before stopping standalone containers: it cannot update the scheduler's
desired state. It is not an offline emergency kill command. `stop-models` stops
all GPUStack backends by default; `--vllm-only` restricts it to vLLM deployments.

As of the 2026-10-07 read-only inspection, the live user profile still supplied
the earlier standalone `vllm_stop`, without `gpustack-spark`. The trial used a
separately built temporary control output. Publication does not activate this
integration or restart the trial. Retaining its control output under a durable
Nix root and verifying the new global commands remain deployment follow-ups.

The owner explicitly controls model downloads and launches from the UI. The
Qwen preset is created with zero replicas. No automatic launch or model-download
operator is installed. Preview metadata requests do not download model weights.

## Spark-specific adaptations

Two exact-release upstream Python files are fetched by Nix with hashes:

- The worker honors its configured loopback bind address instead of hardcoding
  `0.0.0.0`. Its outbound tunnel connects to the local server; native Tailscale
  and SSH do not change.
- The collector identifies NVIDIA GB10's unified memory and caps its reported
  GPU pool at actual physical system RAM. It keeps live GPU usage telemetry.
  The generated Python is syntax-checked during its Nix build.

The user requested 90% GPU memory utilization. The worker reserves **8 GiB RAM
and 0 GiB additional VRAM** because these are the same physical pool. GPUStack
adds both reserve fields for unified memory; setting both to 8 incorrectly
reserved 16 GiB and rejected 90% allocations. This host reports about 121.69
GiB physical RAM, leaving about 113.69 GiB schedulable after the single reserve.
The actual model memory setting remains 90%, approximately 109.52 GiB.
A successful scheduler preview is not proof that every model/context fits at
runtime. No desktop shutdown is selected.

GPU access uses the factory CDI configuration. GPUStack CDI generation is off;
its runtime helper images and vLLM image are pinned by ARM64 digest. The worker
has Docker socket access to create inference containers. Worker credentials
and the patched module mounts are excluded from inference-container mount
mirroring; only its separate cache and existing model cache are shared.

The runtime state is in named Docker volumes: `spark-gpustack_server-data`,
`spark-gpustack_worker-data`, and `spark-gpustack_worker-cache`. Existing model
weights stay at `~/.cache/huggingface`. These are mutable data, not Nix outputs.
See [validation](VALIDATION.md) for the trial's exact limits.
