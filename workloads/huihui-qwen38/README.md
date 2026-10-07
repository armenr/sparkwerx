# Huihui Qwen3.8 27B on spark-9667

The owner selected this model after completing workstation setup. This separate
Docker workload retains factory NVIDIA drivers/CUDA and the existing desktop.
Model files remain in the owner's Hugging Face cache, outside Git and Nix.

## Exact inputs

- Model: `huihui-ai/Huihui-Qwen3.8-27B-abliterated`, revision
  `739e3c5b89849f6c238ce1e5b70008612ae42cdd`, BF16, approximately 55.6 GB.
- Image source tag when downloaded: `vllm/vllm-openai:latest`.
- Multi-platform digest:
  `sha256:8a69ffad015f138d7170c4ddc429e230a3bc1c1719f67e14324749df200a4b90`.
- Selected linux/arm64 digest:
  `sha256:4864d46625cbc3307623e29ac742030655e27249feba7b97ec925ce4cc4dfb56`.
- Observed image versions: vLLM 0.30.0, Transformers 5.17.0,
  PyTorch 2.13.0+cu130, CUDA 13.0.
- NVIDIA playbook source:
  [vLLM instructions at b9b14c4](https://github.com/NVIDIA/dgx-spark-playbooks/blob/b9b14c44352154a0d2cc49655bb226e1895e17bf/nvidia/vllm/README.md).

The image passed a CUDA matrix calculation on GB10 with host driver 580.178.04.
The pinned model uses `Qwen3_5ForConditionalGeneration`, a 262,144-token native
limit, and XML tool calls. The selected parsers are `qwen3_xml` for tools and
`qwen3` for reasoning. Those registrations were inspected in the exact image.

## Serving and access

The starting configuration requests 131,072 tokens, one active sequence, an
8,192-token prefill batch, and a 70% GPU-memory budget. Memory is shared with
the OS/desktop; the context setting does not establish long-context quality
or guarantee a particular inference speed. Startup and inference results are
recorded in [the live validation](VALIDATION.md).

Docker publishes port 8000 only on loopback, the selected private LAN IPv4,
and the node's Tailscale IPv4. Its generated port mappings are scoped to those
destination addresses. There is no host wildcard or IPv6 publication.
The container itself listens on its internal interfaces. No router forwarding,
Tailscale Funnel, VPN preference change, or host service restart is performed.

The private configuration directory is
`~/.config/sparkwerx/huihui-qwen38`, mode 0700. Its files have mode 0600:

- `network.env`: `SPARK_LAN_IP` and `SPARK_TAILSCALE_IP` for Compose.
- `api.env`: randomly generated `VLLM_API_KEY`, never committed or printed by
  the setup/check scripts. Configure the client's bearer token from this file.

On the Spark, from the checkout:

```bash
python3 workloads/huihui-qwen38/prepare.py
docker compose --env-file ~/.config/sparkwerx/huihui-qwen38/network.env \
  -f workloads/huihui-qwen38/compose.yaml up -d
docker logs --tail 100 -f huihui-qwen38
```

Preparation verifies the host, private addresses, and downloaded weight shards.
It preserves an existing API key and refuses changed bindings for review.
Validate the running API with the external credential (never echoed):

```bash
python3 workloads/huihui-qwen38/probe.py --thinking
```

The probe checks authentication, ten tool calls across JSON and streaming,
escaped URLs, a synthetic tool-result round trip, a no-tool response, and
optionally thinking-enabled tool extraction. It does not execute a web fetch.

Clients use `http://<private-address>:8000/v1` for OpenAI-compatible requests,
the exact model identifier above, and the API key. A local SSH tunnel may also
forward a workstation port to `127.0.0.1:8000` on the Spark. Do not paste the
credential into Git, a public issue, or a shared transcript.

## Stop, restart, and retained state

From any directory on the Spark:

```bash
vllm_stop
```

This global workstation command stops all local containers using official
Docker Hub/NGC vLLM images, plus custom containers labeled
`io.sparkwerx.workload=vllm`. It interrupts active requests, stops the model
workers, and verifies no matching containers remain running. It retains
containers, downloaded weights, images, and caches. Repeating it is harmless.
It uses the local Docker socket, irrespective of any remote Docker context.
Native vLLM processes and other model runtimes are outside its scope.

The branch's newer Nix wrapper also coordinates with the optional
[GPUStack trial](../gpustack/README.md): configured vLLM deployments are scaled
to zero before standalone containers are stopped. If that management API is
unavailable, shutdown returns an error before touching standalone containers.
This integration requires activating the new workstation candidate; the
previously installed standalone command does not acquire it merely from a Git pull.

Docker gets 15 seconds for shutdown before terminating a stuck container.
The command does not change restart policies or external service managers;
this workload's policy remains `restart: "no"`.

To control this one model independently:

```bash
docker stop huihui-qwen38
docker start huihui-qwen38
```

Automatic restart is disabled during initial validation. Stopping releases
model memory; it does not remove weights or compilation caches. The Hugging
Face cache is mounted read-only, and compilation caches use named Docker
volumes. Compose down without `--volumes` removes the service/network while
retaining those caches. This first workload has no previous model deployment;
its initial recovery action is to stop it. Preserve this Compose revision and
image before later changes.

Tool calls are requests for the client to execute a function. A valid JSON
call alone does not establish safe or reliable agent behavior. Test actual
tool-result round trips, streaming, no-tool responses, and representative
contexts before connecting an unattended agent.
