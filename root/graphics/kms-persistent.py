"""Opt-in Ubuntu GRUB adapter. No reboot, module reload, or desktop operation."""

import argparse
import fcntl
import importlib.util
import json
import os
import re
import signal
import stat
import subprocess
import sys
import tempfile
from contextlib import ExitStack
from pathlib import Path

spec = importlib.util.spec_from_file_location("kms_trial", Path(__file__).with_name("kms-trial.py"))
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)
require = trial.require

FALLBACK_ID = "sparkwerx-factory-kms-off"
ARG_ON = "nvidia_drm.modeset=1"
ARG_OFF = "nvidia_drm.modeset=0"
LINKS = ("etc/grub.d/42_sparkwerx_kms", "etc/default/grub.d/zz-sparkwerx-kms.cfg")
ROOT_LINK = "nix/var/nix/gcroots/dgx-setup-kms-persistent"
SECTION = re.compile(r"^### BEGIN (/etc/grub.d/[^\n]+) ###\n(.*?)^### END \1 ###\n", re.M | re.S)

# Recovery identity for the FIRST failed persistent-KMS attempt, not a moving
# package dependency or a generic update allowlist. Its menu ordering failed
# before GRUB publication, and automatic recovery removed its two links. A
# corrected enable may archive only that exact recovered initial transaction;
# never accept an active, interrupted, unknown, or stale predecessor here.
PREVIOUS_BUNDLE = "/nix/store/kzjrqwgbbji4xbs7sibmh7fqsrc0xkj4-dgx-kms-persistent"
PREVIOUS_CONFIGURATION = (
    "/nix/store/27nywkkszswmpsj37191zb80nhszk30g-dgx-kms-persistent-configuration"
)
PREVIOUS_DEFAULT = "etc/default/grub.d/90-sparkwerx-kms.cfg"
RETRY_ARCHIVE = "var/lib/dgx-setup/kms-persistent-before-menu-fix"
PREVIOUS_ROOT = ROOT_LINK + "-before-menu-fix"


def first_body(config):
    """Reuse the strict, tested Ubuntu entry parser; infer the generated kernel."""
    matches = re.findall(r"^\s*linux(?:efi)?\s+(?:/boot)?/vmlinuz-([\w.+-]+)\s", config, re.M)
    require(bool(matches), "no supported Ubuntu kernel entry")
    # Only remove our one literal argument; other NVIDIA arguments are refused
    # by the existing parser. No shell evaluation or raw arguments in errors.
    clean = re.sub(r"(?<=\s)nvidia_drm\.modeset=[01](?=\s|$)", "", config)
    clean = clean.replace(trial.CUSTOM_HOOK, "") + "\n" + trial.CUSTOM_HOOK
    body, linux = trial.factory_entry(clean, matches[0])
    body[linux] = re.sub(r"\s+", " ", body[linux].strip()) + "\n"
    return body, linux


def render_fallback(generated):
    body, linux = first_body(generated)
    body[linux] = body[linux].rstrip() + " " + ARG_OFF + "\n"
    return (
        f"menuentry 'Sparkwerx: factory settings (NVIDIA KMS off)' --id {FALLBACK_ID} {{\n"
        + "".join(body)
        + "}\n"
    )


def run(args, *, env=None, data=None):
    result = subprocess.run(
        args, input=data, env=env, capture_output=True, text=True, timeout=180, check=False
    )
    require(result.returncode == 0, f"{Path(args[0]).name} failed; raw boot output withheld")
    require(len(result.stdout) <= 2 * 1024 * 1024, "generated boot output exceeds size limit")
    return result.stdout


def fallback():
    # grub-mkconfig sources the Nix drop-in and exports its variables. Run the
    # vendor generator again, then emit ONLY a renamed copy of its first entry.
    # This tracks the current kernel/initrd/UUID on every Ubuntu update-grub.
    # No saved boot image, duplicate normal IDs, grubenv write, or firmware edit.
    args = (
        os.environ.get("GRUB_CMDLINE_LINUX", "")
        + " "
        + os.environ.get("GRUB_CMDLINE_LINUX_DEFAULT", "")
    ).split()
    require(args.count(ARG_ON) == 1, "KMS fallback requires exactly one enable argument")
    require(
        not any(
            word != ARG_ON
            and (word.startswith(("nvidia_drm.", "nvidia-drm.")) or word == "nomodeset")
            for word in args
        ),
        "conflicting KMS argument in GRUB settings",
    )
    trial.read_owned(Path("/etc/grub.d/10_linux"))
    print(render_fallback(run(["/etc/grub.d/10_linux"])), end="")


