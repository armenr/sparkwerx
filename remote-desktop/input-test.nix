{
  pkgs,
  hyprland,
  sunshineInput,
}:
let
  receiver =
    pkgs.runCommandCC "sparkwerx-input-receiver"
      {
        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.wayland-scanner
        ];
        buildInputs = [
          pkgs.wayland
          pkgs.libxkbcommon
        ];
      }
      ''
        protocol=${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
        wayland-scanner client-header "$protocol" xdg-shell-client-protocol.h
        wayland-scanner private-code "$protocol" xdg-shell-protocol.c
        cp ${./color-client.c} color-client.c
        mkdir -p "$out/bin"
        $CC -std=c11 -Wall -Wextra -Werror -I. ${./input-receiver.c} xdg-shell-protocol.c \
          $(pkg-config --cflags --libs wayland-client xkbcommon) -o "$out/bin/sparkwerx-input-receiver"
        $CC -std=c11 -Wall -Wextra -Werror -I. color-client.c xdg-shell-protocol.c \
          $(pkg-config --cflags --libs wayland-client) -o "$out/bin/sparkwerx-color-client"
      '';
  # Reuse the byte-identical no-IP/no-kernel-input supervisor. This separate
  # source tree selects an extended probe; the passed diagnostics keep exactly
  # their original source, manifests, and store outputs.
  source = pkgs.runCommand "sparkwerx-private-input-source" { } ''
    mkdir -p "$out"
    cp ${./session-test.py} "$out/session-test.py"
    cp ${./gpu-probe.py} "$out/gpu-probe.py"
    cp ${./virtual-display.py} "$out/virtual-display.py"
    cp ${./inspect-session.py} "$out/inspect-session.py"
    cp ${./sunshine-startup.py} "$out/sunshine-original.py"
    cp ${./input-probe.py} "$out/sunshine-startup.py"
  '';
  manifest = pkgs.writeText "sparkwerx-private-input-tools.json" (
    builtins.toJSON {
      Hyprland = "${hyprland}/bin/Hyprland";
      hyprctl = "${hyprland}/bin/hyprctl";
      seatd = "${pkgs.lib.getBin pkgs.seatd}/bin/seatd";
      grim = "${pkgs.grim}/bin/grim";
      client = "${receiver}/bin/sparkwerx-color-client";
      "libgbm.so.1" = "${pkgs.libgbm}/lib/libgbm.so.1";
      "libdrm.so.2" = "${pkgs.libdrm}/lib/libdrm.so.2";
      sunshine = "${sunshineInput.package}/bin/sunshine";
      sunshineVersion = sunshineInput.package.version;
      inputReceiver = "${receiver}/bin/sparkwerx-input-receiver";
      inputExercise = "${sunshineInput.test}/bin/sparkwerx-wayland-input-test";
    }
  );
in
{
  inherit receiver;
  test = pkgs.writeShellApplication {
    name = "dgx-remote-desktop-input-test";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${source}/session-test.py host --tools ${manifest} "$@"
    '';
  };
  policy =
    pkgs.runCommand "sparkwerx-private-input-policy"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        mkdir -p tree/dev tree/remote-desktop tree/packages/sunshine "$out"
        cp ${../dev/test_remote_desktop_input.py} tree/dev/test_remote_desktop_input.py
        cp ${./input-probe.py} tree/remote-desktop/input-probe.py
        cp ${./sunshine-startup.py} tree/remote-desktop/sunshine-startup.py
        cp ${./session-test.py} tree/remote-desktop/session-test.py
        cp ${./gpu-probe.py} tree/remote-desktop/gpu-probe.py
        cp ${./virtual-display.py} tree/remote-desktop/virtual-display.py
        cp ${../packages/sunshine/wayland-input.hpp} tree/packages/sunshine/wayland-input.hpp
        cp ${../packages/sunshine/wayland-input.cpp} tree/packages/sunshine/wayland-input.cpp
        python3 -m unittest discover -s tree/dev
        ${sunshineInput.test}/bin/sparkwerx-wayland-input-test --self-test
        test -e ${sunshineInput.policy}/passed
        test -x ${receiver}/bin/sparkwerx-input-receiver
        test -x ${sunshineInput.package}/bin/sunshine
        test ! -e ${sunshineInput.package}/lib/udev
        test ! -e ${sunshineInput.package}/lib/systemd
        touch "$out/passed"
      '';
}
