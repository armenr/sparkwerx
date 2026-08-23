{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  release = builtins.fromJSON (builtins.readFile ./source.json);
in
# Temporary anti-downgrade package for the fleet access plane.
# Locked stable Nixpkgs was older than the approved installed Tailscale release.
# Re-check and prefer pkgs.tailscale on every update; see
# .agents/skills/dgx-spark-ops/references/tailscale.md.
stdenvNoCC.mkDerivation {
  pname = "tailscale";
  inherit (release) version;

  src = fetchurl {
    inherit (release) url hash;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 tailscale "$out/bin/tailscale"
    install -Dm755 tailscaled "$out/bin/tailscaled"

    runHook postInstall
  '';

  # Preserve the vendor release payload byte-for-byte. In particular, do not
  # strip or patch the statically linked upstream Go binaries.
  dontStrip = true;
  dontPatchELF = true;

  passthru = {
    inherit release;
    updateScript = ../../scripts/update-tailscale.sh;
  };

  meta = {
    description = "WireGuard-based mesh network and fleet access plane";
    homepage = "https://tailscale.com/";
    changelog = "https://tailscale.com/changelog";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "tailscale";
  };
}
