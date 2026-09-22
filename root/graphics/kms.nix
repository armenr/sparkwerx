{ pkgs }:
let
  plan = ./kms-plan.json;
  code = pkgs.runCommand "dgx-kms-trial-code" { } ''
    mkdir -p "$out"
    cp ${./kms-preflight.py} "$out/kms-preflight.py"
    cp ${./kms-trial.py} "$out/kms-trial.py"
  '';
in
{
  # Preparatory tools only. Importing this does not change a System Manager
  # generation, /etc/modprobe.d, initramfs, GRUB, the loaded GPU driver, or GDM.
  preflight = pkgs.writeShellApplication {
    name = "dgx-kms-preflight";
    text = ''
      exec ${pkgs.python3}/bin/python3 -I -B ${./kms-preflight.py} --plan-file ${plan} "$@"
    '';
  };
  trial = pkgs.writeShellApplication {
    name = "dgx-kms-trial";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      bundle="$(dirname "$(dirname "$(readlink -f "$0")")")"
      exec ${pkgs.python3}/bin/python3 -I -B ${code}/kms-trial.py \
        --plan-file ${plan} --bundle "$bundle" "$@"
    '';
  };
  policy =
    pkgs.runCommand "sparkwerx-kms-preparation-policy"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.grub2_efi
        ];
      }
      ''
        mkdir -p tree/dev tree/root/graphics "$out"
        cp ${./kms-preflight.py} tree/root/graphics/kms-preflight.py
        cp ${./kms-trial.py} tree/root/graphics/kms-trial.py
        cp ${plan} tree/root/graphics/kms-plan.json
        cp ${../../dev/test_kms_preflight.py} tree/dev/test_kms_preflight.py
        cp ${../../dev/test_kms_trial.py} tree/dev/test_kms_trial.py
        python3 -B -m unittest discover -s tree/dev
        cp ${plan} "$out/plan.json"
        touch "$out/passed"
      '';
}
