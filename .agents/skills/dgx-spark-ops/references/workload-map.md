# DGX Spark workload map

## Packaging decision

Use the smallest ownership model that preserves NVIDIA's validated GPU stack:

1. Start with the current workload entry in the official DGX Spark playbooks.
2. Prefer a pinned container when CUDA, Python, PyTorch, or framework versions
   are tightly coupled.
3. Use Nix for Compose generation, configuration, CLI clients, wrappers,
   development shells, health checks, and source pins.
4. Consider a native Nix build only when ARM64 support is sound and it consumes
   the DGX OS driver interface without replacing the vendor CUDA/driver layer.
5. Keep models and all writable application state in reviewed persistent paths.

A container is isolation and dependency packaging, not a substitute for a pin.
Record both the readable source tag and the resolved `linux/arm64` digest.

## Workload recommendations

| Goal | First implementation | Persistent state | Important gate |
| --- | --- | --- | --- |
| Private chat: Ollama + Open WebUI | Pinned Compose stack derived from NVIDIA's `open-webui` playbook | Ollama models and Open WebUI database/uploads | GPU visibility, model fit, authentication, backup |
| Friendly desktop model manager: LM Studio | Armen graphical overlay using a current pinned ARM64 package | Models and application settings | Keep separate from headless `llmster`; exact unfree exception and GB10 validation |
| OpenAI-compatible serving: vLLM | NVIDIA-validated vLLM container | Model cache and server logs | Model architecture support, memory budget, API health |
| OpenAI-compatible serving: SGLang | NVIDIA-validated SGLang container | Model cache and server logs | Model support, attention backend, memory budget |
| Broad GGUF support: llama.cpp | NVIDIA playbook; use a pinned source build in a Nix dev shell or a pinned container | GGUF models and logs | CUDA build flags, performance, API compatibility |
| Local coding assistant | Nix-managed coding CLI pointed at an Ollama, vLLM, SGLang, or llama.cpp endpoint | CLI config outside Git; endpoint model cache | Secret handling, API compatibility, context length |
| Images/video: ComfyUI | Pinned container/Compose definition from the NVIDIA playbook | Models, custom nodes, workflows, input/output | Custom-node provenance, VRAM, backup |
| Fine-tuning: Unsloth | NVIDIA-validated container/playbook | Datasets, caches, adapters, checkpoints, logs | Supported model, precision, checkpoint recovery |
| Fine-tuning: LLaMA Factory | NVIDIA-validated container/playbook | Datasets, caches, adapters, checkpoints, logs | Dependency matrix and reproducible job config |
| Fine-tuning: NeMo | NVIDIA NGC container and Spark playbook | Datasets, checkpoints, experiment logs | Image entitlement, framework compatibility, storage |
| Private RAG | AI Workbench recipe or a pinned container stack | Documents, embeddings, vector database, app database | Data boundary, backup, embedding/model migration |
| GPU data science: RAPIDS | NVIDIA NGC RAPIDS container from `cuda-x-data-science` | Notebooks, datasets, caches | RAPIDS/CUDA matrix and dataset memory |
| Robotics/simulation: Isaac | Dedicated source-build role pinned to NVIDIA's current `isaac` playbook | Build tree, assets, projects, caches, results | At least 50 GB before project/model data; display/headless validation; source/LFS/toolchain pins |
| Monitoring | DGX Dashboard first; later pinned exporters plus Prometheus/Grafana | Metrics database and dashboards | Cardinality, retention, credentials, GPU metrics |
| Multi-Spark | NVIDIA Sync/cluster guidance, NCCL tests, explicit topology config | Shared artifacts and test records | Network topology, SSH trust, NCCL validation, failure isolation |

## Current selected and excluded scope

- SELECTED: LM Studio desktop in Armen's graphical overlay.
- OPEN: headless LM Studio `llmster` as a separately controlled serving
  workload; the desktop selection does not authorize it.
- SELECTED: Isaac Sim, Isaac Lab, and Omniverse robotics/simulation tooling in
  an `isaac-omniverse` workload role. Start with Isaac's required components;
  enumerate every additional Omniverse app or Kit component independently.
- NOT SELECTED: NIM and NVIDIA AI Enterprise. Do not scaffold them merely
  because they appear beside selected products in NVIDIA's catalog.
- NOT SELECTED: VS Code. Coding workflows should use Zed or a separately
  selected terminal tool.

## Deployment rules

- Default to one memory-heavy GPU service per Spark. Use Compose profiles or
  host roles so vLLM, SGLang, training, ComfyUI, and Isaac do not all start by
  accident.
- Bind service APIs to loopback unless network exposure is explicitly required.
  Add authentication and a reviewed firewall rule before LAN exposure.
- Define health checks that prove application readiness, not merely that the
  container process exists.
- Pin the DGX playbook commit, every image digest, Dockerfile base, downloaded
  source archive, model revision where possible, and custom plugin/node source.
- Preserve the previous Compose definition and image digest for rollback.
- Never put Hugging Face, NGC, OpenAI, or application credentials in Nix store
  derivations, Compose files, command history, logs, or Git.
- Do not download a model during Nix evaluation or bake licensed/private model
  weights into the Nix store.
- Record ports, expected GPU memory, storage paths, health endpoint, and
  backup/restore notes beside each workload definition.

## Suggested repository shape

Create this structure only as workloads are actually approved:

```text
workloads/
  <workload>/
    README.md              Source, pin, ports, storage, validation, rollback
    compose.yaml           Generated or declarative service definition
    config/                Non-secret application configuration
hosts/
  <hostname>/
    roles.nix              Workloads selected for that host
```

Put secrets in the external secret system and mutable data outside the
repository. A future reviewed convention may use `/srv/dgx/<workload>/`, but
do not create or mount it merely while scaffolding configuration.

## Workload acceptance gates

Before declaring a workload ready:

1. Trace it to the exact NVIDIA playbook commit and upstream release/image.
2. Confirm a `linux/arm64` image or successful native `aarch64-linux` build.
3. Confirm the container sees the GPU without changing the host driver stack.
4. Run a minimal representative inference, render, training step, query, or
   NCCL test.
5. Measure idle and peak memory and ensure another role cannot auto-start into
   resource contention.
6. Restart the service and verify persistent data survives.
7. Exercise the documented stop and rollback path.
8. Confirm GNOME and the host remain usable independently of the workload.
