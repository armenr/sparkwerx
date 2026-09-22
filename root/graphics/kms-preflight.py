"""Read-only boot evidence for a future KMS trial; never edit or execute boot configuration."""

import argparse
import configparser
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

GRUB_CONFIG = Path("/boot/grub/grub.cfg")
GRUB_ENV = Path("/boot/grub/grubenv")
VENDOR_OVERRIDE = Path("/etc/modprobe.d/zz-nvidia-drm-override.conf")
PROFILE = Path("/nix/var/nix/profiles/system-manager-profiles/system-manager")
UNITS = (
    "dgx-headless.target",
    "gdm.service",
    "dgx-dashboard.service",
    "dgx-dashboard-admin.service",
    "docker.service",
    "tailscaled.service",
    "nvidia-persistenced.service",
    "nix-daemon.service",
    "nix-daemon.socket",
)
GUARDS = ("desktop-switch", "tailscale-migration", "fleet-bootstrap", "root-reboot-recovery")


class InspectionError(ValueError):
    """A diagnostic constructed here, safe to show without raw configuration."""


def command(args):
    # Only fixed read-only commands are called below. Never source GRUB shell
    # files, invoke grub-mkconfig/update-initramfs, or print command stderr: it
    # may contain disk identifiers or private boot arguments.
    result = subprocess.run(args, capture_output=True, text=True, timeout=30, check=False)
    if result.returncode:
        raise InspectionError(f"read-only {Path(args[0]).name} query failed ({result.returncode})")
    return result.stdout


def read_config(path):
    try:
        info = path.lstat()
    except OSError as error:
        raise InspectionError(f"cannot inspect {path}: {type(error).__name__}") from None
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
        raise InspectionError(f"expected a root-owned, non-writable regular file: {path}")
    if info.st_size > 2 * 1024 * 1024:
        raise InspectionError(f"configuration exceeds inspection size limit: {path}")
    return path.read_text(encoding="utf-8")


def kernel_boolean(value):
    value = value.strip()
    if value not in ("Y", "N"):
        raise InspectionError("unrecognized loaded NVIDIA DRM boolean")
    return value


def grub_summary(config, environment, release):
    # These are textual clues for review, NOT a GRUB interpreter or a claim
    # that firmware/GRUB can actually consume and clear a one-shot selection.
    lines = [line.strip() for line in config.splitlines() if not line.lstrip().startswith("#")]
    text = "\n".join(lines)
    header = text.split("menuentry ", 1)[0]
    once = re.search(
        r'if \[ "\$\{next_entry\}" \] ; then\s+'
        r'set default="\$\{next_entry\}"\s+set next_entry=\s+'
        r'save_env next_entry\s+set boot_once=true\s+else\s+set default="0"\s+fi',
        header,
    )
    linux = [line for line in lines if re.match(r"linux(?:efi)?\s", line)]
    initrd = [line for line in lines if re.match(r"initrd(?:efi)?\s", line)]
    first_kernel = linux[0].split()[1] if linux and len(linux[0].split()) > 1 else ""
    first_initrd = initrd[0].split()[1] if initrd and len(initrd[0].split()) > 1 else ""
    # Report no UUID, entry ID/title, raw kernel command line, or env value.
    env = {}
    for line in environment.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in env:
            raise InspectionError("duplicate GRUB environment key; inspect privately")
        env[key] = value
    return {
        "configSha256": hashlib.sha256(config.encode()).hexdigest(),
        "standardOneShotHeaderObserved": once is not None,
        "loadsEnvironment": any(line == "load_env" for line in header.splitlines()),
        "firstKernelMatchesRunning": first_kernel
        in (f"/boot/vmlinuz-{release}", f"/vmlinuz-{release}"),
        "firstInitrdMatchesRunning": first_initrd
        in (f"/boot/initrd.img-{release}", f"/initrd.img-{release}"),
        "linuxEntryCount": len(linux),
        "pendingNextEntry": bool(env.get("next_entry")),
        "pendingPreviousEntry": bool(env.get("prev_entry") or env.get("prev_saved_entry")),
        "initrdFailureRecorded": env.get("initrdfail") not in (None, "", "0"),
        "recordfail": env.get("recordfail") not in (None, "", "0"),
        "bootloaderWriteVerified": False,
    }


def unit_summary(output):
    records = {}
    for block in output.strip().split("\n\n"):
        fields = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        name = fields.get("Id")
        if name not in UNITS or name in records:
            raise InspectionError("unexpected or duplicate systemd record")
        records[name] = {
            key: fields.get(key, "unknown")
            for key in ("LoadState", "ActiveState", "SubState", "NeedDaemonReload")
        }
    if set(records) != set(UNITS):
        raise InspectionError("incomplete systemd inspection")
    return records


def gnome_policy(config):
    parser = configparser.ConfigParser(interpolation=None)
    parser.read_string(config)
    value = parser.get("daemon", "WaylandEnable", fallback="unset").lower()
    return value if value in ("false", "true", "unset") else "unrecognized"


