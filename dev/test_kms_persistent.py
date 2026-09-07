"""KMS generation and transaction tests; synthetic private boot trees only."""

import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "persistent", ROOT / "root/graphics/kms-persistent.py"
)
kms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kms)
PLAN = json.loads((ROOT / "root/graphics/kms-plan.json").read_text())
BUNDLE = "/nix/store/" + "a" * 32 + "-dgx-kms-persistent"
HEADER = """if [ -s $prefix/grubenv ]; then
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
set timeout_style=hidden
set timeout=0
"""
BODY = """  recordfail
  load_video
  insmod gzio
  insmod part_gpt
  insmod ext2
  set root='hd0,gpt2'
  if [ x$feature_platform_search_hint = xy ]; then
    search --no-floppy --fs-uuid --set=root --hint-efi=hd0,gpt2 PRIVATE-UUID
  else
    search --no-floppy --fs-uuid --set=root PRIVATE-UUID
  fi
  linux /boot/vmlinuz-RELEASE root=UUID=PRIVATE-UUID ro quiet ARGUMENT
  initrd /boot/initrd.img-RELEASE
"""


def section(name, value):
    return f"\n### BEGIN /etc/grub.d/{name} ###\n{value}### END /etc/grub.d/{name} ###\n"


def fixture(enabled=False, release="6.17.0-1031-nvidia"):
    header = (
        HEADER.replace("hidden", "menu").replace("timeout=0", "timeout=5") if enabled else HEADER
    )
    body = BODY.replace("RELEASE", release).replace("ARGUMENT", kms.ARG_ON if enabled else "")
    linux = "menuentry 'Ubuntu' --id normal-id {\n" + body + "}\n"
    result = section("00_header", header) + section("10_linux", linux)
    result += section("41_custom", kms.trial.CUSTOM_HOOK + "\n")
    if enabled:
        result += section("42_sparkwerx_kms", kms.render_fallback(linux))
    return result


