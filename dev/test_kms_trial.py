"""One-boot KMS policy/transaction tests; only synthetic, temporary boot trees."""

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
spec = importlib.util.spec_from_file_location("kms_trial", ROOT / "root/graphics/kms-trial.py")
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)
PLAN = json.loads((ROOT / "root/graphics/kms-plan.json").read_text())
RELEASE = PLAN["reviewedBoot"]["kernel"]
BUNDLE = "/nix/store/" + "a" * 32 + "-dgx-kms-trial"
NONCE = "b" * 32
BODY = f"""  recordfail
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
  linux /boot/vmlinuz-{RELEASE} root=UUID=PRIVATE-UUID ro iommu.passthrough=0 console=ttyAMA0,115200 earlycon quiet $vt_handoff
  initrd /boot/initrd.img-{RELEASE}
"""
GRUB = (
    """if [ -s $prefix/grubenv ]; then
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
menuentry 'PRIVATE NAME' --id PRIVATE-ID {
"""
    + BODY
    + "}\n"
    + trial.CUSTOM_HOOK
    + "\n"
)


class FakeTrial(trial.Trial):
    def __init__(self, root):
        super().__init__(PLAN, BUNDLE, root)
        self.calls = []
        self.fail_operation = None
        self.fail_after_write = False
        self.fail_syntax = False
        self.preflight_count = 0
        self.drift = False

    def preflight(self):
        self.preflight_count += 1
        if self.drift and self.preflight_count == 2:
            self.grub.write_text(GRUB + "# unrelated update\n")
        trial.require(not os.path.lexists(self.custom), "foreign custom.cfg")
        trial.require(trial.TICKET not in self.env_values(), "foreign marker")
        return {"kernel": RELEASE}

    def check_syntax(self, candidate):
        trial.require(not self.fail_syntax, "syntax failed")

    def run(self, args):
        self.calls.append(args)
        if args[0] != "/usr/bin/grub-editenv":
            raise AssertionError(f"unexpected simulated command: {args[0]}")
        path, action = Path(args[1]), args[2]
        values = json.loads(path.read_text())
        if action == "list":
            return "".join(f"{key}={value}\n" for key, value in values.items())
        operation = action + " " + args[3].split("=", 1)[0]
        fail = operation == self.fail_operation
        if fail:
            self.fail_operation = None
        if fail and not self.fail_after_write:
            raise ValueError("injected failure before environment write")
        for item in args[3:]:
            if action == "set":
                key, value = item.split("=", 1)
                values[key] = value
            elif action == "unset":
                values.pop(item, None)
            else:
                raise AssertionError("unexpected simulated environment operation")
        path.write_text(json.dumps(values))
        if fail:
            raise ValueError("injected failure after environment write")
        return ""


