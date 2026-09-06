{
  pkgs,
  hyprland,
  sunshine ? null,
  sunshineCaptureTest ? null,
  ffmpeg ? null,
}:
# The startup verifier follows this release's log/config contract. An upstream
# update needs source review and retesting, not an automatic evidence carryover.
assert sunshine == null || sunshine.version == "2026.516.143833";
assert sunshineCaptureTest == null || (sunshine != null && ffmpeg != null);
let
  client =
    pkgs.runCommandCC "sparkwerx-wayland-color-client"
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
        mkdir -p "$out/bin"
        $CC -std=c11 -Wall -Wextra -Werror -I. ${./color-client.c} xdg-shell-protocol.c \
          $(pkg-config --cflags --libs wayland-client) -o "$out/bin/sparkwerx-color-client"
      '';
  source = pkgs.runCommand "sparkwerx-private-session-source" { } ''
    mkdir -p "$out"
    cp ${./session-test.py} "$out/session-test.py"
    cp ${./gpu-probe.py} "$out/gpu-probe.py"
    cp ${./virtual-display.py} "$out/virtual-display.py"
    cp ${./inspect-session.py} "$out/inspect-session.py"
    ${pkgs.lib.optionalString (sunshine != null) ''
      cp ${./sunshine-startup.py} "$out/sunshine-startup.py"
    ''}
    ${pkgs.lib.optionalString (sunshineCaptureTest != null) ''
      cp ${./sunshine-frames.py} "$out/sunshine-frames.py"
    ''}
  '';
  manifest = pkgs.writeText "sparkwerx-private-session-tools.json" (
    builtins.toJSON (
      {
        Hyprland = "${hyprland}/bin/Hyprland";
        hyprctl = "${hyprland}/bin/hyprctl";
        seatd = "${pkgs.lib.getBin pkgs.seatd}/bin/seatd";
        grim = "${pkgs.grim}/bin/grim";
        client = "${client}/bin/sparkwerx-color-client";
        "libgbm.so.1" = "${pkgs.libgbm}/lib/libgbm.so.1";
        "libdrm.so.2" = "${pkgs.libdrm}/lib/libdrm.so.2";
      }
      // pkgs.lib.optionalAttrs (sunshine != null) {
        sunshine = "${sunshine}/bin/sunshine";
        sunshineVersion = sunshine.version;
      }
      // pkgs.lib.optionalAttrs (sunshineCaptureTest != null) {
        sunshineFrameCapture = "${sunshineCaptureTest}/bin/sparkwerx-sunshine-capture";
        ffmpeg = "${pkgs.lib.getBin ffmpeg}/bin/ffmpeg";
        ffprobe = "${pkgs.lib.getBin ffmpeg}/bin/ffprobe";
      }
    )
  );
in
{
  inspect = pkgs.writeShellApplication {
    name = "dgx-remote-desktop-session-inspect";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./inspect-session.py} "$@"
    '';
  };
  test = pkgs.writeShellApplication {
    name =
      if sunshineCaptureTest != null then
        "dgx-remote-desktop-sunshine-frames-test"
      else if sunshine == null then
        "dgx-remote-desktop-session-test"
      else
        "dgx-remote-desktop-sunshine-startup-test";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${source}/session-test.py host --tools ${manifest} "$@"
    '';
  };
  policy =
    pkgs.runCommand "sparkwerx-private-session-policy"
      {
        nativeBuildInputs = [
          pkgs.python3
          hyprland
        ];
      }
      ''
        mkdir -p tree/dev tree/scripts tree/remote-desktop runtime cache config "$out"
        chmod 700 runtime
        cp ${source}/*.py tree/remote-desktop/
        ${pkgs.lib.optionalString (sunshine == null) ''
          cp ${./sunshine-startup.py} tree/remote-desktop/sunshine-startup.py
        ''}
        cp ${../dev/test_remote_desktop_sunshine.py} tree/dev/test_remote_desktop_sunshine.py
        cp ${../scripts/test-remote-desktop-sunshine.sh} tree/scripts/test-remote-desktop-sunshine.sh
        cp ${../dev/test_remote_desktop_capture.py} tree/dev/test_remote_desktop_capture.py
        cp ${../dev/test_remote_desktop_inspect.py} tree/dev/test_remote_desktop_inspect.py
        ${pkgs.lib.optionalString (sunshineCaptureTest != null) ''
          cp ${../dev/test_remote_desktop_sunshine_frames.py} tree/dev/test_remote_desktop_sunshine_frames.py
          ${sunshineCaptureTest}/bin/sparkwerx-sunshine-capture --describe > "$out/capture-build.json"
        ''}
        ${pkgs.lib.optionalString (sunshineCaptureTest != null) ''
          export DGX_TEST_FFMPEG=${pkgs.lib.getBin ffmpeg}/bin
        ''}
        ${
          pkgs.lib.optionalString (sunshine != null) "DGX_TEST_SUNSHINE=${sunshine}/bin/sunshine "
        }python3 -m unittest discover -s tree/dev
        PYTHONPATH=tree/remote-desktop python3 - <<'PY'
        import importlib.util
        from pathlib import Path
        spec = importlib.util.spec_from_file_location("capture", "tree/remote-desktop/session-test.py")
        capture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(capture)
        for name, preset in capture.PRESETS.items():
            Path(name + ".conf").write_text(capture.test_config(preset))
        PY
        for preset in 1440p120 4k60 4k120; do
          env XDG_RUNTIME_DIR="$PWD/runtime" XDG_CACHE_HOME="$PWD/cache" \
            XDG_CONFIG_HOME="$PWD/config" Hyprland --verify-config --config "$preset.conf"
        done
        # Force the tiny client to compile with warnings treated as errors.
        test -x ${client}/bin/sparkwerx-color-client
        touch "$out/passed"
      '';
}
