"""Exercise NVENC using synthetic video; never capture a desktop or start a server."""

import argparse
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

CODECS = ("h264", "hevc", "av1")
PRESETS = {
    "smoke": (1280, 720, 30, 10),
    "1440p120": (2560, 1440, 120, 40),
    "4k60": (3840, 2160, 60, 60),
    "4k120": (3840, 2160, 120, 100),
}
DRIVER_LIBRARIES = ("libcuda", "libnvcuvid", "libnvidia-encode")
UNITS = (
    "tailscaled.service",
    "gdm.service",
    "dgx-headless.target",
    "docker.service",
    "dgx-dashboard.service",
    "dgx-dashboard-admin.service",
    "nvidia-persistenced.service",
)
PROPERTIES = (
    "Id",
    "ActiveState",
    "SubState",
    "MainPID",
    "ExecMainStartTimestampMonotonic",
    "FragmentPath",
    "NeedDaemonReload",
)


def run(args, *, env=None, timeout=30):
    return subprocess.run(
        [str(arg) for arg in args],
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True,
        stdin=subprocess.DEVNULL,
    ).stdout


def host_snapshot():
    units = run(
        [
            "systemctl",
            "show",
            *UNITS,
            *[f"--property={prop}" for prop in PROPERTIES],
        ]
    )
    profile = Path("/nix/var/nix/profiles/system-manager-profiles/system-manager")
    return units, str(profile.resolve()) if profile.exists() else None


def trusted_driver_file(path, stem, version):
    resolved = path.resolve(strict=True)
    if resolved.name != f"{stem}.so.{version}":
        raise ValueError(f"{stem} does not match the running driver version")
    for part in (resolved, *resolved.parents):
        info = part.stat()
        if info.st_uid != 0 or info.st_mode & 0o022:
            raise ValueError(f"untrusted driver library or ancestor: {part}")
    if not stat.S_ISREG(resolved.stat().st_mode):
        raise ValueError(f"driver library is not a regular file: {resolved}")
    with resolved.open("rb") as stream:
        header = stream.read(20)
    if header[:6] != b"\x7fELF\x02\x01" or header[18:20] != b"\xb7\x00":
        raise ValueError(f"driver library is not AArch64 ELF64: {resolved}")
    return resolved


def driver_bridge(directory, version, *, graphics=False):
    # Do not add /usr/lib to LD_LIBRARY_PATH: that would also mix Ubuntu's
    # libc/C++ runtime into the Nix process. Expose only the matching NVIDIA
    # driver libraries, in a temporary private directory. No driver is installed.
    libraries = {
        stem: trusted_driver_file(Path(f"/usr/lib/aarch64-linux-gnu/{stem}.so.1"), stem, version)
        for stem in DRIVER_LIBRARIES
    }
    libraries = {f"{stem}.so.1": target for stem, target in libraries.items()}
    if graphics:
        for stem, suffix in (
            ("libEGL_nvidia", "0"),
            ("libnvidia-glsi", version),
            ("libnvidia-eglcore", version),
            ("libnvidia-gpucomp", version),
        ):
            libraries[f"{stem}.so.{suffix}"] = trusted_driver_file(
                Path(f"/usr/lib/aarch64-linux-gnu/{stem}.so.{suffix}"), stem, version
            )
    directory.mkdir(mode=0o700)
    for name, target in libraries.items():
        (directory / name).symlink_to(target)
    env = os.environ.copy()
    for name in (
        "LD_PRELOAD",
        "LD_LIBRARY_PATH",
        "LD_AUDIT",
        "FFREPORT",
        "__EGL_VENDOR_LIBRARY_FILENAMES",
        "__EGL_VENDOR_LIBRARY_DIRS",
        "__GLX_VENDOR_LIBRARY_NAME",
        "LIBGL_ALWAYS_SOFTWARE",
        "EGL_PLATFORM",
    ):
        env.pop(name, None)
    env["LD_LIBRARY_PATH"] = str(directory)
    # Rendering tests must not populate the user's persistent driver caches.
    env["__GL_SHADER_DISK_CACHE"] = "0"
    env["CUDA_CACHE_DISABLE"] = "1"
    if graphics:
        vendor = directory / "nvidia.json"
        vendor.write_text(
            json.dumps(
                {
                    "file_format_version": "1.0.0",
                    "ICD": {"library_path": str(directory / "libEGL_nvidia.so.0")},
                }
            )
        )
        env["__EGL_VENDOR_LIBRARY_FILENAMES"] = str(vendor)
    return env


