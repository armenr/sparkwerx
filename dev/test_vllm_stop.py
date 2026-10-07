"""Keep model shutdown scoped to vLLM and report incomplete shutdowns."""

import importlib.machinery
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

LOADER = importlib.machinery.SourceFileLoader(
    "vllm_stop", str(Path(__file__).resolve().parent.parent / "scripts/vllm_stop")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
stop = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(stop)


class StopTests(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(stop, "stop_gpustack")
        self.manager_stop = patcher.start()
        self.addCleanup(patcher.stop)

    def test_manager_failure_prevents_container_race(self):
        self.manager_stop.side_effect = RuntimeError("manager offline")
        with patch.object(stop, "docker") as docker:
            with self.assertRaisesRegex(RuntimeError, "manager offline"):
                stop.stop_models()
        docker.assert_not_called()

    def test_official_and_labeled_images_match_but_neighbors_do_not(self):
        for image in (
            "vllm/vllm-openai:latest",
            "docker.io/vllm/vllm-openai@sha256:abc",
            "nvcr.io/nvidia/vllm:26.09-py3",
        ):
            self.assertTrue(stop.is_vllm({"image": image}))
        for image in ("postgres", "my-vllm-backup:latest", "evil/vllm-openai", "nixos/nix"):
            self.assertFalse(stop.is_vllm({"image": image}))
        self.assertTrue(stop.is_vllm({"image": "localhost:5000/custom:1", "workload": "vllm"}))

    def test_shutdown_stops_all_selected_containers_without_removing_data(self):
        containers = [{"id": "one", "name": "/first"}, {"id": "two", "name": "/second"}]
        with (
            patch.object(stop, "running_models", side_effect=[containers, []]),
            patch.object(stop, "docker") as docker,
        ):
            stop.stop_models()
        self.assertEqual(
            [call.args for call in docker.call_args_list],
            [("stop", "--timeout", "15", "one"), ("stop", "--timeout", "15", "two")],
        )

    def test_already_stopped_is_a_noop(self):
        with (
            patch.object(stop, "running_models", return_value=[]),
            patch.object(stop, "docker") as docker,
        ):
            stop.stop_models()
        docker.assert_not_called()

    def test_failure_still_attempts_other_models_and_reports_failure(self):
        containers = [{"id": "one", "name": "/first"}, {"id": "two", "name": "/second"}]
        with (
            patch.object(stop, "running_models", side_effect=[containers, [containers[0]]]),
            patch.object(stop, "docker", side_effect=[RuntimeError("denied"), "two"]) as docker,
        ):
            with self.assertRaisesRegex(RuntimeError, "Still running: first"):
                stop.stop_models()
        self.assertEqual(docker.call_count, 2)

    def test_replacement_model_prevents_false_success(self):
        with (
            patch.object(
                stop,
                "running_models",
                side_effect=[[{"id": "one", "name": "/first"}], [{"name": "/replacement"}]],
            ),
            patch.object(stop, "docker"),
        ):
            with self.assertRaisesRegex(RuntimeError, "Still running: replacement"):
                stop.stop_models()
