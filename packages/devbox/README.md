# Devbox current-release adapter

The fleet base wants current Devbox, but on 2026-08-23 both locked stable and
apps Nixpkgs package 0.17.5 while upstream final is 0.18.0. `default.nix`
therefore overrides only the existing Nixpkgs recipe's version, immutable
upstream source, Go vendor graph, and embedded version flag. It still uses the
reviewed Nixpkgs build logic and installs no service.

`source.json` is the reproducible source of truth. The adapter exists to bridge
packaging lag, not to become a permanent fork. On every dependency update:

1. compare its version with final tags in the official Devbox repository;
2. compare both locked Nixpkgs Devbox versions;
3. prefer the stock package as soon as it provides the same/newer approved
   release and passes the ARM64 build/SBOM checks;
4. otherwise update the immutable source hash and Go `vendorHash`, build
   `.#devbox` with `--no-link`, verify `devbox version`, and update the SBOM.

The normal dependency updater refuses to continue when a newer upstream tag
exists because deriving the new Go vendor hash and reviewing release behavior
must be explicit. Never run Devbox's bootstrap installer from this package or
allow it to install, replace, or update the machine's root Nix runtime.