def review_findings(report):
    findings = []
    for key in (
        "standardOneShotHeaderObserved",
        "loadsEnvironment",
        "firstKernelMatchesRunning",
        "firstInitrdMatchesRunning",
    ):
        if not report["grub"][key]:
            findings.append(f"grub.{key}")
    for key in ("pendingNextEntry", "pendingPreviousEntry", "initrdFailureRecorded", "recordfail"):
        if report["grub"][key]:
            findings.append(f"grub.{key}")
    if report["grubFilesystem"] != "ext2" or report["grubStorageAbstractionPresent"]:
        findings.append("grub.storage-needs-review")
    if not report["efi"] or not report["pilotRootMatches"]:
        findings.append("host.not-reviewed-pilot-boot")
    if report["existingGuardCount"]:
        findings.append("host.existing-transition-guard")
    if report["modeset"] != "N" or not report["factoryOverrideExact"]:
        findings.append("kms.not-factory-disabled")
    inactive = {"gdm.service", "dgx-dashboard.service"}
    for name, unit in report["units"].items():
        expected = "inactive" if name in inactive else "active"
        # Nix is allowed to idle behind the active/listening socket.
        healthy_idle = (
            name == "nix-daemon.service"
            and unit["ActiveState"] == "inactive"
            and report["units"]["nix-daemon.socket"]["ActiveState"] == "active"
            and report["units"]["nix-daemon.socket"]["SubState"] == "listening"
        )
        if (
            unit["LoadState"] != "loaded"
            or unit["NeedDaemonReload"] != "no"
            or (unit["ActiveState"] != expected and not healthy_idle)
        ):
            findings.append(f"unit.{name}")
    return findings


def inspect(plan):
    if os.geteuid() != 0:
        raise InspectionError("check needs sudo to read the existing boot configuration")
    host = os.uname()
    if host.machine != "aarch64" or host.nodename.split(".")[0] != plan["pilotHost"]:
        raise InspectionError("boot inspection currently supports only the declared ARM64 pilot")
    grub = read_config(GRUB_CONFIG)
    # Inspect the real environment block with the factory reader, never edit it.
    read_config(GRUB_ENV)
    environment = command(["/usr/bin/grub-editenv", str(GRUB_ENV), "list"])
    fs = command(["/usr/sbin/grub-probe", "--target=fs", str(GRUB_ENV)]).strip()
    abstraction = command(["/usr/sbin/grub-probe", "--target=abstraction", str(GRUB_ENV)]).strip()
    units = command(
        [
            "/usr/bin/systemctl",
            "show",
            *UNITS,
            "--property=Id",
            "--property=LoadState",
            "--property=ActiveState",
            "--property=SubState",
            "--property=NeedDaemonReload",
        ]
    )
    report = {
        "stage": "inspection-only",
        "kernel": host.release,
        "efi": Path("/sys/firmware/efi").is_dir(),
        "pilotRootMatches": str(PROFILE.resolve(strict=True)) == plan["pilotRoot"],
        "modeset": kernel_boolean(Path("/sys/module/nvidia_drm/parameters/modeset").read_text()),
        "fbdev": kernel_boolean(Path("/sys/module/nvidia_drm/parameters/fbdev").read_text()),
        "factoryOverrideExact": read_config(VENDOR_OVERRIDE).strip()
        == "options nvidia-drm modeset=0",
        "gnomeWaylandSetting": gnome_policy(read_config(Path("/etc/gdm3/custom.conf"))),
        "grub": grub_summary(grub, environment, host.release),
        # ext4 is reported as ext2 by GRUB's ext-family driver. No device IDs.
        "grubFilesystem": fs if fs in ("ext2", "btrfs", "xfs", "zfs", "fat") else "other",
        "grubStorageAbstractionPresent": bool(abstraction),
        "existingGuardCount": sum(os.path.lexists(f"/var/lib/dgx-setup/{name}") for name in GUARDS),
        "units": unit_summary(units),
        "activationImplemented": False,
        "hostChangesPerformed": False,
    }
    report["reviewFindings"] = review_findings(report)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "check"))
    parser.add_argument("--plan-file", type=Path, required=True)
    args = parser.parse_args(argv)
    plan = json.loads(args.plan_file.read_text())
    report = plan if args.action == "plan" else inspect(plan)
    print(json.dumps(report, indent=2, sort_keys=True))
    print(
        "KMS_STATUS=PREPARATION_ONLY"
        if args.action == "plan"
        else "KMS_STATUS=BOOT_REVIEW_REQUIRED"
    )
    print("NO_CHANGES: no boot files, module settings, services, desktop, or GPU workload changed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except InspectionError as error:
        print(f"FAIL|kms_preflight|{error}; no changes made", file=sys.stderr)
        raise SystemExit(1) from None
    except (OSError, ValueError, configparser.Error, subprocess.SubprocessError) as error:
        # Avoid dumping raw configuration or subprocess output in an exception.
        print(
            f"FAIL|kms_preflight|inspection failed ({type(error).__name__}); no changes made",
            file=sys.stderr,
        )
        raise SystemExit(1) from None
