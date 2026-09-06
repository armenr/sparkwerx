{ pkgs }:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  # These two upstream releases are ahead of nixpkgs-devtools. Keep the
  # adapters in the development shell only; retire them when stock catches up.
  preCommit = pkgs.pre-commit.overridePythonAttrs (_: {
    version = sources.pre-commit.version;
    src = pkgs.fetchurl {
      inherit (sources.pre-commit) url sha256;
    };
    # The full upstream suite provisions many unrelated language toolchains.
    # Exercise our actual local-hook/install path in dev/test_quality.py instead.
    nativeCheckInputs = [ ];
    preCheck = "";
    postCheck = "";
    doCheck = false;
    doInstallCheck = true;
    installCheckPhase = ''
      $out/bin/pre-commit --version | grep -Fx 'pre-commit ${sources.pre-commit.version}'
    '';
  });
  ruff = pkgs.stdenvNoCC.mkDerivation {
    pname = "ruff";
    version = sources.ruff.version;
    src = pkgs.fetchurl {
      inherit (sources.ruff) url sha256;
    };
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      install -Dm755 ruff $out/bin/ruff
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      $out/bin/ruff --version | grep -Fx 'ruff ${sources.ruff.version}'
    '';
    meta = pkgs.ruff.meta // {
      platforms = [ "aarch64-linux" ];
    };
  };
in
[
  preCommit
  ruff
  pkgs.shellcheck
  pkgs.shfmt
  pkgs.actionlint
  pkgs.nixfmt
  pkgs.python3
]
