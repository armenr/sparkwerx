{
  pkgs,
  hyprland,
  sunshineInput,
  inputPolicy,
}:
let
  # Assemble each tree from declared files, never a glob over another output
  # that an earlier root-run Python process might have populated with caches.
  sourceFiles = [
    ./trial-control.py
    ./trial-session.py
    ./trial-metrics.py
    ./session-test.py
    ./gpu-probe.py
    ./virtual-display.py
    ./sunshine-startup.py
    ./inspect-session.py
  ];
  networkFiles = sourceFiles ++ [
    ./trial-network-test.py
    ./network-test.py
  ];
  copySources =
    destination: files:
    pkgs.lib.concatMapStringsSep "\n" (
      file: "cp ${file} ${destination}/${builtins.baseNameOf file}"
    ) files;
  canvas =
    pkgs.runCommandCC "sparkwerx-trial-canvas"
      {
        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.wayland-scanner
        ];
        buildInputs = [ pkgs.wayland ];
      }
      ''
        protocol=${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
        wayland-scanner client-header "$protocol" xdg-shell-client-protocol.h
        wayland-scanner private-code "$protocol" xdg-shell-protocol.c
        cp ${./color-client.c} color-client.c
        mkdir -p "$out/bin"
        $CC -std=c11 -Wall -Wextra -Werror -I. ${./trial-canvas.c} xdg-shell-protocol.c \
          $(pkg-config --cflags --libs wayland-client) -o "$out/bin/sparkwerx-trial-canvas"
        "$out/bin/sparkwerx-trial-canvas" --describe
        "$out/bin/sparkwerx-trial-canvas" --timing-self-test
      '';
  source = pkgs.runCommand "sparkwerx-moonlight-trial-source" { } ''
    mkdir -p "$out"
    ${copySources ''"$out"'' sourceFiles}
  '';
  tools = {
    Hyprland = "${hyprland}/bin/Hyprland";
    hyprctl = "${hyprland}/bin/hyprctl";
    seatd = "${pkgs.lib.getBin pkgs.seatd}/bin/seatd";
    "libgbm.so.1" = "${pkgs.libgbm}/lib/libgbm.so.1";
    "libdrm.so.2" = "${pkgs.libdrm}/lib/libdrm.so.2";
    sunshine = "${sunshineInput.package}/bin/sunshine";
    sunshineVersion = sunshineInput.package.version;
    canvas = "${canvas}/bin/sparkwerx-trial-canvas";
    nft = "${pkgs.nftables}/bin/nft";
  };
  manifest = pkgs.writeText "sparkwerx-moonlight-trial-tools.json" (builtins.toJSON tools);
  mkBundle =
    name: tree: config: controller:
    pkgs.runCommand name { } ''
      mkdir -p "$out/bin"
      substitute ${./trial-wrapper.sh} "$out/bin/dgx-moonlight-trial" \
        --replace-fail '@bash@' '${pkgs.bash}/bin/bash' \
        --replace-fail '@readlink@' '${pkgs.coreutils}/bin/readlink' \
        --replace-fail '@python@' '${pkgs.python3}/bin/python3' \
        --replace-fail '@controller@' '${tree}/${controller}' \
        --replace-fail '@manifest@' '${config}'
      chmod 0555 "$out/bin/dgx-moonlight-trial"
    '';
  bundle = mkBundle "sparkwerx-moonlight-trial" source manifest "trial-control.py";
  fixtureSource = pkgs.runCommand "sparkwerx-moonlight-trial-fixture-source" { } ''
    mkdir -p "$out"
    ${copySources ''"$out"'' (sourceFiles ++ [ ./trial-fixture.py ])}
  '';
  fixtureManifest = pkgs.writeText "sparkwerx-moonlight-trial-fixture-tools.json" (
    builtins.toJSON {
      nft = tools.nft;
      controller = "trial-fixture.py";
    }
  );
  networkSource = pkgs.runCommand "sparkwerx-moonlight-trial-network-source" { } ''
    mkdir -p "$out"
    ${copySources ''"$out"'' networkFiles}
  '';
in
{
  inherit
    canvas
    source
    bundle
    manifest
    fixtureSource
    networkSource
    ;
  fixture =
    mkBundle "sparkwerx-moonlight-trial-fixture" fixtureSource fixtureManifest
      "trial-fixture.py";
  networkTest = pkgs.writeShellApplication {
    name = "sparkwerx-moonlight-trial-network-test";
    runtimeInputs = [
      pkgs.python3
      pkgs.iproute2
      pkgs.nftables
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = "exec unshare --net -- python3 -B ${networkSource}/trial-network-test.py";
  };
  policy =
    pkgs.runCommand "sparkwerx-moonlight-trial-policy"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        mkdir -p tree/remote-desktop tree/dev "$out"
        ${copySources "tree/remote-desktop" (
          networkFiles
          ++ [
            ./trial-canvas.c
            ./trial-wrapper.sh
            ./trial-gate.nix
            ./trial.nix
          ]
        )}
        cp ${../dev/test_moonlight_trial.py} tree/dev/test_moonlight_trial.py
        SPARKWERX_TEST_NFT=${pkgs.nftables}/bin/nft python3 -B -m unittest discover -s tree/dev
        test -e ${inputPolicy}/passed
        ${canvas}/bin/sparkwerx-trial-canvas --describe
        test ! -e ${source}/trial-fixture.py
        test -x ${bundle}/bin/dgx-moonlight-trial
        touch "$out/passed"
      '';
}
