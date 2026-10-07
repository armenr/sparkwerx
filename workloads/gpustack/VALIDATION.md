# GPUStack trial evidence — 2026-09-25

Host: deadspark workstation spark-9667, factory GNOME retained.

- Official GPUStack 2.2.3 ARM64 image pulled by the child digest in source.json.
- Nix built the control command and exact-release worker/collector adapters.
- Container detector found GB10, CUDA 13.0, compute capability 12.1.
- GPUStack server reports v2.2.3 / 1cfcbbf and passes readiness.
- UI and version endpoint return 200 over Tailscale from the client computer;
  unauthenticated `/v2/workers` returns 401.
- Worker is ready in cluster spark-9667. Worker listener is 127.0.0.1:10150;
  UI publications are explicit loopback and Tailscale addresses only.
- Corrected collector reports unified memory and 130660909056 bytes of
  physical memory for both system and GPU pool. Factory services stay active.
- An initial collector text substitution had incorrect indentation. The worker
  exited; it was corrected using a Nix-built Python transformer that parses the
  output before realization. Subsequent worker startup succeeded.
- Initial separate RAM/VRAM reserves incorrectly added together for unified
  memory. The final reserve is RAM 8 GiB, VRAM 0. The original 90% reservation
  rejection was reproduced and the exact upstream calculation reviewed.
- GPUStack's `/v2/model-evaluations` then returned `compatible: true` with no
  compatibility or scheduling messages for LiquidAI/LFM2.5-8B-A1B and
  Qwen/Qwen3.6-27B using vLLM 0.30.0-custom at 90%, one sequence.
  Each predicted reservation was 117594818150 bytes. Model instance count: 0.
- An empty managed-model stop operation succeeded. Unit checks cover private
  bindings, credential retention/permissions, public-address rejection,
  deployment scaling before waiting, and management API failures.

No new model weights were downloaded and no inference model was started.
The owner explicitly reserved model-launch decisions for the UI. GPUStack GPU
inference, throughput, loaded-model stop/restart, full-context behavior, and
physical-host reboot are therefore not validated by this trial. The earlier
standalone vLLM evidence does not prove GPUStack's complete serving path.
