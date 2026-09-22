"""Check the built CUDA adapter without opening a GPU, service, or listener."""

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path


def verify(args):
    package = Path(args.package)
    evidence = json.loads((package / "share/sparkwerx/sunshine-build.json").read_text())
    assert evidence == {
        "sunshineVersion": "2026.516.143833",
        "cudaCompilerVersion": "12.9.86",
        "cudaRuntimeVersion": "12.9.79",
        "cudaImplementationCompiled": True,
        "streamingTested": False,
    }
    binary = package / "bin/.sunshine-wrapped"
    assert binary.is_file(), "expected the reviewed Nix shell wrapper and ELF pair"
    rpath = subprocess.check_output([args.patchelf, "--print-rpath", str(binary)], text=True)
    assert not any("stubs" in entry for entry in rpath.strip().split(":")), rpath
    assert not any("cuda_nvcc" in entry for entry in rpath.strip().split(":")), rpath

    # In the pinned main.cpp, --version exits after parsing configuration and
    # before GPU/input/display/server initialization. Use entirely private
    # state and an invented driver-bridge path, never the host environment.
    for inherited in (None, "", "/run/sparkwerx-factory-driver-test"):
        with tempfile.TemporaryDirectory() as temporary:
            env = {"HOME": temporary, "XDG_CONFIG_HOME": temporary, "LANG": "C"}
            if inherited is not None:
                env["LD_LIBRARY_PATH"] = inherited
            result = subprocess.run(
                [args.bash, "-x", str(package / "bin/sunshine"), "--version"],
                env=env,
                cwd=temporary,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=10,
                check=True,
            )
            expected = args.vulkan_lib + (":" + inherited if inherited else "")
            # makeWrapper assigns the path first, then exports its name on a
            # separate line. Require both the final value and the export.
            assignments = re.findall(
                r"^\+ (?:export )?LD_LIBRARY_PATH=(.*)$", result.stderr, re.MULTILINE
            )
            assert assignments and assignments[-1] == expected, result.stderr
            assert re.search(r"^\+ export LD_LIBRARY_PATH(?:=.*)?$", result.stderr, re.MULTILINE)
            assert "Sunshine version: " + evidence["sunshineVersion"] in result.stdout
            assert "Trying encoder" not in result.stdout + result.stderr
            assert "Screencasting" not in result.stdout + result.stderr
    print(
        "PASS|sunshine_package|compiled CUDA evidence, loader paths, and version-only wrapper checks passed"
    )
    print("NOT_GPU_TESTED: no capture, encoder initialization, or streaming was performed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "bash", "patchelf", "vulkan-lib"):
        parser.add_argument("--" + name, required=True)
    verify(parser.parse_args())


if __name__ == "__main__":
    main()
