"""Private network and stop semantics for the optional GPUStack workload."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "gpustack_control", Path(__file__).resolve().parents[1] / "workloads/gpustack/control.py"
)
control = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control)


class GPUStackControlTests(unittest.TestCase):
    def test_private_bindings_and_no_autostart(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "config/gpustack"
            pin = Path(__file__).resolve().parents[1] / "workloads/gpustack/source.json"
            with (
                patch.object(control, "ROOT", root),
                patch.object(control, "run", return_value="100.64.0.42\n"),
                patch.object(control, "compose"),
                patch.dict(
                    control.os.environ,
                    {
                        "SPARK_GPUSTACK_PIN": str(pin),
                        "SPARK_GPUSTACK_WORKER": "/nix/store/worker.py",
                        "SPARK_GPUSTACK_COLLECTOR": "/nix/store/collector.py",
                    },
                ),
            ):
                control.prepare()
                first = (root / "admin.password").read_text()
                control.private_write(root / "worker.env", "GPUSTACK_TOKEN=fixture\n")
                control.prepare()
                self.assertEqual(first, (root / "admin.password").read_text())
                doc = json.loads((root / "compose.json").read_text())
                server = doc["services"]["server"]
                self.assertEqual(server["ports"], ["127.0.0.1:8090:80", "100.64.0.42:8090:80"])
                self.assertEqual(server["restart"], "no")
                self.assertNotIn("fixture", (root / "compose.json").read_text())
                worker = doc["services"]["worker"]
                self.assertEqual(worker["environment"]["GPUSTACK_HOST"], "127.0.0.1")
                self.assertEqual(
                    json.loads(worker["environment"]["GPUSTACK_SYSTEM_RESERVED"]),
                    {"ram": 8, "vram": 0},
                )
                self.assertEqual(
                    worker["environment"]["GPUSTACK_RUNTIME_DOCKER_CDI_SPECS_GENERATE"], "false"
                )
                self.assertEqual((root / "admin.password").stat().st_mode & 0o777, 0o600)

    def test_public_address_rejected_before_password_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "config/gpustack"
            pin = Path(__file__).resolve().parents[1] / "workloads/gpustack/source.json"
            with (
                patch.object(control, "ROOT", root),
                patch.object(control, "run", return_value="8.8.8.8"),
                patch.dict(control.os.environ, {"SPARK_GPUSTACK_PIN": str(pin)}),
            ):
                with self.assertRaises(RuntimeError):
                    control.prepare()
                self.assertFalse((root / "admin.password").exists())

    def test_stop_scales_deployment_to_zero_before_waiting(self):
        with patch.object(
            control,
            "api",
            side_effect=[{"items": [{"id": 3, "name": "test", "replicas": 1}]}, {}, {"items": []}],
        ) as api:
            control.stop_models()
        self.assertEqual(
            api.call_args_list[1].args,
            ("/v2/models/3", {"id": 3, "name": "test", "replicas": 0}, "PUT"),
        )
        self.assertIn("model-instances", api.call_args_list[2].args[0])

    def test_api_failure_does_not_claim_stopped(self):
        with patch.object(control, "api", side_effect=RuntimeError("unavailable")):
            with self.assertRaises(RuntimeError):
                control.stop_models()

    def test_vllm_stop_preserves_other_backends_and_waits_for_its_instances(self):
        models = [
            {"id": 3, "name": "vllm", "backend": "vLLM", "replicas": 1},
            {"id": 4, "name": "other", "backend": "SGLang", "replicas": 1},
        ]
        with (
            patch.object(
                control,
                "api",
                side_effect=[
                    {"items": models},
                    {},
                    {"items": [{"model_id": 3}, {"model_id": 4}]},
                    {"items": [{"model_id": 4}]},
                ],
            ) as api,
            patch.object(control.time, "sleep") as sleep,
        ):
            control.stop_models(vllm_only=True)
        updates = [call for call in api.call_args_list if len(call.args) > 1]
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0].args[0], "/v2/models/3")
        self.assertEqual(updates[0].args[1]["replicas"], 0)
        sleep.assert_called_once_with(2)

    def test_zero_replicas_still_waits_and_reports_stuck_instance(self):
        with (
            patch.object(
                control,
                "api",
                side_effect=[
                    {"items": [{"id": 3, "replicas": 0}]},
                    {"items": [{"model_id": 3}]},
                ],
            ) as api,
            patch.object(control.time, "monotonic", side_effect=[0, 91]),
        ):
            with self.assertRaisesRegex(RuntimeError, "not finished releasing"):
                control.stop_models()
        self.assertEqual(api.call_count, 2)

    def test_presets_are_created_stopped_and_existing_ui_edits_are_preserved(self):
        root = Path(__file__).resolve().parents[1] / "workloads/gpustack"
        presets = json.loads((root / "models.json").read_text())
        name = next(iter(presets))
        for exists in (False, True):
            with (
                self.subTest(exists=exists),
                patch.dict(
                    control.os.environ,
                    {
                        "SPARK_GPUSTACK_PIN": str(root / "source.json"),
                        "SPARK_GPUSTACK_MODELS": str(root / "models.json"),
                    },
                ),
                patch.object(
                    control,
                    "api",
                    side_effect=[
                        {"items": [{"id": 1, "backend_name": "vLLM"}]},
                        {},
                        {"items": [{"id": 1, "name": "spark-9667"}]},
                        {"items": [{"name": name}] if exists else []},
                        {},
                    ],
                ) as api,
            ):
                control.configure_models()
            creates = [
                call
                for call in api.call_args_list
                if call.args[0] == "/v2/models" and len(call.args) > 1
            ]
            self.assertEqual(len(creates), 0 if exists else 1)
            if creates:
                self.assertEqual(creates[0].args[1]["replicas"], 0)
                self.assertFalse(creates[0].args[1]["restart_on_error"])


if __name__ == "__main__":
    unittest.main()
