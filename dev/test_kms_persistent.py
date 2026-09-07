"""KMS generation and transaction tests; synthetic private boot trees only."""

import importlib.util
import io
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

    def test_hidden_or_zero_timeout_cannot_be_reported_active(self):
        for changed in (
            fixture(True).replace("timeout_style=menu", "timeout_style=hidden"),
            fixture(True).replace("timeout=5", "timeout=0"),
            fixture(True).replace("timeout=5", "timeout=5\nset timeout_style=hidden"),
            fixture(True).replace("timeout=5", "timeout=5\nset timeout=0"),
        ):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                kms.check_enabled(changed)

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

    def test_factory_dropin_order_keeps_fallback_menu_visible(self):
        location = os.environ.get("DGX_KMS_TEST_CONFIGURATION")
        if not location:
            self.skipTest("Nix policy supplies the actual GRUB drop-in")
        if os.environ["DGX_KMS_TEST_ENABLED"] != "1":
            return
        defaults = Path(location) / kms.LINKS[1]
        with tempfile.TemporaryDirectory(prefix="sparkwerx-grub-order-test-") as temporary:
            folder = Path(temporary)
            # The factory grub-mkconfig sources *.cfg in shell glob order.
            # Numeric prefixes precede BOTH of these installed factory files.
            (folder / "menu.cfg").write_text("GRUB_TIMEOUT=5\nGRUB_TIMEOUT_STYLE=menu\n")
            (folder / "no-grubmenu.cfg").write_text("GRUB_TIMEOUT=0\nGRUB_TIMEOUT_STYLE=hidden\n")
            (folder / "nvidia-spark-pci.cfg").write_text(
                'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT factory-pci=fixture"\n'
            )
            (folder / defaults.name).symlink_to(defaults)
            result = subprocess.run(
                [
                    "sh",
                    "-c",
                    'GRUB_CMDLINE_LINUX_DEFAULT=quiet; for x in "$1"/*.cfg; do . "$x"; done; '
                    'printf "%s\\n" "$GRUB_TIMEOUT_STYLE" "$GRUB_TIMEOUT" "$GRUB_CMDLINE_LINUX_DEFAULT"',
                    "fixture",
                    str(folder),
                ],
                env={"PATH": os.environ["PATH"], "LC_ALL": "C"},
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "menu",
                os.environ["DGX_KMS_TEST_MENU_SECONDS"],
                "quiet factory-pci=fixture " + kms.ARG_ON,
            ],
        )


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

    def initial_check(self, *, allow_previous=False):
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


class TemporaryBootTestCase(unittest.TestCase):
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


class TransactionTests(TemporaryBootTestCase):
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

    def test_menu_order_failure_reports_automatic_recovery(self):
        def generate():
            return fixture(bool(self.ops.ownership())).replace(
                "timeout_style=menu", "timeout_style=hidden"
            )

        output = io.StringIO()
        with (
            mock.patch.object(self.ops, "generate", side_effect=generate),
            mock.patch("sys.stderr", output),
        ):
            with self.assertRaisesRegex(ValueError, "fallback menu is not visible"):
                self.ops.apply(True, True)
        self.assertEqual(self.ops.grub.read_text(), fixture())
        self.assertEqual(self.ops.ownership(), [])
        self.assertEqual(self.ops.load()["phase"], "recovered")
        self.assertIn(
            "PASS|recovery|exact pre-transaction boot configuration restored", output.getvalue()
        )

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


