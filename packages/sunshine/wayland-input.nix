{
  pkgs,
  sunshine,
  hyprland,
}:
assert sunshine.version == "2026.516.143833";
let
  protocolSource = hyprland.src + "/protocols";
  source =
    pkgs.runCommand "sparkwerx-wayland-input-source"
      {
        nativeBuildInputs = [ pkgs.wayland-scanner ];
      }
      ''
          mkdir -p "$out"
          cp ${./wayland-input.hpp} "$out/wayland-input.hpp"
          cp ${./wayland-input.cpp} "$out/wayland-input.cpp"
          cp ${./wayland-input-test.cpp} "$out/wayland-input-test.cpp"
          # Reuse exactly the upstream Moonlight -> Linux keycode mapping. No
          # inputtino device code enters the adapter or its protocol fixture.
        cp ${sunshine.src}/third-party/inputtino/src/uinput/include/inputtino/keyboard.hpp \
          "$out/sparkwerx-keyboard-map.hpp"
        cp ${sunshine.src}/third-party/inputtino/LICENSE "$out/inputtino-LICENSE"
          for kind in keyboard pointer; do
            if [[ "$kind" == keyboard ]]; then
              protocol=${protocolSource}/virtual-keyboard-unstable-v1.xml
            else
              protocol=${protocolSource}/wlr-virtual-pointer-unstable-v1.xml
            fi
            cp "$protocol" "$out/virtual-$kind.xml"
            wayland-scanner client-header "$protocol" "$out/virtual-$kind-client.h"
            wayland-scanner server-header "$protocol" "$out/virtual-$kind-server.h"
            wayland-scanner private-code "$protocol" "$out/virtual-$kind.c"
          done
      '';
  test =
    pkgs.runCommandCC "sparkwerx-wayland-input-test"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          pkgs.wayland
          pkgs.libxkbcommon
        ];
      }
      ''
          cp ${source}/virtual-*.c .
          $CC -c virtual-keyboard.c virtual-pointer.c $(pkg-config --cflags wayland-client)
          mkdir -p "$out/bin"
          $CXX -std=c++20 -Wall -Wextra -Werror -pthread -I${source} \
            ${source}/wayland-input-test.cpp virtual-keyboard.o virtual-pointer.o \
            $(pkg-config --cflags --libs wayland-client wayland-server xkbcommon) \
            -o "$out/bin/sparkwerx-wayland-input-test"
        "$out/bin/sparkwerx-wayland-input-test" --self-test
        install -Dm644 ${source}/inputtino-LICENSE "$out/share/licenses/inputtino-LICENSE"
      '';
  package = sunshine.overrideAttrs (old: {
    pname = "sparkwerx-sunshine-wayland-input";
    buildInputs = old.buildInputs ++ [ pkgs.libxkbcommon ];
    postPatch = (old.postPatch or "") + ''
      sha256sum --check ${./capture-engine.sha256}
      mkdir -p src/platform/linux/input/sparkwerx
      cp ${source}/* src/platform/linux/input/sparkwerx/
      substituteInPlace cmake/compile_definitions/linux.cmake \
        --replace-fail 'list(APPEND PLATFORM_TARGET_FILES ''${INPUTTINO_SOURCES})' \
        'list(APPEND PLATFORM_TARGET_FILES ''${CMAKE_SOURCE_DIR}/src/platform/linux/input/inputtino_seat.cpp ''${CMAKE_SOURCE_DIR}/src/platform/linux/input/sparkwerx/wayland-input.cpp ''${CMAKE_SOURCE_DIR}/src/platform/linux/input/sparkwerx/virtual-keyboard.c ''${CMAKE_SOURCE_DIR}/src/platform/linux/input/sparkwerx/virtual-pointer.c)
      pkg_check_modules(SPARKWERX_XKB REQUIRED xkbcommon)
      list(APPEND PLATFORM_LIBRARIES ''${SPARKWERX_XKB_LIBRARIES})
      include_directories(''${SPARKWERX_XKB_INCLUDE_DIRS})'
      sha256sum --check ${./capture-engine.sha256}
    '';
    postBuild = (old.postBuild or "") + ''
      test -s CMakeFiles/sunshine.dir/src/platform/linux/input/sparkwerx/wayland-input.cpp.o
      test ! -e CMakeFiles/sunshine.dir/src/platform/linux/input/inputtino.cpp.o
      ${test}/bin/sparkwerx-wayland-input-test --self-test
    '';
    # Do not install the upstream uinput/service/desktop setup artifacts.
    installPhase = ''
      runHook preInstall
      install -Dm755 sunshine "$out/bin/sunshine"
      mkdir -p "$out/assets"
      cp -rL assets/. "$out/assets/"
      test -s "$out/assets/shaders/opengl/ConvertY.frag"
      test -s "$out/assets/web/index.html"
      install -Dm644 ${./wayland-input.hpp} "$out/share/sparkwerx/wayland-input.hpp"
      install -Dm644 ${source}/inputtino-LICENSE "$out/share/licenses/inputtino-LICENSE"
      printf '%s\n' '{"input":"private-wayland","kernelInput":false,"hardwareTested":false}' \
        > "$out/share/sparkwerx/wayland-input.json"
      runHook postInstall
    '';
    doInstallCheck = false;
    passthru = (old.passthru or { }) // {
      sparkwerxWaylandInput = true;
    };
  });
in
{
  inherit source test package;
  policy = import ./policy.nix {
    inherit pkgs;
    sunshine = package;
    inherit (pkgs) vulkan-loader;
  };
}
