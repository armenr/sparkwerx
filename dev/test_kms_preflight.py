"""KMS boot-review tests use synthetic configuration, never the live bootloader."""

import importlib.util
import io
import json
import stat
import subprocess
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("kms", ROOT / "root/graphics/kms-preflight.py")
kms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kms)
PLAN = json.loads((ROOT / "root/graphics/kms-plan.json").read_text())
RELEASE = "6.17.0-1031-nvidia"
GRUB = """# This is synthetic test data, not copied host boot configuration.
if [ -s $prefix/grubenv ]; then
  set have_grubenv=true
  load_env
fi
if [ "${next_entry}" ] ; then
  set default="${next_entry}"
  set next_entry=
  save_env next_entry
  set boot_once=true
else
  set default="0"
fi
menuentry 'PRIVATE TITLE' --id 'PRIVATE-ENTRY-ID' {
  search --fs-uuid PRIVATE-UUID
  linux /boot/vmlinuz-6.17.0-1031-nvidia root=UUID=PRIVATE-UUID credential=PRIVATE-SECRET ro
  initrd /boot/initrd.img-6.17.0-1031-nvidia
}
"""


def units():
    result = {}
    for name in kms.UNITS:
        inactive = name in ("gdm.service", "dgx-dashboard.service")
        result[name] = {
            "LoadState": "loaded",
            "ActiveState": "inactive" if inactive else "active",
            "SubState": "dead" if inactive else "running",
            "NeedDaemonReload": "no",
        }
    result["nix-daemon.socket"]["SubState"] = "listening"
    return result


def report():
    return {
        "grub": kms.grub_summary(GRUB, "saved_entry=PRIVATE-VALUE\n", RELEASE),
        "grubFilesystem": "ext2",
        "grubStorageAbstractionPresent": False,
        "efi": True,
        "pilotRootMatches": True,
        "existingGuardCount": 0,
        "modeset": "N",
        "factoryOverrideExact": True,
        "units": units(),
    }