class GeneratorTests(unittest.TestCase):
    def test_ubuntu_legacy_hidden_timeout_transition_is_narrowly_accepted(self):
        legacy = """if [ x$feature_timeout_style = xy ] ; then
    set timeout_style=hidden
    set timeout=0
  elif sleep --interruptible 0 ; then
    set timeout=0
  fi
"""
        visible = (
            legacy.replace("hidden", "menu")
            .replace("timeout=0", "timeout=5")
            .replace("elif sleep --interruptible 0 ; then", "else")
        )
        kms.verify_change(
            fixture().replace(HEADER, HEADER + legacy),
            fixture(True).replace("set timeout=5\n", "set timeout=5\n" + visible, 1),
        )
        with self.assertRaises(ValueError):
            kms.verify_change(
                fixture().replace(HEADER, HEADER + legacy),
                fixture(True).replace(
                    "set timeout=5\n",
                    "set timeout=5\n" + visible.replace("  else", "  else\n    reboot"),
                    1,
                ),
            )

    def test_normal_and_fallback_have_same_current_kernel_and_private_args(self):
        kms.verify_change(fixture(), fixture(True))
        kms.check_enabled(fixture(True))
        body = kms.sections(fixture(True))["/etc/grub.d/42_sparkwerx_kms"]
        self.assertIn("root=UUID=PRIVATE-UUID ro quiet", body)
        self.assertIn(kms.ARG_OFF, body)
        self.assertNotIn(kms.ARG_ON, body)
        self.assertNotIn("--id normal-id", body)
        self.assertNotIn("save_env", body)
        self.assertNotIn("set default", body)

    def test_kernel_update_generates_new_fallback_without_old_kernel(self):
        changed = fixture(True, "6.18.0-new")
        kms.verify_change(fixture(False, "6.18.0-new"), changed)
        self.assertNotIn("1031", changed)
        self.assertEqual(changed.count("vmlinuz-6.18.0-new"), 2)

    def test_unrelated_or_unsafe_generated_changes_are_rejected(self):
        for changed in (
            fixture(True).replace("PRIVATE-UUID", "DIFFERENT"),
            fixture(True).replace('set default="0"', 'set default="1"'),
            fixture(True).replace("timeout_style=menu", "timeout_style=hidden"),
            fixture(True).replace("timeout=5", "timeout=0"),
            fixture(True).replace(kms.ARG_OFF, kms.ARG_ON),
            fixture(True).replace(kms.ARG_ON, kms.ARG_ON + " " + kms.ARG_ON),
            fixture(True).replace("  load_env", "  reboot"),
            fixture(True) + "reboot\n",
            fixture(True) + section("99_unrelated", "reboot\n"),
        ):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                kms.verify_change(fixture(), changed)

    def test_stale_or_missing_fallback_cannot_be_reported_active(self):
        changed = fixture(True).replace("vmlinuz-6.17.0-1031-nvidia", "vmlinuz-6.18-new", 1)
        with self.assertRaises(ValueError):
            kms.check_enabled(changed)
        with self.assertRaises(ValueError):
            kms.check_enabled(fixture())

    def test_fallback_refuses_unsupported_factory_entry_shape(self):
        for changed in (
            fixture(True).replace("  load_video", "  source /foreign.cfg"),
            fixture(True).replace(" ro quiet ", " ro quiet nomodeset "),
            fixture(True).replace(" ro quiet ", " ro quiet nvidia-drm.modeset=0 "),
            fixture(True).replace(" ro quiet ", " ro quiet ; reboot "),
            fixture(True).replace("  load_video", "  function nested {\n }"),
        ):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                kms.render_fallback(changed)

    def test_real_grub_parser_accepts_default_and_fallback(self):
        checker = shutil.which("grub-script-check")
        if checker is None:
            self.skipTest("Nix policy supplies the native GRUB parser")
        parsed = subprocess.run(
            [checker], input=fixture(True), capture_output=True, text=True, check=False
        )
        self.assertEqual(parsed.returncode, 0, parsed.stderr)

    def test_generator_runs_vendor_script_without_mutating_environment(self):
        linux = kms.sections(fixture(True))["/etc/grub.d/10_linux"]
        with (
            mock.patch.dict(
                os.environ,
                {"GRUB_CMDLINE_LINUX_DEFAULT": "quiet " + kms.ARG_ON, "GRUB_CMDLINE_LINUX": ""},
            ),
            mock.patch.object(kms.trial, "read_owned"),
            mock.patch.object(kms, "run", return_value=linux) as run,
            mock.patch("builtins.print") as output,
        ):
            kms.fallback()
            run.assert_called_once_with(["/etc/grub.d/10_linux"])
            self.assertEqual(output.call_args.args[0], kms.render_fallback(linux))
            self.assertIn(kms.ARG_ON, os.environ["GRUB_CMDLINE_LINUX_DEFAULT"])

    def test_missing_duplicate_or_conflicting_enable_arg_refused_before_execution(self):
        for value in (
            "",
            kms.ARG_ON + " " + kms.ARG_ON,
            kms.ARG_ON + " nomodeset",
            kms.ARG_ON + " nvidia-drm.modeset=0",
        ):
            with (
                mock.patch.dict(
                    os.environ, {"GRUB_CMDLINE_LINUX_DEFAULT": value, "GRUB_CMDLINE_LINUX": ""}
                ),
                mock.patch.object(kms, "run") as run,
            ):
                with self.assertRaises(ValueError):
                    kms.fallback()
                run.assert_not_called()

    def test_nix_configuration_selection_and_posix_default_append(self):
        location = os.environ.get("DGX_KMS_TEST_CONFIGURATION")
        if not location:
            self.skipTest("Nix policy supplies enabled/disabled configuration outputs")
        path = Path(location)
        selected = os.environ["DGX_KMS_TEST_ENABLED"] == "1"
        self.assertEqual(all((path / name).is_file() for name in kms.LINKS), selected)
        if not selected:
            self.assertEqual(list(path.iterdir()), [])
            return
        defaults = path / kms.LINKS[1]
        result = subprocess.run(
            [
                "sh",
                "-c",
                'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"; . "$1"; printf "%s\\n" "$GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_TIMEOUT_STYLE" "$GRUB_TIMEOUT"',
                "fixture",
                str(defaults),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.splitlines(),
            ["quiet splash " + kms.ARG_ON, "menu", os.environ["DGX_KMS_TEST_MENU_SECONDS"]],
        )
        self.assertTrue(os.access(path / kms.LINKS[0], os.X_OK))


class PowerCut(BaseException):
    pass


class Fake(kms.Persistent):
    def __init__(self, root, configuration):
        super().__init__(PLAN, str(configuration), BUNDLE, root)
        self.release = "6.17.0-1031-nvidia"
        self.bad_generator = False
        self.fail_health = False
        self.power_cut = None
        self.events = []

    def initial_check(self):
        self.health()
        kms.require(not self.ownership(), "foreign initial state")

    def health(self):
        self.events.append("health")
        if self.fail_health and kms.ARG_ON in self.grub.read_text():
            raise ValueError("injected health failure")

    def environment(self):
        return {}

    def fingerprint(self):
        return {"kernel": self.release}

    def generate(self):
        enabled = len(self.ownership()) == 2
        self.events.append("generate")
        if enabled and self.bad_generator:
            raise ValueError("injected generator failure")
        return fixture(enabled, self.release)

    def syntax(self, text):
        self.events.append("parse")

    def links(self, wanted):
        super().links(wanted)
        if self.power_cut == "links":
            raise PowerCut

    def replace_grub(self, text, expected):
        super().replace_grub(text, expected)
        if self.power_cut == "grub":
            raise PowerCut


class TransactionTests(unittest.TestCase):
    def setUp(self):
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        temporary = tempfile.TemporaryDirectory(prefix="sparkwerx-kms-persistent-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        owner = mock.patch.object(kms.trial, "OWNER", os.getuid())
        owner.start()
        self.addCleanup(owner.stop)
        for folder in (
            "var/lib/dgx-setup",
            "boot/grub",
            "etc/grub.d",
            "etc/default/grub.d",
            "nix/var/nix/gcroots",
            "sys/module/nvidia_drm/parameters",
        ):
            (self.root / folder).mkdir(parents=True)
        self.configuration = self.root / "configuration"
        for name in kms.LINKS:
            path = self.configuration / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic Nix configuration\n")
        (self.root / "boot/grub/grub.cfg").write_text(fixture())
        (self.root / "sys/module/nvidia_drm/parameters/modeset").write_text("N\n")
        self.ops = Fake(self.root, self.configuration)

    def test_enable_disable_are_next_boot_only_and_retain_private_rollback(self):
        self.assertEqual(self.ops.apply(True, True)["status"], "PERSISTENT_PENDING_REBOOT")
        self.assertEqual(self.ops.ownership(), list(kms.LINKS))
        self.assertEqual(self.ops.state.stat().st_mode & 0o777, 0o700)
        self.assertTrue(self.ops.retention.is_symlink())
        for path in self.ops.state.glob("txn-*/*"):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.ops.apply(False)["status"], "FACTORY_DEFAULT")
        self.assertEqual(self.ops.grub.read_text(), fixture())
        self.assertEqual(self.ops.ownership(), [])
        self.assertTrue(self.ops.retention.is_symlink())
        self.assertEqual(len(list(self.ops.state.glob("txn-*"))), 2)

    def test_missing_console_gate_causes_zero_mutation(self):
        with self.assertRaises(ValueError):
            self.ops.apply(True)
        self.assertFalse(self.ops.state.exists())
        self.assertEqual(self.ops.ownership(), [])

    def test_idempotent_enable_and_disable_do_not_generate_or_change_snapshot(self):
        self.ops.apply(True, True)
        before = (self.ops.state / "journal.json").read_bytes()
        with mock.patch.object(self.ops, "generate") as generate:
            self.ops.apply(True, True)
            generate.assert_not_called()
        self.assertEqual((self.ops.state / "journal.json").read_bytes(), before)
        self.ops.apply(False)
        with mock.patch.object(self.ops, "generate") as generate:
            self.ops.apply(False)
            generate.assert_not_called()

    def test_failed_generator_and_postflight_restore_exact_factory_state(self):
        for flag in ("bad_generator", "fail_health"):
            with self.subTest(flag=flag):
                setattr(self.ops, flag, True)
                with self.assertRaises(ValueError):
                    self.ops.apply(True, True)
                self.assertEqual(self.ops.grub.read_text(), fixture())
                self.assertEqual(self.ops.ownership(), [])
                self.assertEqual(self.ops.load()["phase"], "recovered")
                setattr(self.ops, flag, False)

    def test_interrupted_publication_recovers_before_or_after_grub_replace(self):
        for point in ("links", "grub"):
            with self.subTest(point=point):
                self.ops.power_cut = point
                with self.assertRaises(PowerCut):
                    self.ops.apply(True, True)
                self.assertEqual(self.ops.status()["status"], "RECOVERY_REQUIRED")
                self.ops.power_cut = None
                self.ops.recover()
                self.assertEqual(self.ops.grub.read_text(), fixture())
                self.assertEqual(self.ops.ownership(), [])

    def test_failed_disable_restores_enabled_state(self):
        self.ops.apply(True, True)
        self.ops.power_cut = "grub"
        with self.assertRaises(PowerCut):
            self.ops.apply(False)
        self.ops.power_cut = None
        self.ops.recover()
        self.assertEqual(self.ops.grub.read_text(), fixture(True))
        self.assertEqual(self.ops.ownership(), list(kms.LINKS))

    def test_foreign_file_and_symlink_collisions_preserved(self):
        path = self.root / kms.LINKS[0]
        path.write_text("foreign")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertEqual(path.read_text(), "foreign")
        path.unlink()
        path.symlink_to("/foreign")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertEqual(os.readlink(path), "/foreign")

    def test_concurrent_grub_change_is_never_overwritten_by_recovery(self):
        self.ops.power_cut = "links"
        with self.assertRaises(PowerCut):
            self.ops.apply(True, True)
        self.ops.power_cut = None
        self.ops.grub.write_text(fixture() + "# foreign update\n")
        with self.assertRaises(ValueError):
            self.ops.recover()
        self.assertTrue(self.ops.grub.read_text().endswith("# foreign update\n"))

    def test_stale_snapshot_cannot_restore_old_kernel_boot_config(self):
        self.ops.power_cut = "grub"
        with self.assertRaises(PowerCut):
            self.ops.apply(True, True)
        self.ops.power_cut = None
        self.ops.release = "6.18-new"
        with self.assertRaises(ValueError):
            self.ops.recover()

    def test_disable_after_os_update_regenerates_current_kernel_not_old_snapshot(self):
        self.ops.apply(True, True)
        self.ops.release = "6.18-new"
        self.ops.grub.write_text(fixture(True, self.ops.release))
        self.assertEqual(self.ops.status()["status"], "PERSISTENT_PENDING_REBOOT")
        self.ops.apply(False)
        self.assertEqual(self.ops.grub.read_text(), fixture(False, self.ops.release))
        self.assertNotIn("1031", self.ops.grub.read_text())

    def test_corrupt_snapshot_and_wrong_bundle_are_rejected(self):
        self.ops.apply(True, True)
        wrong = Fake(self.root, self.configuration)
        wrong.bundle = "/foreign"
        with self.assertRaises(ValueError):
            wrong.load()
        data = self.ops.load()
        (self.ops.state / data["transaction"] / "before").write_text("corrupt")
        with self.assertRaises(ValueError):
            self.ops.load()

    def test_loaded_kms_changes_only_in_separate_simulated_boot(self):
        self.ops.apply(True, True)
        loaded = self.root / "sys/module/nvidia_drm/parameters/modeset"
        self.assertEqual(loaded.read_text(), "N\n")
        loaded.write_text("Y\n")
        self.assertEqual(self.ops.status()["status"], "PERSISTENT_KMS_ACTIVE")
        self.assertEqual(self.ops.apply(False)["status"], "FACTORY_PENDING_REBOOT")
        self.assertEqual(loaded.read_text(), "Y\n")

    def test_generation_drift_is_refused_before_config_mutation(self):
        self.ops.grub.write_text(fixture() + "# unreviewed\n")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertFalse(self.ops.state.exists())
        self.assertEqual(self.ops.ownership(), [])

    def test_foreign_retention_is_preserved_without_creating_recovery_state(self):
        self.ops.retention.symlink_to("/foreign")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertFalse(self.ops.state.exists())
        self.assertEqual(os.readlink(self.ops.retention), "/foreign")
        self.assertEqual(self.ops.ownership(), [])

    def test_boot_environment_drift_is_refused_before_config_mutation(self):
        with mock.patch.object(self.ops, "environment", side_effect=[{}, {"foreign": "value"}]):
            with self.assertRaises(ValueError):
                self.ops.apply(True, True)
        self.assertFalse(self.ops.state.exists())
        self.assertEqual(self.ops.ownership(), [])


if __name__ == "__main__":
    unittest.main()
