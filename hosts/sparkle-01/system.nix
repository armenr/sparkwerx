{ pkgs, ... }:

{
  imports = [ ../../modules/system/minimal-root.nix ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Harmless ownership proof for the future root-manager pilot. It contains no
  # secret or mutable state, refuses to replace a collision, and deactivation
  # removes only the repository-owned symlink.
  environment.etc."dgx-setup/canary" = {
    text = ''
      schema=1
      host=sparkle-01
      owner=DGX-setup
      purpose=system-manager activation and rollback canary
    '';
    replaceExisting = false;
  };

  # This oneshot proves unit installation and removal without opening a port,
  # changing permissions, writing persistent state, or touching another unit.
  systemd.services.dgx-setup-canary = {
    description = "DGX setup root-manager canary";
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/test -L /etc/dgx-setup/canary";
    };
  };
}