def sections(text):
    found = list(SECTION.finditer(text))
    require(bool(found), "generated GRUB section markers are absent")
    result = {item[1]: item[2] for item in found}
    require(len(found) == len(result), "duplicate generated GRUB section")
    return result


def without_kms(text):
    return re.sub(r"(?<=\s)nvidia_drm\.modeset=1(?=\s|$)", "", text)


def normalize_space(text):
    return "\n".join(" ".join(line.split()) for line in text.splitlines())


def check_menu(header):
    styles = re.findall(r"(?m)^[ \t]*set timeout_style=([^\s]+)[ \t]*$", header)
    require(styles and set(styles) == {"menu"}, "fallback menu is not visible")
    timeouts = re.findall(r"(?m)^[ \t]*set timeout=([^\s]+)[ \t]*$", header)
    require(
        timeouts and all(value.isdecimal() and 5 <= int(value) <= 30 for value in timeouts),
        "fallback menu timeout missing or outside 5-30 seconds",
    )


def verify_change(factory, enabled):
    """Prove the only functional changes are KMS, menu timeout, and fallback."""
    before, after = sections(factory), sections(enabled)
    hook = "/etc/grub.d/42_sparkwerx_kms"
    require(hook not in before and hook in after, "unexpected fallback section ownership")
    require(set(after) == set(before) | {hook}, "unrelated GRUB generator added/removed")
    # Protect bytes outside the generator sections too.
    require(
        SECTION.sub("", factory).split() == SECTION.sub("", enabled).split(),
        "GRUB outer structure changed",
    )
    for name in before:
        if name == "/etc/grub.d/10_linux":
            require(
                ARG_ON not in before[name] and ARG_OFF not in before[name],
                "factory KMS arguments need review",
            )
            require(
                normalize_space(before[name]) == normalize_space(without_kms(after[name])),
                "unrelated Linux entry change",
            )
            normal = re.findall(r"^\s*linux(?:efi)?\s+.*$", after[name], re.M)
            require(normal and ARG_ON in normal[0].split(), "default kernel lacks KMS argument")
            for line in normal:
                require(line.split().count(ARG_ON) <= 1, "duplicate KMS argument")
                require(
                    "nomodeset" not in line.split() or ARG_ON not in line.split(),
                    "recovery entry unexpectedly enables KMS",
                )
        elif name == "/etc/grub.d/00_header":
            # Ubuntu changes its legacy hidden-timeout `elif sleep` into
            # `else` for a visible menu. Normalize only that exact fallback,
            # timeout assignments, and comments; preserve all other logic.
            def header(value):
                value = re.sub(
                    r"(?m)^(\s*)elif sleep(?: --verbose)? --interruptible [0-9]+ ; then$",
                    r"\1else",
                    value,
                )
                return "\n".join(
                    line
                    for line in value.splitlines()
                    if not re.match(r"\s*(?:#|set timeout(?:_style)?=)", line)
                )

            require(
                header(before[name]) == header(after[name]),
                "GRUB header change exceeds menu timeout",
            )
            check_menu(after[name])
            require('set default="0"' in after[name], "nonstandard default selection needs review")
        else:
            require(before[name] == after[name], "unrelated GRUB section changed")
    expected = render_fallback(after["/etc/grub.d/10_linux"])
    require(
        after[hook].strip() == expected.strip(), "fallback differs from the current default kernel"
    )
    require(enabled.count("--id " + FALLBACK_ID) == 1, "fallback entry is not unique")


def check_enabled(config):
    parts = sections(config)
    hook = "/etc/grub.d/42_sparkwerx_kms"
    require(hook in parts and "/etc/grub.d/10_linux" in parts, "persistent GRUB sections missing")
    require(
        parts[hook].strip() == render_fallback(parts["/etc/grub.d/10_linux"]).strip(),
        "fallback is stale or modified",
    )
    first = re.search(r"^\s*linux(?:efi)?\s+.*$", parts["/etc/grub.d/10_linux"], re.M)
    require(
        first and first[0].split().count(ARG_ON) == 1,
        "default boot does not enable KMS exactly once",
    )
    require(config.count("--id " + FALLBACK_ID) == 1, "fallback entry is not unique")
    require("/etc/grub.d/00_header" in parts, "persistent GRUB header missing")
    check_menu(parts["/etc/grub.d/00_header"])


