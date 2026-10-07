"""Exercise real profile generations in a disposable Nix container only."""

import importlib.machinery
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOADER = importlib.machinery.SourceFileLoader("workstation", str(ROOT / "scripts/dgx-workstation"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
ws = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(ws)


def main():
    if not Path("/.dockerenv").exists():
        raise SystemExit("Run only in the disposable Nix validation container")
    with tempfile.TemporaryDirectory(prefix="sparkwerx-profile-test-") as directory:
        home = Path(directory)
        profile = ws.Profile(home)
        profile.prepare()
        shell = home / ".zshrc"
        shell.write_text("preserve existing shell\n")

        def fixture(name, exit_code):
            source = home / name
            (source / "bin").mkdir(parents=True)
            for command in ("ncdu", "devbox"):
                script = source / "bin" / command
                script.write_text(f"#!/bin/sh\nexit {exit_code}\n")
                script.chmod(0o755)
            (source / "workstation.json").write_text(json.dumps({"commands": ["ncdu", "devbox"]}))
            return ws.run(ws.NIX + ["store", "add-path", str(source)], capture=True).strip()

        first = fixture("first", 0)
        second = fixture("second", 0)
        broken = fixture("broken", 42)
        # Real nix-env switches, real executable postflight; no mocks.
        try:
            profile.apply(broken)
            raise AssertionError("Broken initial activation succeeded")
        except subprocess.CalledProcessError:
            assert profile.current() is None
        profile.apply(first)
        profile.apply(second)
        assert profile.current() == second
        try:
            profile.apply(broken)
            raise AssertionError("Broken update succeeded")
        except subprocess.CalledProcessError:
            assert profile.current() == second
            assert not profile.pending.exists()
        # Persist exactly the journal left by an interrupted switch; reopen it.
        ws.write_json(profile.pending, {"before": second, "candidate": first})
        profile.switch(first)
        recovered = ws.Profile(home)
        recovered.recover()
        assert recovered.current() == second
        recovered.disable()
        assert recovered.current() is None
        retained = {target for _, target in recovered.generations()}
        assert {first, second, broken} <= retained
        recovered.apply(first)
        assert recovered.current() == first
        roots = ws.run(["nix-store", "--gc", "--print-roots"], capture=True)
        # A custom profile location must retain every generation, even disabled.
        for _, target in recovered.generations():
            assert target in roots, f"Generation is not rooted: {target}"
        assert shell.read_text() == "preserve existing shell\n"
        assert not recovered.pending.exists()
        print(
            "PASS: real Nix activation, failed install/update, recovery, disable, rollback, roots"
        )


if __name__ == "__main__":
    main()
