{
  devbox,
  fetchFromGitHub,
}:
let
  release = builtins.fromJSON (builtins.readFile ./source.json);
in
# Temporary current-release adapter. nixpkgs-apps still packages 0.17.5, so the
# fleet base pins the immutable upstream 0.18.0 source and Go dependency graph.
# This packages Devbox itself; it never invokes Devbox's Nix bootstrap installer
# and does not grant Devbox ownership of the system Nix runtime.
devbox.overrideAttrs (oldAttrs: {
  inherit (release) version vendorHash;

  src = fetchFromGitHub {
    inherit (release)
      owner
      repo
      tag
      hash
      ;
  };

  ldflags = [
    "-s"
    "-w"
    "-X go.jetify.com/devbox/internal/build.Version=${release.version}"
  ];

  passthru = (oldAttrs.passthru or { }) // {
    inherit release;
  };
})
