{
  pkgs,
  enable ? false,
  menuSeconds ? 5,
}:
assert builtins.isBool enable;
assert builtins.isInt menuSeconds && menuSeconds >= 5 && menuSeconds <= 30;
let
  code = pkgs.runCommand "dgx-kms-persistent-code" { } ''
    mkdir -p "$out"
    cp ${./kms-persistent.py} "$out/kms-persistent.py"
    cp ${./kms-trial.py} "$out/kms-trial.py"
    cp ${./kms-preflight.py} "$out/kms-preflight.py"
  '';
  fallback = pkgs.writeShellScript "42_sparkwerx_kms" ''
    # Called by Ubuntu's grub-mkconfig, with its exported GRUB variables.
    # Never substitute a Nix kernel/driver or reuse a saved kernel path.
    exec ${pkgs.python3}/bin/python3 -I -B ${code}/kms-persistent.py fallback
  '';
  defaults = pkgs.writeText "90-sparkwerx-kms.cfg" ''
    # Sparkwerx opt-in KMS; NVIDIA's module configuration stays untouched.
    # GRUB_CMDLINE_LINUX_DEFAULT excludes Ubuntu's recovery-mode entries.
    GRUB_CMDLINE_LINUX_DEFAULT="''${GRUB_CMDLINE_LINUX_DEFAULT} nvidia_drm.modeset=1"
    GRUB_TIMEOUT_STYLE=menu
    GRUB_TIMEOUT=${toString menuSeconds}
  '';
  configuration = pkgs.runCommand "dgx-kms-persistent-configuration" { } (
    ''mkdir -p "$out"''
    + pkgs.lib.optionalString enable ''
      mkdir -p "$out/etc/default/grub.d" "$out/etc/grub.d"
      ln -s ${defaults} "$out/etc/default/grub.d/90-sparkwerx-kms.cfg"
      ln -s ${fallback} "$out/etc/grub.d/42_sparkwerx_kms"
    ''
  );
  operator = pkgs.writeShellApplication {
    name = "dgx-kms-persistent";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      bundle="$(dirname "$(dirname "$(readlink -f "$0")")")"
      exec ${pkgs.python3}/bin/python3 -I -B ${code}/kms-persistent.py \
        --configuration ${configuration} --bundle "$bundle" \
        --plan-file ${./kms-plan.json} "$@"
    '';
  };
  policy =
    pkgs.runCommand "dgx-kms-persistent-policy"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.grub2_efi
        ];
      }
      ''
        mkdir -p tree/root/graphics tree/dev "$out"
        cp ${code}/*.py tree/root/graphics/
        cp ${./kms-plan.json} tree/root/graphics/kms-plan.json
        cp ${../../dev/test_kms_persistent.py} tree/dev/test_kms_persistent.py
        export DGX_KMS_TEST_CONFIGURATION=${configuration}
        export DGX_KMS_TEST_ENABLED=${if enable then "1" else "0"}
        export DGX_KMS_TEST_MENU_SECONDS=${toString menuSeconds}
        cd tree
        python3 -B -m unittest discover -s dev -p test_kms_persistent.py -v
        touch "$out/passed"
      '';
in
{
  inherit configuration operator policy;
}
