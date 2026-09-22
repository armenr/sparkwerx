{
  lib,
  sunshine,
  vulkan-loader,
}:
# A different executable, never the package offered to Home/System Manager.
# Keep the original capture, conversion and encoding engines; replace only the
# application entry point. It calls video::capture and consumes video packets
# locally without starting HTTP, RTSP, audio, input or application launchers.
assert sunshine.version == "2026.516.143833";
sunshine.overrideAttrs (old: {
  pname = "sparkwerx-sunshine-capture";
  postPatch = (old.postPatch or "") + ''
    sha256sum --check ${./capture-engine.sha256}
    cp ${./capture-main.cpp} src/main.cpp
    sha256sum --check ${./capture-engine.sha256}
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 sunshine "$out/bin/sparkwerx-sunshine-capture"
    # The unchanged OpenGL converter reads these at runtime. Include the
    # original shaders, not the server UI, launchers, or device/service rules.
    mkdir -p "$out/assets/shaders"
    cp -r ../src_assets/linux/assets/shaders/. "$out/assets/shaders/"
    diff -r ../src_assets/linux/assets/shaders "$out/assets/shaders"
    install -Dm644 ${./capture-engine.sha256} "$out/share/sparkwerx/capture-engine.sha256"
    install -Dm644 ${./capture-main.cpp} "$out/share/sparkwerx/capture-main.cpp"
  '';
  postFixup = ''
    wrapProgram "$out/bin/sparkwerx-sunshine-capture" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader ]}
    "$out/bin/sparkwerx-sunshine-capture" --describe > "$out/share/sparkwerx/capture-build.json"
    test ! -e "$out/bin/sunshine"
    test ! -e "$out/lib/systemd"
    test ! -e "$out/lib/udev"
    test ! -e "$out/share/systemd"
    test ! -e "$out/share/applications"
    test -s "$out/assets/shaders/opengl/ConvertY.frag"
    test -s "$out/assets/shaders/opengl/ConvertUV.frag"
    test -s "$out/assets/shaders/opengl/ConvertUV.vert"
    test -s "$out/assets/shaders/opengl/Scene.frag"
    test -s "$out/assets/shaders/opengl/Scene.vert"
  '';
  doInstallCheck = false; # This executable installs no upstream udev rules.
  meta = old.meta // {
    description = "Offline Sunshine capture/encode diagnostic; not a streaming server";
    mainProgram = "sparkwerx-sunshine-capture";
  };
})
