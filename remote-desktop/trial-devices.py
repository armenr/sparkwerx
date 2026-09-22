"""Read-only NVIDIA DRM discovery for the live trial, not the frozen offline tests."""

import os
import re
import stat
from pathlib import Path

UNSPECIFIED = object()


def discover(sys_class=Path("/sys/class/drm"), dev_dri=Path("/dev/dri")):
    # cardN/renderDN are enumeration results, not GPU identities. Select one
    # NVIDIA PCI device, then require its unique primary/render pair. Do not
    # create aliases or use a colon-containing by-path name in AQ_DRM_DEVICES.
    cards = []
    for entry in sorted(sys_class.iterdir()):
        if not re.fullmatch(r"card\d+", entry.name):
            continue
        driver = entry / "device/driver"
        if driver.exists() and driver.resolve(strict=True).name == "nvidia":
            cards.append(entry)
    if len(cards) != 1:
        raise ValueError("expected exactly one NVIDIA DRM card; refusing absent or ambiguous GPUs")
    card = cards[0]
    device = (card / "device").resolve(strict=True)
    if (
        (device / "subsystem").resolve(strict=True).name != "pci"
        or (device / "vendor").read_text().strip() != "0x10de"
        or (device / "device").read_text().strip() != "0x2e12"
    ):
        raise ValueError("NVIDIA DRM card is not the reviewed GB10 PCI device")
    renders = [
        entry
        for entry in sorted(sys_class.iterdir())
        if re.fullmatch(r"renderD\d+", entry.name)
        and (entry / "device").resolve(strict=True) == device
        and (entry / "device/driver").resolve(strict=True).name == "nvidia"
    ]
    if len(renders) != 1:
        raise ValueError("NVIDIA DRM card lacks one matching render node on the same GPU")
    result = {"pci_device": str(device)}
    for role, entry in (("card", card), ("render", renders[0])):
        node = dev_dri / entry.name
        try:
            info = node.lstat()
        except FileNotFoundError as error:
            raise ValueError(f"selected NVIDIA DRM node is missing: {node}") from error
        numbers = (entry / "dev").read_text().strip()
        if not re.fullmatch(r"226:\d+", numbers):
            raise ValueError("NVIDIA DRM sysfs device number is unexpected")
        major, minor = map(int, numbers.split(":"))
        if (
            not stat.S_ISCHR(info.st_mode)
            or info.st_uid != 0
            or info.st_rdev != os.makedev(major, minor)
        ):
            raise ValueError(f"DRM node is not a root-owned device matching sysfs: {node}")
        result[role] = str(node)
        result[role + "_rdev"] = [major, minor]
    return result


def configure(capture, *, expected=UNSPECIFIED):
    selection = discover()
    if expected is not UNSPECIFIED and selection != expected:
        raise ValueError("NVIDIA DRM selection differs from the saved trial context")
    previous = getattr(capture, "trial_drm_selection", selection)
    if previous != selection:
        raise ValueError("NVIDIA DRM selection changed during the trial")
    # Only this process's separately imported helper is configured. The passed
    # offline diagnostic source, packages, and original device policy stay exact.
    capture.DRM_CARD = Path(selection["card"])
    capture.DRM_RENDER = Path(selection["render"])
    capture.DEVICES = (selection["card"], selection["render"], *capture.DEVICES[2:])
    other_drm = tuple(
        str(path)
        for path in sorted(capture.DRM_CARD.parent.iterdir())
        if re.fullmatch(r"(?:card\d+|renderD\d+)", path.name)
        and str(path) not in (selection["card"], selection["render"])
    )
    capture.FORBIDDEN_DEVICES = (
        *(
            path
            for path in capture.FORBIDDEN_DEVICES
            if not path.startswith("/dev/dri/") and Path(path).parent != capture.DRM_CARD.parent
        ),
        *other_drm,
    )
    capture.trial_drm_selection = selection
    return selection


def verify_private(capture):
    # PrivateDevices + exact bind mounts must expose only the selected pair,
    # never all of /dev/dri or a second GPU. This also catches unexpected aliases.
    if set(capture.DRM_CARD.parent.iterdir()) != {capture.DRM_CARD, capture.DRM_RENDER}:
        raise RuntimeError("trial exposes DRM devices other than the selected NVIDIA pair")


def preflight(capture):
    # Preserve the offline preflight's host/access/graphics checks here, with
    # discovery replacing only its historical card1/renderD128 assertions.
    # Do not edit the already-passed offline package to extend this live trial.
    if (
        os.geteuid() != 0
        or capture.platform.machine() != "aarch64"
        or capture.socket.gethostname() != "sparkle-01"
    ):
        raise ValueError("this hardware test requires sudo on the reviewed sparkle-01 pilot")
    if str(capture.ROOT_PROFILE.resolve(strict=True)) != capture.PILOT:
        raise ValueError("live root profile is not the reviewed headless generation five")
    if not capture.kms_enabled():
        raise ValueError(
            "NVIDIA DRM KMS is disabled (modeset=N); no graphics started. "
            "Enabling it needs a separately reviewed host change, not a permission workaround."
        )
    configure(capture)
    capture.validate_cuda_device()
    capture.user_device_groups(sunshine=True)
    before = capture.host_snapshot()
    if "NeedDaemonReload=yes" in before["units_profile"][0]:
        raise ValueError("a protected unit has a pending daemon reload")
    for name, expected in (
        ("gdm.service", "inactive"),
        ("dgx-dashboard.service", "inactive"),
        ("dgx-headless.target", "active"),
        ("docker.service", "active"),
        ("dgx-dashboard-admin.service", "active"),
        ("nvidia-persistenced.service", "active"),
        ("tailscaled.service", "active"),
    ):
        if capture.text(["systemctl", "show", name, "-p", "ActiveState", "--value"]) != expected:
            raise ValueError(f"required trial host unit state differs: {name}")
    for guard in capture.GUARDS:
        if os.path.lexists(f"/var/lib/dgx-setup/{guard}"):
            raise ValueError("a deployment/recovery guard exists; inspect it before testing")
    units = capture.json.loads(
        capture.text(["systemctl", "list-units", "--all", "--output=json", "--no-pager"])
    )
    for unit in units:
        name = unit["unit"]
        if (
            name.startswith("dgx-")
            and (
                "rollback" in name or "recovery" in name or name.startswith(capture.SERVICE_PREFIX)
            )
            and unit["active"] in ("active", "activating", "deactivating")
        ):
            raise ValueError("an active diagnostic or recovery unit exists")
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text().strip() in (
                "Hyprland",
                "gnome-shell",
                "Xorg",
                "sway",
                "weston",
                "sunshine",
            ):
                raise ValueError("an existing compositor or capture server is running")
        except (FileNotFoundError, ProcessLookupError):
            pass
    for name in capture.device_nodes(sunshine=True):
        if not stat.S_ISCHR(Path(name).stat().st_mode):
            raise ValueError("a required GPU device is missing")
    return before
