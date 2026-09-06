{ pkgs }:
let
  plan = ./kms-plan.json;
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
  policy =
    pkgs.runCommand "sparkwerx-kms-preparation-policy"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        mkdir -p tree/dev tree/root/graphics "$out"
        cp ${./kms-preflight.py} tree/root/graphics/kms-preflight.py
        cp ${plan} tree/root/graphics/kms-plan.json
        cp ${../../dev/test_kms_preflight.py} tree/dev/test_kms_preflight.py
        python3 -B -m unittest discover -s tree/dev
        cp ${plan} "$out/plan.json"
        touch "$out/passed"
      '';
}