class RetryTests(TemporaryBootTestCase):
    def seed_previous(self):
        self.ops.state.mkdir(mode=0o700)
        transaction = self.ops.state / "txn-menu-order"
        transaction.mkdir(mode=0o700)
        before = fixture().encode()
        checksum = kms.trial.digest(before)
        self.ops.plan = {**PLAN, "reviewedBoot": {**PLAN["reviewedBoot"], "configSha256": checksum}}
        for name in ("before", "baseline"):
            kms.trial.publish(transaction / name, before)
        kms.trial.publish(
            transaction / "generated", fixture(True).replace("menu\n", "hidden\n").encode()
        )
        data = {
            "schema": 1,
            "phase": "recovered",
            "bundle": kms.PREVIOUS_BUNDLE,
            "configuration": kms.PREVIOUS_CONFIGURATION,
            "transaction": transaction.name,
            "wasEnabled": False,
            "inputs": self.ops.fingerprint(),
            "hashes": {"before": checksum, "baseline": checksum},
        }
        self.ops.journal(data)
        self.ops.retention.symlink_to(kms.PREVIOUS_BUNDLE)
        return data

    def assert_previous_preserved(self, journal):
        archive = self.root / kms.RETRY_ARCHIVE
        self.assertEqual((archive / "journal.json").read_bytes(), journal)
        self.assertEqual((archive / "txn-menu-order/before").read_text(), fixture())
        self.assertEqual(os.readlink(self.root / kms.PREVIOUS_ROOT), kms.PREVIOUS_BUNDLE)
        self.assertEqual(os.readlink(self.ops.retention), self.ops.bundle)

    def test_retry_archives_only_recovered_attempt_and_preserves_old_code(self):
        self.seed_previous()
        journal = (self.ops.state / "journal.json").read_bytes()
        self.assertEqual(self.ops.apply(True, True)["status"], "PERSISTENT_PENDING_REBOOT")
        self.assert_previous_preserved(journal)
        self.ops.apply(False)
        self.assertEqual(self.ops.grub.read_text(), fixture())
        self.assert_previous_preserved(journal)

    def test_retry_preflight_is_read_only(self):
        self.seed_previous()
        journal = (self.ops.state / "journal.json").read_bytes()
        self.assertTrue(self.ops.prepare_retry(dry_run=True))
        self.assertEqual((self.ops.state / "journal.json").read_bytes(), journal)
        self.assertEqual(os.readlink(self.ops.retention), kms.PREVIOUS_BUNDLE)
        self.assertFalse((self.root / kms.RETRY_ARCHIVE).exists())
        self.assertFalse(os.path.lexists(self.root / kms.PREVIOUS_ROOT))
        self.assertEqual(self.ops.grub.read_text(), fixture())
        self.assertEqual(self.ops.ownership(), [])

    def test_retry_refuses_unknown_active_or_interrupted_predecessor(self):
        data = self.seed_previous()
        for changes in (
            {"bundle": "/foreign"},
            {"configuration": "/foreign"},
            {"phase": "enabled"},
            {"phase": "prepared"},
            {"wasEnabled": True},
            {"inputs": {"kernel": "other"}},
        ):
            with self.subTest(changes=changes):
                self.ops.journal({**data, **changes})
                journal = (self.ops.state / "journal.json").read_bytes()
                with self.assertRaises(ValueError):
                    self.ops.apply(True, True)
                self.assertEqual((self.ops.state / "journal.json").read_bytes(), journal)
                self.assertEqual(os.readlink(self.ops.retention), kms.PREVIOUS_BUNDLE)
                self.assertFalse((self.root / kms.RETRY_ARCHIVE).exists())
                self.assertEqual(self.ops.ownership(), [])

    def test_retry_preserves_foreign_previous_root(self):
        self.seed_previous()
        previous_root = self.root / kms.PREVIOUS_ROOT
        previous_root.symlink_to("/foreign")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertEqual(os.readlink(previous_root), "/foreign")
        self.assertTrue(self.ops.state.exists())
        self.assertFalse((self.root / kms.RETRY_ARCHIVE).exists())

    def test_retry_refuses_stale_grub_and_leftover_old_dropin(self):
        self.seed_previous()
        self.ops.grub.write_text(fixture() + "# foreign\n")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertTrue(self.ops.grub.read_text().endswith("# foreign\n"))
        self.ops.grub.write_text(fixture())
        previous_default = self.root / kms.PREVIOUS_DEFAULT
        previous_default.write_text("foreign\n")
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertEqual(previous_default.read_text(), "foreign\n")
        self.assertFalse((self.root / kms.RETRY_ARCHIVE).exists())

    def assert_retry_survives_interruption(self, point):
        self.seed_previous()
        journal = (self.ops.state / "journal.json").read_bytes()
        original_link, original_rename, original_replace = Path.symlink_to, Path.rename, os.replace

        def symlink(path, target, **kwargs):
            result = original_link(path, target, **kwargs)
            if point == "retain" and path == self.root / kms.PREVIOUS_ROOT:
                raise PowerCut
            return result

        def rename(path, target):
            result = original_rename(path, target)
            if point == "archive" and target == self.root / kms.RETRY_ARCHIVE:
                raise PowerCut
            return result

        def replace(source, target):
            result = original_replace(source, target)
            if point == "select" and target == self.ops.retention:
                raise PowerCut
            return result

        with (
            mock.patch.object(Path, "symlink_to", symlink),
            mock.patch.object(Path, "rename", rename),
            mock.patch.object(os, "replace", replace),
            self.assertRaises(PowerCut),
        ):
            self.ops.apply(True, True)
        self.assertEqual(self.ops.grub.read_text(), fixture())
        self.assertEqual(self.ops.ownership(), [])
        self.assertEqual(self.ops.apply(True, True)["status"], "PERSISTENT_PENDING_REBOOT")
        self.assert_previous_preserved(journal)

    def test_retry_after_interrupted_old_code_retention(self):
        self.assert_retry_survives_interruption("retain")

    def test_retry_after_interrupted_snapshot_archive(self):
        self.assert_retry_survives_interruption("archive")

    def test_retry_after_interrupted_current_code_selection(self):
        self.assert_retry_survives_interruption("select")

    def test_failed_new_attempt_recovers_and_retries_without_losing_history(self):
        self.seed_previous()
        journal = (self.ops.state / "journal.json").read_bytes()
        self.ops.bad_generator = True
        with self.assertRaises(ValueError):
            self.ops.apply(True, True)
        self.assertEqual(self.ops.grub.read_text(), fixture())
        self.assertEqual(self.ops.load()["phase"], "recovered")
        self.assert_previous_preserved(journal)
        self.ops.bad_generator = False
        self.assertEqual(self.ops.apply(True, True)["status"], "PERSISTENT_PENDING_REBOOT")


if __name__ == "__main__":
    unittest.main()
