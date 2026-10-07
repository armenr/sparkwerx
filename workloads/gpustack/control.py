#!/usr/bin/env python3
"""Control the private GPUStack trial using immutable Nix inputs."""

import argparse
import base64
import ipaddress
import json
import os
import platform
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DOCKER = ["/usr/bin/docker", "--host", "unix:///var/run/docker.sock"]
ROOT = Path.home() / ".config/sparkwerx/gpustack"
URL = "http://127.0.0.1:8090"


def run(*args, capture=True):
    return subprocess.run(args, check=True, text=True, capture_output=capture, timeout=120).stdout


def private_write(path, text):
    if path.is_symlink():
        raise RuntimeError("Refusing redirected runtime file")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(text)
    path.chmod(0o600)


def api(path, data=None, method=None, bootstrap=False):
    token = ROOT / "management.key"
    if token.exists() and not bootstrap:
        auth = "Bearer " + token.read_text().strip()
    else:
        password = (ROOT / "admin.password").read_text().strip()
        auth = "Basic " + base64.b64encode(("admin:" + password).encode()).decode()
    request = urllib.request.Request(
        URL + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Authorization": auth, "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as error:
        # Response bodies can contain credentials or private inventory.
        raise RuntimeError(f"GPUStack API {path}: HTTP {error.code}") from None


def compose(*args):
    run(*DOCKER, "compose", "-f", str(ROOT / "compose.json"), *args, capture=False)


def prepare():
    for parent in [ROOT.parent.parent, ROOT.parent, ROOT]:
        if parent.is_symlink():
            raise RuntimeError("Refusing redirected runtime directory")
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    ROOT.chmod(0o700)
    pin = json.loads(Path(os.environ["SPARK_GPUSTACK_PIN"]).read_text())
    image = "gpustack/gpustack@" + pin["arm64Digest"]
    tail = run("/usr/bin/tailscale", "ip", "-4").strip()
    if ipaddress.ip_address(tail) not in ipaddress.ip_network("100.64.0.0/10"):
        raise RuntimeError("Expected a live Tailscale IPv4 address")
    network = ROOT / "network.json"
    if network.exists() and json.loads(network.read_text()) != {"tail": tail}:
        raise RuntimeError("Tailscale address changed; review the previous binding first")
    private_write(network, json.dumps({"tail": tail}))
    password = ROOT / "admin.password"
    if not password.exists():
        private_write(password, secrets.token_urlsafe(32) + "\n")
    private_write(
        ROOT / "server.env", "GPUSTACK_BOOTSTRAP_PASSWORD=" + password.read_text().strip() + "\n"
    )
    service = {
        "image": image,
        "platform": "linux/arm64",
        "pull_policy": "never",
        "restart": "no",
        "logging": {"driver": "json-file", "options": {"max-size": "20m", "max-file": "3"}},
        "ulimits": {"nofile": {"soft": 65535, "hard": 65535}},
    }
    server = {
        **service,
        "container_name": "spark-gpustack-server",
        "ports": ["127.0.0.1:8090:80", f"{tail}:8090:80"],
        "env_file": [str(ROOT / "server.env")],
        "environment": {"GPUSTACK_DISABLE_UPDATE_CHECK": "true"},
        "volumes": ["server-data:/var/lib/gpustack"],
        "healthcheck": {
            "test": [
                "CMD",
                "python3",
                "-c",
                "import urllib.request; urllib.request.urlopen('http://127.0.0.1/readyz', timeout=5)",
            ],
            "interval": "15s",
            "timeout": "10s",
            "start_period": "3m",
            "retries": 5,
        },
    }
    document = {
        "name": "spark-gpustack",
        "services": {"server": server},
        "volumes": {"server-data": {}, "worker-data": {}, "worker-cache": {}},
    }
    if (ROOT / "worker.env").exists():
        worker = {
            **service,
            "container_name": "spark-gpustack-worker",
            "network_mode": "host",
            "devices": ["nvidia.com/gpu=all"],
            "env_file": [str(ROOT / "worker.env")],
            "environment": {
                "GPUSTACK_SERVER_URL": URL,
                "GPUSTACK_WORKER_IP": "127.0.0.1",
                "GPUSTACK_WORKER_IFNAME": "lo",
                "GPUSTACK_WORKER_NAME": "spark-9667",
                "GPUSTACK_HOST": "127.0.0.1",
                "GPUSTACK_DISABLE_WORKER_METRICS": "true",
                "GPUSTACK_PROXY_MODE": "tunnel",
                "GPUSTACK_SYSTEM_RESERVED": '{"ram":8,"vram":0}',
                "GPUSTACK_RUNTIME_DOCKER_RESOURCE_INJECTION_POLICY": "CDI",
                "GPUSTACK_RUNTIME_DOCKER_CDI_SPECS_GENERATE": "false",
                "GPUSTACK_RUNTIME_DOCKER_PAUSE_IMAGE": "gpustack/runtime@"
                + pin["runtimeImages"]["pause"]["arm64Digest"],
                "GPUSTACK_RUNTIME_DOCKER_UNHEALTHY_RESTART_IMAGE": "gpustack/runtime@"
                + pin["runtimeImages"]["health"]["arm64Digest"],
                "GPUSTACK_RUNTIME_DEPLOY_MIRRORED_NAME": "spark-gpustack-worker",
                "GPUSTACK_RUNTIME_DEPLOY_MIRRORED_DEPLOYMENT_IGNORE_VOLUMES": "/private-worker.py;/private-collector.py;/var/lib/gpustack",
                "HF_HUB_DISABLE_TELEMETRY": "1",
            },
            "volumes": [
                "worker-data:/var/lib/gpustack",
                "worker-cache:/var/lib/gpustack/cache",
                "/var/run/docker.sock:/var/run/docker.sock",
                f"{Path.home()}/.cache/huggingface:{Path.home()}/.cache/huggingface:ro",
                f"{os.environ['SPARK_GPUSTACK_WORKER']}:/private-worker.py:ro",
                f"{os.environ['SPARK_GPUSTACK_COLLECTOR']}:/private-collector.py:ro",
            ],
            "entrypoint": [
                "/bin/sh",
                "-ec",
                "cp /private-worker.py /usr/local/lib/python3.11/dist-packages/gpustack/worker/worker.py; cp /private-collector.py /usr/local/lib/python3.11/dist-packages/gpustack/worker/collector.py; exec /usr/bin/entrypoint.sh",
            ],
        }
        document["services"]["worker"] = worker
    private_write(ROOT / "compose.json", json.dumps(document, indent=2) + "\n")
    compose("config", "--quiet")


def initialize():
    if not (ROOT / "management.key").exists():
        key = api(
            "/v2/api-keys",
            {"name": "spark-local-management", "scope": ["management"]},
            bootstrap=True,
        )
        private_write(ROOT / "management.key", key["value"] + "\n")
    clusters = api("/v2/clusters")["items"]
    cluster = next((c for c in clusters if c["name"] == "spark-9667"), None)
    if cluster is None:
        cluster = api(
            "/v2/clusters",
            {
                "name": "spark-9667",
                "provider": "Docker",
                "description": "Private Nix-managed DGX Spark trial",
            },
        )
    registration = api(f"/v2/clusters/{cluster['id']}/registration-token")
    private_write(ROOT / "worker.env", "GPUSTACK_TOKEN=" + registration["token"] + "\n")
    prepare()
    compose("up", "-d", "worker")
    deadline = time.monotonic() + 120
    while True:
        workers = api("/v2/workers")["items"]
        if any(w["name"] == "spark-9667" and w["state"] == "ready" for w in workers):
            print("Spark worker ready.")
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("Worker readiness timed out; inspect status before deploying models")
        time.sleep(3)


def configure_models():
    """Seed the selected, stopped profile; preserve subsequent UI edits."""
    pin = json.loads(Path(os.environ["SPARK_GPUSTACK_PIN"]).read_text())
    version = "0.30.0-custom"
    backends = api("/v2/inference-backends")["items"]
    backend = next(b for b in backends if b["backend_name"] == "vLLM")
    configured = dict(backend.get("version_configs") or {})
    configured[version] = {
        "image_name": pin["vllmImage"],
        "entrypoint": "vllm serve",
        "custom_framework": "cuda",
    }
    api(
        f"/v2/inference-backends/{backend['id']}",
        {
            **backend,
            "backend_source": "built_in",
            "default_version": None,
            "version_configs": configured,
            "default_backend_param": ["--gpu-memory-utilization=0.90", "--max-num-seqs=1"],
        },
        "PUT",
    )
    cluster = next(c for c in api("/v2/clusters")["items"] if c["name"] == "spark-9667")
    existing = {m["name"] for m in api("/v2/models?perPage=1000")["items"]}
    presets = json.loads(Path(os.environ["SPARK_GPUSTACK_MODELS"]).read_text())
    for name, model in presets.items():
        if name in existing:
            continue
        params = [
            "--host=127.0.0.1",
            "--dtype=bfloat16",
            "--revision=" + model["revision"],
            "--tokenizer-revision=" + model["revision"],
            "--gpu-memory-utilization=" + model["memoryUtilization"],
            "--max-model-len=" + str(model["contextLength"]),
            "--max-num-seqs=1",
            "--max-num-batched-tokens=8192",
            "--enable-auto-tool-choice",
            "--tool-call-parser=" + model["toolParser"],
            "--reasoning-parser=" + model["reasoningParser"],
        ]
        api(
            "/v2/models",
            {
                "name": name,
                "source": "huggingface",
                "huggingface_repo_id": model["repository"],
                "backend": model["backend"],
                "backend_version": model["backendVersion"],
                "backend_parameters": params,
                "cluster_id": cluster["id"],
                "replicas": 0,
                "restart_on_error": False,
                "cpu_offloading": False,
                "distributed_inference_across_workers": False,
                "env": {"HF_HUB_DISABLE_TELEMETRY": "1", "VLLM_NO_USAGE_STATS": "1"},
            },
        )
        print(f"Saved stopped profile: {name}")


def stop_models(vllm_only=False):
    models = api("/v2/models?perPage=1000")["items"]
    selected = [m for m in models if not vllm_only or m.get("backend") == "vLLM"]
    selected_ids = {m["id"] for m in selected}
    for model in selected:
        if model.get("replicas", 0):
            api(f"/v2/models/{model['id']}", {**model, "replicas": 0}, "PUT")
            print(f"Stopped deployment: {model['name']}")
    deadline = time.monotonic() + 90
    while any(
        i["model_id"] in selected_ids for i in api("/v2/model-instances?perPage=1000")["items"]
    ):
        if time.monotonic() >= deadline:
            raise RuntimeError("GPUStack has not finished releasing its model instances")
        time.sleep(2)
    print("GPUStack model instances stopped; downloaded weights retained.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=[
            "up",
            "initialize",
            "configure-models",
            "status",
            "stop-models",
            "down",
            "password",
        ],
    )
    parser.add_argument("--vllm-only", action="store_true", help="Stop only vLLM deployments")
    args = parser.parse_args()
    if (
        platform.node().split(".")[0] != "spark-9667"
        or Path.home() != Path("/home/deadspark")
        or os.getuid() != 1000
    ):
        raise RuntimeError("Run as deadspark on spark-9667 without sudo")
    if args.action == "up":
        prepare()
        compose("up", "-d", "server")
    elif args.action == "initialize":
        initialize()
    elif args.action == "configure-models":
        configure_models()
    elif args.action == "status":
        print("GPUStack UI: http://spark-9667:8090 (Tailscale)")
        for worker in api("/v2/workers")["items"]:
            print(f"Worker {worker['name']}: {worker['state']}")
        for model in api("/v2/models")["items"]:
            print(f"Model {model['name']}: {model['replicas']} requested instances")
    elif args.action == "password":
        if not sys.stdout.isatty():
            raise RuntimeError("Display the initial password only in your own interactive terminal")
        print((ROOT / "admin.password").read_text().strip())
    elif args.action == "stop-models":
        stop_models(args.vllm_only)
    elif args.action == "down":
        stop_models()
        compose("stop")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError, KeyError) as error:
        print(f"gpustack-spark: {error}", file=sys.stderr)
        sys.exit(1)
