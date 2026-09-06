{
  pkgs,
  plans,
  sunshine,
}:
let
  plansFile = pkgs.writeText "remote-desktop-plans.json" (builtins.toJSON plans);
in
{
  policy =
    pkgs.runCommand "sparkwerx-remote-desktop-policy" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        mkdir -p tree/dev tree/scripts tree/fleet tree/remote-desktop "$out"
        cp ${../dev/test_remote_desktop.py} tree/dev/test_remote_desktop.py
        cp ${../scripts/dgx-remote-desktop} tree/scripts/dgx-remote-desktop
        cp ${../fleet/hosts.json} tree/fleet/hosts.json
        cp ${./defaults.json} tree/remote-desktop/defaults.json
        cp ${./client-presets.json} tree/remote-desktop/client-presets.json
        cp ${./network-test.py} tree/remote-desktop/network-test.py
        DGX_REMOTE_NIX_PLANS=${plansFile} python3 -m unittest discover -s tree/dev
        cp ${plansFile} "$out/plans.json"
        cp ${./client-presets.json} "$out/client-presets.json"
        cp ${./sunshine.conf.in} "$out/sunshine.conf.in"
        cp ${./network.nft} "$out/network.nft"
        printf '%s\n' '${sunshine.version}' > "$out/sunshine-version"
      '';

  networkTest = pkgs.writeShellApplication {
    name = "dgx-remote-desktop-network-test";
    runtimeInputs = [
      pkgs.python3
      pkgs.iproute2
      pkgs.nftables
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      if [[ "$EUID" -ne 0 ]]; then
        echo 'This disposable network test requires root, not a graphical session.' >&2
        exit 1
      fi
      exec unshare --net -- python3 ${./network-test.py} ${./network.nft}
    '';
  };
}
