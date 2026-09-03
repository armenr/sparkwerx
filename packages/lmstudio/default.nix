{
  appimageTools,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
}:
let
  release = builtins.fromJSON (builtins.readFile ./source.json);

  src = fetchurl {
    inherit (release) url hash;
  };

  appimageContents = appimageTools.extract {
    pname = "lmstudio";
    inherit (release) version;
    inherit src;
  };
in
# Temporary current-release adapter. The locked apps branch still packages an
# older release. Its generic Bubblewrap AppImage wrapper cannot start under the
# factory Ubuntu AppArmor user-namespace restriction, so this keeps the current
# Nixpkgs extraction/layout logic but runs the vendor AppRun directly against
# the DGX Ubuntu runtime. It packages only the desktop app and bundled `lms`
# CLI: no llmster service, model, API listener, autostart, account data, or
# mutable application state is declared.
stdenv.mkDerivation {
  pname = "lmstudio";
  inherit (release) version;

  src = appimageContents;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # This release ships pre-rendered icons for every hicolor size.
    mkdir -p "$out/share/icons"
    cp -r ${appimageContents}/usr/share/icons/hicolor "$out/share/icons/"

    install -m 0444 -D \
      ${appimageContents}/ai.elementlabs.lmstudio.desktop \
      "$out/share/applications/ai.elementlabs.lmstudio.desktop"

    substituteInPlace \
      "$out/share/applications/ai.elementlabs.lmstudio.desktop" \
      --replace-fail 'Exec=AppRun %U' 'Exec=lm-studio %U'

    # Copy only the small vendor launcher so its shell interpreter can be
    # pinned. APPDIR remains the immutable extracted application tree. AppRun
    # follows LM Studio's own fallback to --no-sandbox when Ubuntu AppArmor
    # blocks its user-namespace probe; no host policy is weakened here.
    mkdir -p "$out/bin" "$out/libexec"
    install -m 0755 ${appimageContents}/AppRun "$out/libexec/lmstudio-AppRun"
    patchShebangs "$out/libexec/lmstudio-AppRun"
    makeWrapper "$out/libexec/lmstudio-AppRun" "$out/bin/lm-studio" \
      --set APPDIR ${appimageContents}

    # Preserve LM Studio's bundled Deno standalone executable byte-for-byte.
    # patchelf appends ELF data and makes Deno lose its payload-at-EOF marker.
    # Invoking a Nix loader explicitly has the same problem because Deno then
    # sees the loader as /proc/self/exe. Keep the vendor interpreter and supply
    # only libgcc from Nix; the DGX Ubuntu substrate supplies its glibc loader.
    mkdir -p "$out/libexec"
    ln -s \
      ${appimageContents}/resources/app/.webpack/lms \
      "$out/libexec/lms-real"
    makeWrapper "$out/libexec/lms-real" "$out/bin/lms" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"

    runHook postInstall
  '';

  dontPatchELF = true;
  dontStrip = true;

  passthru = {
    inherit release;
    avoidsUserNamespaceWrapper = true;
    desktopUsesFactoryLinuxRuntime = true;
    lmsUsesFactoryGlibcLoader = true;
    updateScript = ../../scripts/update-lmstudio.sh;
  };

  meta = {
    description = "Desktop application for running local language models";
    homepage = "https://lmstudio.ai/";
    license = lib.licenses.unfree;
    mainProgram = "lm-studio";
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