class KmsTests(unittest.TestCase):
    def test_selected_intent_is_preparation_not_activation(self):
        self.assertEqual(PLAN["stage"], "preparation-only")
        self.assertEqual(PLAN["defaultPolicy"], "preserve-factory")
        self.assertEqual(PLAN["use"], ["local", "remote-over-tailscale"])
        self.assertEqual(PLAN["fallbackDesktop"], "factory-gnome-xorg")
        for key in (
            "activationImplemented",
            "rebootImplemented",
            "replaceDriver",
            "removeFactoryOverride",
            "reloadGpuModules",
        ):
            self.assertIs(PLAN[key], False)
        trial = PLAN["proposedTrial"]
        self.assertEqual(trial["kernelArguments"], ["nvidia_drm.modeset=1"])
        self.assertTrue(trial["normalBootUnchanged"])
        self.assertTrue(trial["keepHeadlessDuringInitialTest"])
        self.assertTrue(trial["requiresIndependentRecovery"])

    def test_recognizes_header_but_does_not_claim_a_verified_boot(self):
        observed = report()
        self.assertTrue(observed["grub"]["standardOneShotHeaderObserved"])
        self.assertTrue(observed["grub"]["loadsEnvironment"])
        self.assertTrue(observed["grub"]["firstKernelMatchesRunning"])
        self.assertTrue(observed["grub"]["firstInitrdMatchesRunning"])
        self.assertFalse(observed["grub"]["bootloaderWriteVerified"])
        self.assertEqual(kms.review_findings(observed), [])

    def test_private_boot_arguments_and_environment_values_never_appear(self):
        observed = kms.grub_summary(
            GRUB, "next_entry=PRIVATE-SELECTION\nsecret=PRIVATE-ENV\n", RELEASE
        )
        self.assertNotIn("PRIVATE", json.dumps(observed))
        self.assertTrue(observed["pendingNextEntry"])

    def test_incomplete_or_reordered_one_shot_header_is_not_accepted(self):
        for changed in (
            GRUB.replace("save_env next_entry", ""),
            GRUB.replace('set default="0"', 'set default="${saved_entry}"'),
            GRUB.replace(
                "set next_entry=\n  save_env next_entry", "save_env next_entry\n  set next_entry="
            ),
            "# " + GRUB.replace("\n", "\n# "),
        ):
            with self.subTest(config=changed):
                self.assertFalse(
                    kms.grub_summary(changed, "", RELEASE)["standardOneShotHeaderObserved"]
                )

    def test_pending_upgrade_is_a_review_finding_not_a_kernel_replacement(self):
        observed = report()
        observed["grub"] = kms.grub_summary(
            GRUB.replace(RELEASE, "6.17.0-1032-nvidia"), "", RELEASE
        )
        self.assertIn("grub.firstKernelMatchesRunning", kms.review_findings(observed))
        self.assertIn("grub.firstInitrdMatchesRunning", kms.review_findings(observed))

    def test_pending_boot_choices_and_failure_records_are_preserved_and_flagged(self):
        for key, finding in (
            ("next_entry", "pendingNextEntry"),
            ("prev_entry", "pendingPreviousEntry"),
            ("prev_saved_entry", "pendingPreviousEntry"),
            ("initrdfail", "initrdFailureRecorded"),
            ("recordfail", "recordfail"),
        ):
            with self.subTest(key=key):
                observed = report()
                observed["grub"] = kms.grub_summary(GRUB, f"{key}=1\n", RELEASE)
                self.assertIn(f"grub.{finding}", kms.review_findings(observed))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            kms.grub_summary(GRUB, "next_entry=a\nnext_entry=b\n", RELEASE)

    def test_storage_and_existing_guard_need_review(self):
        for key, value in (
            ("grubFilesystem", "btrfs"),
            ("grubStorageAbstractionPresent", True),
            ("existingGuardCount", 1),
            ("pilotRootMatches", False),
            ("efi", False),
            ("modeset", "Y"),
            ("factoryOverrideExact", False),
        ):
            with self.subTest(key=key):
                observed = report()
                observed[key] = value
                self.assertTrue(kms.review_findings(observed))

    def test_gnome_policy_does_not_treat_a_comment_as_configuration(self):
        self.assertEqual(kms.gnome_policy("[daemon]\n#WaylandEnable=false\n"), "unset")
        self.assertEqual(kms.gnome_policy("[daemon]\nWaylandEnable=false\n"), "false")
        self.assertEqual(kms.gnome_policy("[daemon]\nWaylandEnable=true\n"), "true")
        self.assertEqual(kms.gnome_policy("[daemon]\nWaylandEnable=PRIVATE\n"), "unrecognized")

    def test_loaded_booleans_are_strict(self):
        for value in ("Y", "N"):
            self.assertEqual(kms.kernel_boolean(value + "\n"), value)
        for value in ("1", "0", "", "yes"):
            with self.assertRaises(ValueError):
                kms.kernel_boolean(value)

    def test_unit_parser_consumes_whole_records_in_any_property_order(self):
        expected = units()
        data = "\n\n".join(
            "\n".join(f"{key}={value}" for key, value in (fields | {"Id": name}).items())
            for name, fields in expected.items()
        )
        self.assertEqual(kms.unit_summary(data), expected)
        with self.assertRaises(ValueError):
            kms.unit_summary(data + "\n\n" + data)
        with self.assertRaises(ValueError):
            kms.unit_summary("")

    def test_socket_idle_nix_is_healthy_but_reload_drift_and_graphics_are_not(self):
        observed = report()
        observed["units"]["nix-daemon.service"].update(ActiveState="inactive", SubState="dead")
        self.assertEqual(kms.review_findings(observed), [])
        observed["units"]["nix-daemon.socket"]["SubState"] = "dead"
        self.assertIn("unit.nix-daemon.service", kms.review_findings(observed))
        observed = report()
        observed["units"]["gdm.service"]["ActiveState"] = "active"
        observed["units"]["tailscaled.service"]["NeedDaemonReload"] = "yes"
        self.assertEqual(
            kms.review_findings(observed), ["unit.gdm.service", "unit.tailscaled.service"]
        )

    def test_plan_does_not_inspect_host_or_start_a_subprocess(self):
        with (
            mock.patch.object(kms, "inspect") as inspect,
            mock.patch.object(kms.subprocess, "run") as run,
            mock.patch("sys.stdout", new_callable=io.StringIO) as output,
        ):
            self.assertEqual(
                kms.main(["plan", "--plan-file", str(ROOT / "root/graphics/kms-plan.json")]), 0
            )
            self.assertIn("KMS_STATUS=PREPARATION_ONLY", output.getvalue())
            inspect.assert_not_called()
            run.assert_not_called()

    def test_nonroot_check_stops_before_reading_private_boot_data(self):
        with (
            mock.patch.object(kms.os, "geteuid", return_value=1000),
            mock.patch.object(kms, "read_config") as read,
            mock.patch.object(kms, "command") as command,
        ):
            with self.assertRaisesRegex(ValueError, "sudo"):
                kms.inspect(PLAN)
            read.assert_not_called()
            command.assert_not_called()

    def test_foreign_or_writable_configuration_is_not_followed(self):
        for mode, owner in (
            (stat.S_IFLNK | 0o777, 0),
            (stat.S_IFREG | 0o644, 1000),
            (stat.S_IFREG | 0o666, 0),
        ):
            path = mock.Mock()
            path.lstat.return_value = mock.Mock(st_mode=mode, st_uid=owner, st_size=100)
            with self.assertRaises(ValueError):
                kms.read_config(path)
            path.read_text.assert_not_called()

    def test_complete_inspection_uses_only_read_only_commands(self):
        responses = ["saved_entry=PRIVATE\n", "ext2\n", "", "ignored by mocked parser"]
        host = mock.Mock(machine="aarch64", nodename=PLAN["pilotHost"], release=RELEASE)
        configs = [
            GRUB,
            "# GRUB Environment Block\n",
            "options nvidia-drm modeset=0\n",
            "[daemon]\n",
        ]
        with (
            mock.patch.object(kms.os, "geteuid", return_value=0),
            mock.patch.object(kms.os, "uname", return_value=host),
            mock.patch.object(kms, "read_config", side_effect=configs),
            mock.patch.object(kms, "command", side_effect=responses) as command,
            mock.patch.object(kms, "unit_summary", return_value=units()),
            mock.patch.object(kms, "PROFILE") as profile,
            mock.patch.object(kms.Path, "read_text", return_value="N\n"),
            mock.patch.object(kms.Path, "is_dir", return_value=True),
            mock.patch.object(kms.os.path, "lexists", return_value=False),
        ):
            profile.resolve.return_value = Path(PLAN["pilotRoot"])
            observed = kms.inspect(PLAN)
            self.assertFalse(observed["activationImplemented"])
            self.assertFalse(observed["hostChangesPerformed"])
            self.assertEqual(kms.review_findings(observed), [])
        calls = [call.args[0] for call in command.call_args_list]
        self.assertEqual(len(calls), 4)
        self.assertEqual(
            calls[:3],
            [
                ["/usr/bin/grub-editenv", "/boot/grub/grubenv", "list"],
                ["/usr/sbin/grub-probe", "--target=fs", "/boot/grub/grubenv"],
                ["/usr/sbin/grub-probe", "--target=abstraction", "/boot/grub/grubenv"],
            ],
        )
        self.assertEqual(calls[3][:2], ["/usr/bin/systemctl", "show"])

    def test_failed_read_command_does_not_leak_output(self):
        with mock.patch.object(
            kms.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 1, "PRIVATE", "PRIVATE"),
        ):
            with self.assertRaisesRegex(ValueError, "read-only grub-probe query failed") as raised:
                kms.command(["/usr/sbin/grub-probe", "--target=fs", "/boot/grub/grubenv"])
            self.assertNotIn("PRIVATE", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
