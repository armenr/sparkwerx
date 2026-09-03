# Frozen root dependency lane

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: live root evidence decoupled from user/package lock refreshes

## Boundary

The live System Manager configuration and all of its disposable tests now use
the dedicated `nixpkgs-root` input. It is fixed at the already-proven
`nixos-26.05` revision
`a9e6d84f9c2f9012f5fe7d964a7851352300e61a`. System Manager follows that
input; its packages, recovery bundle, closure inspection, policy derivation,
container test hosts, and root-only parser test all use the same root package
set.

The ordinary `nixpkgs` input remains the independently refreshable stable lane
for Home Manager, the fleet base, and shared user infrastructure.
`nixpkgs-apps` remains the independently refreshable fast-application lane.
The normal dependency updater excludes both `nixpkgs-root` and
`system-manager`, captures the complete root evidence fingerprint before and
after a user/package refresh, and refuses to proceed if it changes.

Advancing either root input is a future root-generation operation with its own
review and test evidence; it is not routine package maintenance.

## Identity proof

Adding the dedicated input and redirecting root evaluation produced no change
to any reviewed root artifact. Machine comparison found exact equality for:

- generation-one output
  `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager`;
- generation-two output
  `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager`;
- generation-three output
  `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager`;
- recovery bundle
  `/nix/store/wpikhcgj77ws90j4ivdp3498mlmffyax-dgx-root-reboot-recovery`;
- root policy and parser derivations; and
- all six recorded disposable activation/registration/switch/boot/recovery
  test derivations.

The root-manager policy built successfully, the complete flake evaluation
passed, and the live read-only classifier remained
`ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`. No profile,
package, service, boot link, recovery unit, or other host state was changed.
