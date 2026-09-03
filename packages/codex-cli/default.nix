{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  release = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenvNoCC.mkDerivation {
  pname = "codex-cli";
  inherit (release) version;

  src = fetchurl {
    inherit (release) url hash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    tar -xzf "$src" -C "$out"

    test -f "$out/codex-package.json"
    test -x "$out/bin/codex"
    test -x "$out/bin/codex-code-mode-host"
    test -x "$out/codex-path/rg"
    test -x "$out/codex-resources/bwrap"
    test "$(HOME="$TMPDIR" CODEX_HOME="$TMPDIR/codex-home" \
      "$out/bin/codex" --version)" = "codex-cli ${release.version}"

    runHook postInstall
  '';

  # Preserve OpenAI's release payload and its embedded signatures/build IDs.
  dontStrip = true;
  dontPatchELF = true;

  passthru = {
    inherit release;
    updateScript = ../../scripts/update-codex.sh;
  };

  meta = {
    description = "OpenAI Codex command-line coding agent";
    homepage = "https://developers.openai.com/codex/cli/";
    changelog = "https://github.com/openai/codex/releases/tag/${release.releaseTag}";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "codex";
  };
}
