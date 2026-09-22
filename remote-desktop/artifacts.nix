{
  pkgs,
  plans,
  sunshine,
  sunshineCaptureTest,
  ffmpeg,
  hyprland,
}:
let
  plansFile = pkgs.writeText "remote-desktop-plans.json" (builtins.toJSON plans);
  capture = import ./session-test.nix { inherit pkgs hyprland; };
  sunshineStartup = import ./session-test.nix { inherit pkgs hyprland sunshine; };
  sunshineFrames = import ./session-test.nix {
    inherit
      pkgs
      hyprland
      sunshine
      sunshineCaptureTest
      ffmpeg
      ;
  };
  eglProbe =
    pkgs.runCommandCC "sparkwerx-egl-probe"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.libglvnd ];
      }
      ''
        mkdir -p "$out/bin"
        $CC -std=c11 -Wall -Wextra -Werror ${./egl-probe.c} \
          $(pkg-config --cflags --libs egl opengl) -o "$out/bin/sparkwerx-egl-probe"
      '';
in
{
  sessionTest = capture.test;
  sessionInspect = capture.inspect;
  capturePolicy = capture.policy;
  sunshineStartupTest = sunshineStartup.test;
  sunshineStartupPolicy = sunshineStartup.policy;
  sunshineFramesTest = sunshineFrames.test;
  sunshineFramesPolicy = sunshineFrames.policy;
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

  gpuPolicy =
    pkgs.runCommand "sparkwerx-remote-desktop-gpu-policy"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        mkdir -p tree/dev tree/remote-desktop "$out"
        cp ${../dev/test_remote_desktop_gpu.py} tree/dev/test_remote_desktop_gpu.py
        cp ${./gpu-probe.py} tree/remote-desktop/gpu-probe.py
        cp ${./client-presets.json} tree/remote-desktop/client-presets.json
        python3 -m unittest discover -s tree/dev
        touch "$out/passed"
      '';

  gpuTest = pkgs.writeShellApplication {
    name = "dgx-remote-desktop-gpu-test";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./gpu-probe.py} --ffmpeg-bin ${pkgs.lib.getBin ffmpeg}/bin \
        --egl-probe ${eglProbe}/bin/sparkwerx-egl-probe "$@"
    '';
  };

  sessionPolicy =
    pkgs.runCommand "sparkwerx-remote-desktop-session-policy"
      {
        nativeBuildInputs = [
          pkgs.python3
          hyprland
        ];
      }
      ''
        mkdir -p tree/dev tree/remote-desktop runtime cache config "$out"
        chmod 700 runtime
        cp ${../dev/test_remote_desktop_session.py} tree/dev/test_remote_desktop_session.py
        cp ${./virtual-display.py} tree/remote-desktop/virtual-display.py
        python3 -m unittest discover -s tree/dev
        for preset in 1440p120 4k60 4k120; do
          python3 ${./virtual-display.py} --presets ${./client-presets.json} \
            --preset "$preset" > "$out/$preset.conf"
          env XDG_RUNTIME_DIR="$PWD/runtime" XDG_CACHE_HOME="$PWD/cache" \
            XDG_CONFIG_HOME="$PWD/config" Hyprland --verify-config \
            --config "$out/$preset.conf"
        done
      '';
}
