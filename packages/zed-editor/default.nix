{
  fetchurl,
  lib,
  makeWrapper,
  stdenvNoCC,
}:
let
  release = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenvNoCC.mkDerivation {
  pname = "zed-editor";
  inherit (release) version;

  src = fetchurl {
    inherit (release) url hash;
  };

  sourceRoot = "zed.app";
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -a . "$out/"

    # Keep the official CLI/editor binaries byte-for-byte intact. Their
    # documented Linux contract intentionally uses the DGX Ubuntu glibc and
    # desktop/Vulkan libraries. The wrapper only disables Zed's self-updater;
    # mutable settings, credentials, extensions, and project state stay under
    # the user's normal application directories.
    mv "$out/bin/zed" "$out/bin/.zed-unwrapped"
    makeWrapper "$out/bin/.zed-unwrapped" "$out/bin/zed" \
      --set ZED_UPDATE_EXPLANATION \
        "Zed is managed by the DGX-setup Nix profile; update it through the repository."

    test -x "$out/bin/zed"
    test -x "$out/bin/.zed-unwrapped"
    test -x "$out/libexec/zed-editor"
    test -f "$out/share/applications/dev.zed.Zed.desktop"

    runHook postInstall
  '';

  # Preserve the vendor release payload, signatures/build IDs, interpreter,
  # and relative RPATH. The factory Ubuntu substrate satisfies that ABI while
  # its NVIDIA userspace remains the authoritative Vulkan implementation.
  dontPatchELF = true;
  dontStrip = true;

  passthru = {
    inherit release;
    usesFactoryLinuxRuntime = true;
    updateScript = ../../scripts/update-zed.sh;
  };

  meta = {
    description = "High-performance collaborative code editor";
    homepage = "https://zed.dev/";
    changelog = "https://github.com/zed-industries/zed/releases/tag/${release.releaseTag}";
    license = lib.licenses.gpl3Only;
    mainProgram = "zed";
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