def encode_command(ffmpeg, codec, preset, destination):
    if codec not in CODECS or preset not in PRESETS:
        raise ValueError("unknown codec or preset")
    width, height, fps, bitrate = PRESETS[preset]
    return [
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-n",
        "-filter_threads",
        "2",
        "-f",
        "lavfi",
        "-i",
        f"testsrc2=size={width}x{height}:rate={fps}",
        "-frames:v",
        "60",
        "-an",
        "-c:v",
        f"{codec}_nvenc",
        "-gpu",
        "0",
        "-preset",
        "p1",
        "-tune",
        "ull",
        "-bf",
        "0",
        "-b:v",
        f"{bitrate}M",
        "-pix_fmt",
        "yuv420p",
        "-f",
        "matroska",
        destination,
    ]


def verify_stream(metadata, frame_hashes, codec, preset):
    streams = metadata.get("streams", [])
    width, height, fps, _ = PRESETS[preset]
    if len(streams) != 1 or any(
        streams[0].get(key) != value
        for key, value in {
            "codec_name": codec,
            "width": width,
            "height": height,
            "nb_read_frames": "60",
            "r_frame_rate": f"{fps}/1",
        }.items()
    ):
        raise ValueError("encoded video does not have the exact codec, size, rate, and frame count")
    hashes = []
    for line in frame_hashes.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split(",")]
        if len(fields) != 6 or not re.fullmatch(r"[0-9a-f]{32}", fields[-1]):
            raise ValueError("invalid decoded frame checksum record")
        hashes.append(fields[-1])
    if len(hashes) != 60 or len(set(hashes)) < 2:
        raise ValueError("decoded video is incomplete or contains no changing frames")


def exercise(ffmpeg, ffprobe, codec, preset, directory, env):
    video = directory / f"{codec}.mkv"
    run(encode_command(ffmpeg, codec, preset, video), env=env)
    metadata = json.loads(
        run(
            [
                ffprobe,
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-count_frames",
                "-show_entries",
                "stream=codec_name,width,height,nb_read_frames,r_frame_rate",
                "-of",
                "json",
                video,
            ],
            env=env,
        )
    )
    hashes = run(
        [
            ffmpeg,
            "-hide_banner",
            "-nostdin",
            "-loglevel",
            "error",
            "-threads",
            "2",
            "-i",
            video,
            "-map",
            "0:v:0",
            "-frames:v",
            "60",
            "-an",
            "-f",
            "framemd5",
            "-",
        ],
        env=env,
    )
    verify_stream(metadata, hashes, codec, preset)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg-bin", required=True, type=Path)
    parser.add_argument("--egl-probe", required=True, type=Path)
    parser.add_argument("--preset", choices=tuple(PRESETS), default="smoke")
    parser.add_argument("--codec", choices=("all", *CODECS), default="all")
    args = parser.parse_args()
    if platform.machine() != "aarch64" or platform.system() != "Linux":
        raise ValueError("this driver bridge targets factory DGX ARM64 Linux")
    if os.geteuid() == 0:
        raise ValueError("run this test as your normal user; it requires no sudo")
    version = run(
        ["/usr/bin/nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader"]
    ).strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("expected one GPU with an unambiguous factory driver version")
    before = host_snapshot()
    directory = Path(tempfile.mkdtemp(prefix="sparkwerx-nvenc-"))
    success = False
    try:
        env = driver_bridge(directory / "driver", version, graphics=True)
        print(
            f"INFO|nvenc|factory-driver={version};preset={args.preset};synthetic-video-only",
            flush=True,
        )
        print(run([args.egl_probe], env=env).strip(), flush=True)
        for codec in CODECS if args.codec == "all" else (args.codec,):
            print(f"INFO|encode|{codec};60-frames;no-software-encoder-fallback", flush=True)
            exercise(
                args.ffmpeg_bin / "ffmpeg",
                args.ffmpeg_bin / "ffprobe",
                codec,
                args.preset,
                directory,
                env,
            )
            print(
                f"PASS|encode_decode|{codec};frames=60;content=changing;{args.preset}", flush=True
            )
        success = True
    except subprocess.CalledProcessError as error:
        # All inputs are synthetic. Still keep stderr private rather than
        # dumping driver diagnostics into chat or a public validation record.
        (directory / "error.log").write_text(error.stderr or "No stderr was produced.\n")
        raise RuntimeError(
            f"GPU test subprocess failed; private diagnostics: {directory}/error.log"
        ) from error
    finally:
        encoded_success = success
        success = False
        try:
            if host_snapshot() != before:
                success = False
                raise RuntimeError(
                    "protected services or selected root profile changed during the test"
                )
            success = encoded_success
            print(
                "PASS|host_state|protected services and selected root profile unchanged", flush=True
            )
        finally:
            if success:
                shutil.rmtree(directory)
            else:
                print(f"DIAGNOSTICS_DIR={directory}", file=sys.stderr)
    print(
        "PASS|nvenc_probe|synthetic hardware encode/decode passed; Sunshine capture/streaming untested"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL|nvenc_probe|{error}", file=sys.stderr)
        raise SystemExit(1) from error