def file_hash(path):
    # Kernel/initrd images exceed the boot-text inspection size limit.
    trial.directory(path.parent)
    info = path.lstat()
    require(
        stat.S_ISREG(info.st_mode) and info.st_uid == trial.OWNER and not info.st_mode & 0o022,
        "unsafe factory input",
    )
    import hashlib

    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


class Persistent:
    def __init__(self, plan, configuration, bundle, root=Path("/")):
        # root/fake methods are test injection only; never exposed on the CLI.
        self.plan, self.configuration, self.bundle, self.root = plan, configuration, bundle, root
        self.state = root / "var/lib/dgx-setup/kms-persistent"
        self.grub = root / "boot/grub/grub.cfg"
        self.retention = root / ROOT_LINK

    def targets(self):
        return {self.root / name: str(Path(self.configuration) / name) for name in LINKS}

    def ownership(self):
        present = []
        for path, target in self.targets().items():
            if os.path.lexists(path):
                require(
                    path.is_symlink()
                    and os.readlink(path) == target
                    and path.lstat().st_uid == trial.OWNER,
                    "foreign KMS configuration collision",
                )
                present.append(str(path.relative_to(self.root)))
        return present

    def fingerprint(self):
        names = {
            "etc/default/grub",
            "etc/modprobe.d/zz-nvidia-drm-override.conf",
            "etc/gdm3/custom.conf",
            "usr/sbin/grub-mkconfig",
            "usr/share/grub/grub-mkconfig_lib",
            "boot/efi/EFI/ubuntu/grub.cfg",
        }
        for folder in ("etc/default/grub.d", "etc/grub.d"):
            trial.directory(self.root / folder)
            names.update(
                str(p.relative_to(self.root))
                for p in (self.root / folder).iterdir()
                if p.name != "README"
            )
        for pattern in ("vmlinuz-*", "initrd.img-*"):
            names.update(str(p.relative_to(self.root)) for p in (self.root / "boot").glob(pattern))
        if os.path.lexists(self.root / "boot/grub/custom.cfg"):
            names.add("boot/grub/custom.cfg")
        result = {name: file_hash(self.root / name) for name in sorted(names - set(LINKS))}
        result["system-manager-profile"] = str(
            (self.root / str(trial.kms.PROFILE).lstrip("/")).resolve(strict=True)
        )
        return result

    def environment(self):
        env = self.root / "boot/grub/grubenv"
        trial.read_owned(env)
        values = trial.environment(run(["/usr/bin/grub-editenv", str(env), "list"]))
        require(
            not any(values.get(key) for key in ("next_entry", "prev_entry", "prev_saved_entry")),
            "pending GRUB selection; preserve it and inspect first",
        )
        return values

    def health(self):
        report = trial.kms.inspect(self.plan)
        # KMS may already be loaded by the separately approved one-boot trial.
        report["modeset"] = "N"
        require(
            not trial.kms.review_findings(report), "host boot/access/desktop preflight needs review"
        )
        run(["/usr/bin/nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"])
        state = json.loads(run(["/usr/bin/tailscale", "status", "--json"]))
        require(
            state.get("BackendState") == "Running" and state.get("Self", {}).get("Online") is True,
            "Tailscale access is not healthy",
        )

    def initial_check(self, *, allow_previous=False):
        self.health()
        self.environment()
        if os.path.lexists(self.retention):
            require(
                self.retention.is_symlink()
                and self.retention.lstat().st_uid == trial.OWNER
                and os.readlink(self.retention)
                in ({self.bundle, PREVIOUS_BUNDLE} if allow_previous else {self.bundle}),
                "foreign KMS retention root",
            )
        require(not self.ownership(), "KMS configuration already exists")
        require(
            trial.digest(trial.read_owned(self.grub)) == self.plan["reviewedBoot"]["configSha256"],
            "initial GRUB configuration changed since boot review",
        )
        # Validate, but do not retire, the consumed one-boot experiment.
        old = trial.Trial(self.plan, "unused", self.root)
        if os.path.lexists(old.state):
            data = old.load()
            values = old.surface(data)
            require(
                data["phase"] == "canceled"
                or values.get(trial.TICKET) == "consumed-" + data["nonce"],
                "one-boot trial is not consumed/canceled",
            )
        trial.efi_route(
            run(["/usr/bin/efibootmgr", "-v"]),
            run(
                [
                    "/usr/bin/findmnt",
                    "--noheadings",
                    "--output",
                    "PARTUUID",
                    "--target",
                    "/boot/efi",
                ]
            ),
            trial.read_owned(self.root / "boot/efi/EFI/ubuntu/grub.cfg").decode(),
            run(["/usr/sbin/grub-probe", "--target=fs_uuid", str(self.grub)]),
        )

    def generate(self):
        # stdout only: grub-mkconfig's -o path uses an in-place write. We first
        # validate complete output, then atomically publish on /boot's filesystem.
        env = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LANG": "C", "LC_ALL": "C"}
        return run(["/usr/sbin/grub-mkconfig"], env=env)

    def syntax(self, text):
        run(["/usr/bin/grub-script-check"], data=text)

    def journal(self, data):
        path = self.state / "journal.json"
        trial.publish(
            path, (json.dumps(data, sort_keys=True) + "\n").encode(), replace=path.exists()
        )

    def load(self):
        trial.directory(self.state)
        require(
            stat.S_IMODE(self.state.stat().st_mode) == 0o700, "KMS recovery state must be private"
        )
        data = json.loads(trial.read_owned(self.state / "journal.json"))
        require(
            data.get("schema") == 1
            and data.get("phase") in ("prepared", "enabled", "disabled", "recovered"),
            "unsupported KMS recovery state",
        )
        require(
            data.get("bundle") == self.bundle and data.get("configuration") == self.configuration,
            "use the retained KMS operator for this transaction",
        )
        require(
            self.retention.is_symlink() and os.readlink(self.retention) == self.bundle,
            "KMS recovery code is not retained",
        )
        require(
            re.fullmatch(r"txn-[a-zA-Z0-9_-]+", data.get("transaction", "")),
            "invalid private transaction name",
        )
        for name, checksum in data["hashes"].items():
            require(name in ("before", "after", "baseline"), "unexpected recovery file")
            require(
                trial.digest(trial.read_owned(self.state / data["transaction"] / name)) == checksum,
                "KMS snapshot checksum mismatch",
            )
        return data

    def links(self, wanted):
        self.ownership()  # Validate every target BEFORE touching the first one.
        for path, target in self.targets().items():
            trial.directory(path.parent)
            if wanted and not os.path.lexists(path):
                path.symlink_to(target)
                trial.fsync_directory(path.parent)
            elif not wanted and os.path.lexists(path):
                path.unlink()
                trial.fsync_directory(path.parent)

    def replace_grub(self, text, expected):
        require(
            trial.read_owned(self.grub) == expected, "GRUB changed concurrently; will not overwrite"
        )
        mode = stat.S_IMODE(self.grub.stat().st_mode)
        fd, temp = tempfile.mkstemp(prefix=".sparkwerx-kms-", dir=self.grub.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(text)
                stream.flush()
                os.fchmod(stream.fileno(), mode)
                os.fsync(stream.fileno())
            require(trial.read_owned(self.grub) == expected, "GRUB changed during publication")
            os.replace(temp, self.grub)
            trial.fsync_directory(self.grub.parent)
        finally:
            if os.path.lexists(temp):
                os.unlink(temp)

    def recover(self):
        data = self.load()
        require(data["phase"] == "prepared", "no interrupted KMS transaction to recover")
        require(
            self.fingerprint() == data["inputs"],
            "factory boot inputs changed; will not restore stale GRUB",
        )
        self.environment()
        self.ownership()
        current = trial.read_owned(self.grub)
        require(
            trial.digest(current)
            in [data["hashes"][name] for name in ("before", "after") if name in data["hashes"]],
            "GRUB drift; preserve recovery files for review",
        )
        before = trial.read_owned(self.state / data["transaction"] / "before")
        # Restore a complete boot file first. Removing our links afterwards
        # cannot leave a half-written or missing grub.cfg.
        self.replace_grub(before, current)
        self.links(data["wasEnabled"])
        data["phase"] = "recovered"
        self.journal(data)
        return {"status": "TRANSACTION_RECOVERED", "bootConfigurationRestored": True}

    def prepare_retry(self, *, dry_run=False):
        """Preserve the exact recovered menu-order attempt before a fresh enable.

        The old snapshot and executable remain under explicit archive/root
        paths. Each step can be retried after interruption; none touches /etc,
        grub.cfg, or the old journal. This is not active-configuration migration.
        """
        archive = self.root / RETRY_ARCHIVE
        old_root = self.root / PREVIOUS_ROOT
        if os.path.lexists(self.state):
            trial.directory(self.state)
            data = json.loads(trial.read_owned(self.state / "journal.json"))
            if data.get("bundle") == self.bundle:
                return False
            require(not os.path.lexists(archive), "KMS retry archive collision")
            previous_state = self.state
        elif os.path.lexists(archive):
            previous_state = archive
        else:
            return False

        old = Persistent(self.plan, PREVIOUS_CONFIGURATION, PREVIOUS_BUNDLE, self.root)
        old.state = previous_state
        old.retention = old_root if previous_state == archive else self.retention
        data = old.load()  # Exact predecessor identity, private journal, and checksums.
        require(
            data["phase"] == "recovered"
            and data.get("wasEnabled") is False
            and set(data["hashes"]) == {"before", "baseline"}
            and data["hashes"]["before"]
            == data["hashes"]["baseline"]
            == self.plan["reviewedBoot"]["configSha256"],
            "retry requires the exact recovered initial attempt; use the retained operator",
        )
        require(
            not any(os.path.lexists(self.root / name) for name in (*LINKS, PREVIOUS_DEFAULT)),
            "retry refuses active or partial KMS configuration",
        )
        require(self.fingerprint() == data["inputs"], "retry refuses changed factory boot inputs")
        require(
            trial.read_owned(self.grub)
            == trial.read_owned(previous_state / data["transaction"] / "before"),
            "retry requires exact recovered factory GRUB",
        )
        self.initial_check(allow_previous=True)
        trial.directory(old_root.parent)
        if os.path.lexists(old_root):
            require(
                old_root.is_symlink()
                and old_root.lstat().st_uid == trial.OWNER
                and os.readlink(old_root) == PREVIOUS_BUNDLE,
                "foreign previous KMS retention root",
            )
        if dry_run:
            return True
        if not os.path.lexists(old_root):
            old_root.symlink_to(PREVIOUS_BUNDLE)
            trial.fsync_directory(old_root.parent)
        if previous_state == self.state:
            require(not os.path.lexists(archive), "KMS retry archive appeared concurrently")
            self.state.rename(archive)
            trial.fsync_directory(archive.parent)
        require(
            self.retention.is_symlink()
            and self.retention.lstat().st_uid == trial.OWNER
            and os.readlink(self.retention) in {PREVIOUS_BUNDLE, self.bundle},
            "KMS retention changed during retry preparation",
        )
        # The old code is already independently rooted and its complete state
        # archived. Atomic replacement never leaves the current root missing.
        if os.readlink(self.retention) != self.bundle:
            with tempfile.TemporaryDirectory(
                prefix=".kms-retry-", dir=self.retention.parent
            ) as temp:
                selected = Path(temp) / "selected"
                selected.symlink_to(self.bundle)
                os.replace(selected, self.retention)
                trial.fsync_directory(self.retention.parent)
        print(
            "PASS|retry|previous recovered snapshot and code retained; corrected candidate selected"
        )
        return True

    def apply(self, enabled, console_ready=False):
        require(
            not enabled or console_ready,
            "enable requires --console-ready for independent keyboard/display/power recovery",
        )
        require(
            all(Path(target).is_file() for target in self.targets().values()),
            "KMS is not selected in the Nix configuration",
        )
        if enabled:
            self.prepare_retry()
        if self.state.exists():
            previous = self.load()
            require(previous["phase"] != "prepared", "interrupted transaction; run recover first")
            self.health()
        else:
            self.initial_check()
        environment_before = self.environment()
        present = self.ownership()
        require(len(present) in (0, 2), "partial KMS ownership; run recover")
        was_enabled = bool(present)
        if was_enabled == enabled:
            return self.status()
        inputs = self.fingerprint()
        before = trial.read_owned(self.grub)
        baseline = self.generate()
        # Regenerating the current state must be exact before any ownership
        # changes. Kernel/default/package drift is a review, not silent repair.
        require(
            baseline.encode() == before,
            "current GRUB differs from fresh factory generation; no configuration changed",
        )
        self.syntax(baseline)
        require(self.fingerprint() == inputs, "factory inputs changed during generation")
        require(
            self.environment() == environment_before, "GRUB environment changed during generation"
        )
        if os.path.lexists(self.retention):
            require(
                self.retention.is_symlink() and os.readlink(self.retention) == self.bundle,
                "foreign KMS retention root",
            )
        new_state = not self.state.exists()
        state_dir = (
            Path(tempfile.mkdtemp(prefix=".kms-persistent-", dir=self.state.parent))
            if new_state
            else self.state
        )
        trial.directory(state_dir)
        transaction = Path(tempfile.mkdtemp(prefix="txn-", dir=state_dir))
        trial.publish(transaction / "before", before)
        trial.publish(transaction / "baseline", baseline.encode())
        data = {
            "schema": 1,
            "phase": "prepared",
            "bundle": self.bundle,
            "configuration": self.configuration,
            "transaction": transaction.name,
            "wasEnabled": was_enabled,
            "inputs": inputs,
            "hashes": {"before": trial.digest(before), "baseline": trial.digest(baseline.encode())},
        }
        if not os.path.lexists(self.retention):
            trial.directory(self.retention.parent)
            self.retention.symlink_to(self.bundle)
            trial.fsync_directory(self.retention.parent)
        require(
            self.retention.is_symlink() and os.readlink(self.retention) == self.bundle,
            "foreign KMS retention root",
        )
        if new_state:
            trial.publish(
                state_dir / "journal.json", (json.dumps(data, sort_keys=True) + "\n").encode()
            )
            require(not os.path.lexists(self.state), "KMS recovery state appeared concurrently")
            state_dir.rename(self.state)
            trial.fsync_directory(self.state.parent)
            transaction = self.state / transaction.name
        else:
            self.journal(data)
        # Complete recovery material exists BEFORE changing /etc.
        try:
            self.links(enabled)
            candidate = self.generate()
            # Keep failed comparison evidence private too; never paste raw boot
            # arguments into the error message or lose them on rollback.
            trial.publish(transaction / "generated", candidate.encode())
            verify_change(baseline if enabled else candidate, candidate if enabled else baseline)
            self.syntax(candidate)
            require(
                self.fingerprint() == inputs, "factory inputs changed; refusing GRUB publication"
            )
            require(
                self.environment() == environment_before,
                "GRUB environment changed during generation",
            )
            trial.publish(transaction / "after", candidate.encode())
            data["hashes"]["after"] = trial.digest(candidate.encode())
            self.journal(data)
            self.replace_grub(candidate.encode(), before)
            self.health()
            require(
                self.environment() == environment_before,
                "GRUB environment changed during postflight",
            )
            require(self.fingerprint() == inputs, "factory input drift during postflight")
            require(
                self.ownership() == (list(LINKS) if enabled else []),
                "configuration postflight mismatch",
            )
            require(trial.read_owned(self.grub) == candidate.encode(), "GRUB postflight mismatch")
            data["phase"] = "enabled" if enabled else "disabled"
            self.journal(data)
        except (Exception, KeyboardInterrupt):
            try:
                self.recover()
                print(
                    "PASS|recovery|exact pre-transaction boot configuration restored",
                    file=sys.stderr,
                )
            except Exception:
                print(
                    "RECOVERY_REQUIRED: run dgx-kms-persistent recover; do not reboot or delete its snapshot.",
                    file=sys.stderr,
                )
            raise
        return self.status()

    def status(self):
        if not self.state.exists():
            require(not self.ownership(), "KMS links exist without recovery state")
            return {"status": "FACTORY_DEFAULT", "persistentConfiguration": False}
        data = self.load()
        if data["phase"] == "prepared":
            return {"status": "RECOVERY_REQUIRED", "snapshot": str(self.state)}
        present = self.ownership()
        require(len(present) in (0, 2), "partial KMS configuration")
        config = trial.read_owned(self.grub).decode()
        if present:
            check_enabled(config)
        else:
            require(
                FALLBACK_ID not in config and ARG_ON not in config,
                "GRUB does not match factory configuration",
            )
        loaded = trial.kms.kernel_boolean(
            (self.root / "sys/module/nvidia_drm/parameters/modeset").read_text()
        )
        return {
            "status": ("PERSISTENT_KMS_ACTIVE" if loaded == "Y" else "PERSISTENT_PENDING_REBOOT")
            if present
            else ("FACTORY_PENDING_REBOOT" if loaded == "Y" else "FACTORY_DEFAULT"),
            "persistentConfiguration": bool(present),
            "modeset": loaded,
            "fallbackEntry": FALLBACK_ID if present else None,
            "snapshot": str(self.state),
            "rebootPerformed": False,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action", choices=("plan", "check", "enable", "disable", "recover", "status", "fallback")
    )
    parser.add_argument("--configuration")
    parser.add_argument("--bundle")
    parser.add_argument("--plan-file", type=Path)
    parser.add_argument("--console-ready", action="store_true")
    args = parser.parse_args()
    if args.action == "fallback":
        fallback()
        return
    require(
        args.configuration and args.bundle and args.plan_file, "missing Nix package configuration"
    )
    require(args.action == "enable" or not args.console_ready, "--console-ready is only for enable")
    require(
        re.fullmatch(r"/nix/store/[a-z0-9]{32}-dgx-kms-persistent", args.bundle),
        "unexpected operator bundle",
    )
    plan = json.loads(args.plan_file.read_text())
    if args.action == "plan":
        print(
            json.dumps(
                {
                    "selected": all((Path(args.configuration) / name).is_file() for name in LINKS),
                    "defaultPolicy": "preserve-factory",
                    "host": plan["pilotHost"],
                    "managedFiles": ["/" + name for name in LINKS],
                    "generatedFile": "/boot/grub/grub.cfg",
                    "fallback": FALLBACK_ID,
                    "rebootPerformed": False,
                    "driverReplaced": False,
                },
                indent=2,
            )
        )
        return
    require(os.geteuid() == 0, "boot inspection/operations require sudo")
    require(
        os.uname().machine == "aarch64" and os.uname().nodename.split(".")[0] == plan["pilotHost"],
        "operator supports only the reviewed ARM64 pilot",
    )
    # No ambient Nix/user config executes as root; mutations serialize with our
    # one-boot operator and the Debian package managers. No service changes.
    trial.directory(Path("/var/lib/dgx-setup"))
    lock = os.open("/var/lib/dgx-setup", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        ops = Persistent(plan, args.configuration, args.bundle)

        def interrupted(_signum, _frame):
            raise KeyboardInterrupt

        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGHUP, interrupted)
        if args.action == "check":
            if not ops.prepare_retry(dry_run=True):
                ops.initial_check()
            result = {"status": "READY_FOR_SEPARATE_ACTIVATION", "hostChangesPerformed": False}
        elif args.action in ("enable", "disable", "recover"):
            with ExitStack() as stack:
                for path in ("/var/lib/dpkg/lock-frontend", "/var/lib/dpkg/lock"):
                    fd = stack.enter_context(open(path, "r+"))
                    fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = (
                    ops.recover()
                    if args.action == "recover"
                    else ops.apply(args.action == "enable", args.console_ready)
                )
        else:
            result = ops.status()
        print(json.dumps(result, indent=2, sort_keys=True))
        print("KMS_STATUS=" + result["status"])
        print("NO_REBOOT: loaded KMS, driver, desktop, and services were not changed.")
    finally:
        os.close(lock)


if __name__ == "__main__":
    try:
        main()
    except (
        trial.kms.InspectionError,
        OSError,
        ValueError,
        KeyError,
        subprocess.SubprocessError,
        KeyboardInterrupt,
    ) as error:
        message = (
            str(error) if isinstance(error, trial.kms.InspectionError) else type(error).__name__
        )
        print(f"FAIL|kms_persistent|{message}", file=sys.stderr)
        raise SystemExit(1) from None