class RenderTests(unittest.TestCase):
    def test_exact_factory_body_is_preserved_except_for_the_added_variable(self):
        rendered = trial.render(GRUB, RELEASE, NONCE).decode()
        suffix = rendered[rendered.index("  recordfail\n") : -2]
        self.assertEqual(suffix.replace(" $sparkwerx_kms_arg\n", "\n"), BODY)
        self.assertEqual(rendered.count(trial.ARGUMENT), 1)
        self.assertNotIn("PRIVATE NAME", rendered)
        self.assertIn("root=UUID=PRIVATE-UUID ro iommu.passthrough=0", rendered)
        self.assertNotIn("set default", rendered)
        self.assertNotIn("--skip-sig", rendered)

    def test_unrecognized_or_conflicting_layouts_are_rejected(self):
        for config in (
            GRUB.replace(trial.CUSTOM_HOOK, ""),
            GRUB + trial.CUSTOM_HOOK,
            GRUB.replace(RELEASE, "other-kernel"),
            GRUB.replace(" ro ", " ro nomodeset "),
            GRUB.replace(" ro ", " ro nvidia-drm.modeset=0 "),
            GRUB.replace(" ro ", " ro -- "),
            GRUB.replace(" ro ", " ro systemd.unit=graphical.target "),
            GRUB.replace("  load_video", "  source /private/other.cfg"),
            GRUB.replace("  load_video", "  function nested {\n  }"),
            GRUB.replace("  load_video", "  initrdfail"),
            GRUB.replace("  initrd ", "  linux "),
            GRUB.replace(" quiet ", " quiet ; reboot "),
            GRUB.replace("menuentry 'PRIVATE", "submenu 'other' {\nmenuentry 'PRIVATE"),
        ):
            with self.subTest(config=config):
                with self.assertRaises(ValueError):
                    trial.render(config, RELEASE, NONCE)
        with self.assertRaises(ValueError):
            trial.render(GRUB, RELEASE, "bad;marker")

    def test_real_grub_parser_accepts_the_synthetic_entry(self):
        checker = shutil.which("grub-script-check")
        if checker is None:
            self.skipTest("native GRUB parser absent; Nix policy supplies it")
        result = subprocess.run(
            [checker], input=trial.render(GRUB, RELEASE, NONCE), capture_output=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def gate(self, *, ticket=NONCE, save=True, load=True, persist=True):
        # Execute the identical conditionals with simulated GRUB primitives.
        # This is algorithm coverage, not EFI firmware/disk-write proof.
        gate = (
            trial.render(GRUB, RELEASE, NONCE)
            .decode()
            .split("\n", 2)[2]
            .split("  recordfail\n", 1)[0]
        )
        script = f"""set() {{ declare -g "$1"; }}
disk_ticket='{ticket}'
sparkwerx_kms_ticket="$disk_ticket"
save_env() {{
  {"true" if save else "return 1"}
  {'disk_ticket="$sparkwerx_kms_ticket"' if persist else ":"}
}}
load_env() {{
  {"true" if load else "return 1"}
  sparkwerx_kms_ticket="$disk_ticket"
}}
{gate}
printf '%s\\n' "$sparkwerx_kms_arg"
sparkwerx_kms_ticket="$disk_ticket"
{gate}
printf '%s\\n' "$sparkwerx_kms_arg"
"""
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_ticket_is_used_once_even_if_the_menu_selection_repeats(self):
        self.assertEqual(self.gate(), [trial.ARGUMENT, ""])

    def test_failed_write_failed_read_stale_ticket_or_missing_ticket_boot_without_kms(self):
        for options in (
            {"save": False},
            {"load": False},
            {"persist": False},
            {"ticket": ""},
            {"ticket": "consumed-" + NONCE},
            {"ticket": "foreign"},
        ):
            with self.subTest(options=options):
                self.assertEqual(self.gate(**options), ["", ""])

    def test_efi_route_requires_the_current_partition_loader_and_forwarder(self):
        uuid = "11111111-1111-1111-1111-111111111111"
        boot = f"BootCurrent: 0004\nBoot0004* ubuntu HD(1,GPT,{uuid},0x800,0x10000)/File(\\EFI\\ubuntu\\shimaa64.efi)\n"
        stub = "search.fs_uuid PRIVATE-ROOT root hd0,gpt2\nset prefix=($root)'/boot/grub'\nconfigfile $prefix/grub.cfg\n"
        trial.efi_route(boot, uuid, stub, "PRIVATE-ROOT")
        for args in (
            (boot.replace("0004\n", "0005\n"), uuid, stub, "PRIVATE-ROOT"),
            (boot, "different", stub, "PRIVATE-ROOT"),
            (boot.replace("ubuntu\\shimaa64", "other\\shimaa64"), uuid, stub, "PRIVATE-ROOT"),
            (boot, uuid, stub.replace("PRIVATE-ROOT", "different"), "PRIVATE-ROOT"),
            (boot, uuid, stub + "source /other\n", "PRIVATE-ROOT"),
        ):
            with self.subTest(args=args):
                with self.assertRaises(ValueError):
                    trial.efi_route(*args)


class TransactionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="sparkwerx-kms-test-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(trial, "OWNER", os.getuid()).start()
        self.ops = FakeTrial(root)
        for path in (
            self.ops.state.parent,
            self.ops.custom.parent,
            self.ops.boot_id.parent,
            root / "nix/var/nix/gcroots",
            root / "sys/module/nvidia_drm/parameters",
        ):
            path.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.ops.grub.write_text(GRUB)
        self.ops.env.write_text(json.dumps({"saved_entry": "PRIVATE-EXISTING"}))
        self.ops.grub.chmod(0o600)
        self.ops.env.chmod(0o600)
        self.ops.boot_id.write_text("original-boot\n")
        self.mode = root / "sys/module/nvidia_drm/parameters/modeset"
        self.mode.write_text("N\n")

    def test_missing_console_attestation_makes_no_changes(self):
        with self.assertRaises(ValueError):
            self.ops.arm(False)
        self.assertFalse(self.ops.state.exists())
        self.assertFalse(self.ops.custom.exists())
        self.assertEqual(self.ops.calls, [])

    def test_arm_snapshots_then_selects_without_changing_normal_grub_or_mode(self):
        result = self.ops.arm(True)
        self.assertEqual(result["status"], "ARMED_FOR_ONE_BOOT")
        self.assertEqual(self.ops.grub.read_text(), GRUB)
        self.assertEqual(self.mode.read_text(), "N\n")
        self.assertEqual(self.ops.custom.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.ops.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.ops.env_values()["saved_entry"], "PRIVATE-EXISTING")
        changes = [call[2:] for call in self.ops.calls if call[2] != "list"]
        self.assertEqual(changes[0][0], "set")
        self.assertTrue(changes[0][1].startswith(trial.TICKET + "="))
        self.assertEqual(changes[1], ["set", "next_entry=" + trial.ENTRY])
        self.assertNotIn("PRIVATE", json.dumps(result))
        before = self.ops.env.read_bytes()
        self.assertEqual(self.ops.arm(True)["status"], "ARMED_FOR_ONE_BOOT")
        self.assertEqual(before, self.ops.env.read_bytes())

    def test_existing_empty_next_entry_is_not_misclassified_as_unrelated_drift(self):
        self.ops.change_env("set", "next_entry=")
        self.assertEqual(self.ops.arm(True)["status"], "ARMED_FOR_ONE_BOOT")
        self.assertEqual(self.ops.cancel()["status"], "CANCELED")

    def test_real_grub_environment_tool_on_temporary_files(self):
        executable = shutil.which("grub-editenv")
        if executable is None:
            self.skipTest("native GRUB environment tool absent; Nix policy supplies it")
        root = self.ops.root

        def native_run(args):
            self.assertEqual(args[0], "/usr/bin/grub-editenv")
            self.assertTrue(Path(args[1]).resolve().is_relative_to(root))
            result = subprocess.run(
                [executable, *args[1:]], capture_output=True, text=True, check=False
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

        native_run(["/usr/bin/grub-editenv", str(self.ops.env), "create"])
        # Creation follows the developer's umask; the real host preflight
        # requires a root-owned, non-group-writable existing environment file.
        self.ops.env.chmod(0o600)
        with mock.patch.object(self.ops, "run", side_effect=native_run):
            self.ops.change_env(
                "set", "saved_entry=PRIVATE-EXISTING", "next_entry=", "unrelated=PRIVATE-OTHER"
            )
            self.assertEqual(self.ops.arm(True)["status"], "ARMED_FOR_ONE_BOOT")
            self.assertEqual(self.ops.cancel()["status"], "CANCELED")
            self.assertEqual(
                self.ops.env_values(),
                {"saved_entry": "PRIVATE-EXISTING", "unrelated": "PRIVATE-OTHER"},
            )

    def test_failed_snapshot_publication_leaves_no_active_journal_or_boot_selection(self):
        original_publish = trial.publish

        def failed_snapshot(path, data, **kwargs):
            if path.name == "journal.json":
                raise OSError("injected snapshot write failure")
            return original_publish(path, data, **kwargs)

        with mock.patch.object(trial, "publish", side_effect=failed_snapshot):
            with self.assertRaises(OSError):
                self.ops.arm(True)
        self.assertFalse(self.ops.state.exists())
        self.assertFalse(self.ops.custom.exists())
        self.assertEqual(self.ops.env_values(), {"saved_entry": "PRIVATE-EXISTING"})
        self.assertEqual(self.ops.arm(True)["status"], "ARMED_FOR_ONE_BOOT")

    def test_syntax_or_foreign_custom_file_fail_before_snapshot_or_selection(self):
        self.ops.fail_syntax = True
        with self.assertRaises(ValueError):
            self.ops.arm(True)
        self.assertFalse(self.ops.state.exists())
        self.ops.custom.write_text("foreign data")
        with self.assertRaises(ValueError):
            self.ops.arm(True)
        self.assertEqual(self.ops.custom.read_text(), "foreign data")

    def test_partial_environment_writes_are_revoked_and_private_evidence_remains(self):
        for after in (False, True):
            for operation in ("set " + trial.TICKET, "set next_entry"):
                with self.subTest(after=after, operation=operation):
                    self.ops.fail_operation = operation
                    self.ops.fail_after_write = after
                    with self.assertRaises(ValueError):
                        self.ops.arm(True)
                    self.assertFalse(self.ops.custom.exists())
                    self.assertEqual(self.ops.env_values(), {"saved_entry": "PRIVATE-EXISTING"})
                    self.assertEqual(self.ops.status()["status"], "CANCELED")
                    self.assertEqual(self.ops.grub.read_text(), GRUB)

    def test_bootloader_consumption_is_separate_from_loaded_kms(self):
        self.ops.arm(True)
        nonce = self.ops.load()["nonce"]
        self.ops.boot_id.write_text("new-boot\n")
        self.ops.change_env("unset", "next_entry")
        self.ops.change_env("set", f"{trial.TICKET}=consumed-{nonce}")
        self.assertEqual(self.ops.status()["status"], "BOOT_NEEDS_REVIEW")
        self.mode.write_text("Y\n")
        self.assertEqual(self.ops.status()["status"], "KMS_TEST_BOOT")
        self.ops.grub.write_text(GRUB + "# update\n")
        self.assertEqual(self.ops.status()["status"], "BOOT_NEEDS_REVIEW")

    def test_driver_startup_failure_does_not_block_cancellation(self):
        self.ops.arm(True)
        self.mode.unlink()
        self.assertEqual(self.ops.status()["modeset"], "unavailable")
        self.assertEqual(self.ops.cancel()["status"], "CANCELED")
        self.assertFalse(self.ops.custom.exists())

    def test_resume_after_last_environment_write_before_final_journal_update(self):
        self.ops.arm(True)
        data = self.ops.load()
        data["phase"] = "prepared"
        self.ops.journal(data)
        env = self.ops.env.read_bytes()
        self.assertEqual(self.ops.arm(True)["status"], "ARMED_FOR_ONE_BOOT")
        self.assertEqual(self.ops.load()["phase"], "armed")
        self.assertEqual(self.ops.env.read_bytes(), env)

    def test_cancel_revokes_first_preserves_other_env_and_does_not_reload_kms(self):
        self.ops.arm(True)
        self.mode.write_text("Y\n")
        self.ops.change_env("set", "unrelated=PRIVATE-NEW")
        self.ops.calls.clear()
        result = self.ops.cancel()
        self.assertEqual(result["status"], "CANCELED")
        changes = [call[2:] for call in self.ops.calls if call[2] != "list"]
        self.assertEqual(changes, [["unset", trial.TICKET], ["unset", "next_entry"]])
        self.assertEqual(self.mode.read_text(), "Y\n")
        self.assertFalse(self.ops.custom.exists())
        self.assertEqual(
            self.ops.env_values(), {"saved_entry": "PRIVATE-EXISTING", "unrelated": "PRIVATE-NEW"}
        )
        journal = (self.ops.state / "journal.json").stat().st_mtime_ns
        self.ops.cancel()
        self.assertEqual((self.ops.state / "journal.json").stat().st_mtime_ns, journal)

    def test_foreign_selection_or_custom_file_blocks_cleanup_without_overwrite(self):
        self.ops.arm(True)
        original = self.ops.custom.read_bytes()
        self.ops.custom.write_text("foreign replacement")
        env = self.ops.env.read_bytes()
        with self.assertRaises(ValueError):
            self.ops.cancel()
        self.assertEqual(self.ops.env.read_bytes(), env)
        self.ops.custom.write_bytes(original)
        self.ops.change_env("set", "next_entry=foreign-selection")
        with self.assertRaises(ValueError):
            self.ops.cancel()
        self.assertTrue(self.ops.custom.exists())

    def test_snapshot_tampering_is_rejected(self):
        self.ops.arm(True)
        (self.ops.state / "grub.cfg.before").write_text("tampered")
        with self.assertRaises(ValueError):
            self.ops.cancel()
        self.assertTrue(self.ops.custom.exists())

    def test_preflight_drift_cancels_only_our_preparation(self):
        self.ops.drift = True
        with self.assertRaises(ValueError):
            self.ops.arm(True)
        self.assertFalse(self.ops.custom.exists())
        self.assertTrue(self.ops.grub.read_text().endswith("# unrelated update\n"))
        self.assertEqual(self.ops.status()["status"], "CANCELED")

    def test_interrupted_cancel_can_be_retried_without_losing_evidence(self):
        self.ops.arm(True)
        self.ops.fail_operation = "unset next_entry"
        with self.assertRaises(ValueError):
            self.ops.cancel()
        self.assertNotIn(trial.TICKET, self.ops.env_values())
        self.assertTrue(self.ops.custom.exists())
        self.assertEqual(self.ops.cancel()["status"], "CANCELED")

    def test_clean_retry_archives_the_previous_snapshot_and_retains_its_code_root(self):
        self.ops.arm(True)
        nonce = self.ops.load()["nonce"]
        self.ops.cancel()
        self.assertEqual(self.ops.arm(True)["status"], "ARMED_FOR_ONE_BOOT")
        self.assertTrue(
            (self.ops.state.parent / "kms-trial-history" / nonce / "journal.json").is_file()
        )
        self.assertEqual(len(list((self.ops.root / "nix/var/nix/gcroots").iterdir())), 2)

    def test_atomic_publication_refuses_foreign_files_and_symlinks(self):
        self.ops.custom.write_text("foreign")
        with self.assertRaises(FileExistsError):
            trial.publish(self.ops.custom, b"new")
        self.assertEqual(self.ops.custom.read_text(), "foreign")
        link = self.ops.custom.parent / "foreign-link"
        link.symlink_to(self.ops.custom)
        with self.assertRaises(ValueError):
            trial.read_owned(link)
        with self.assertRaises(FileExistsError):
            trial.publish(link, b"new")


if __name__ == "__main__":
    unittest.main()
