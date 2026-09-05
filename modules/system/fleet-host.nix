{
  dgxHostName,
  pkgs,
  ...
}:

{
  imports = [ ./minimal-root.nix ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # This marker identifies the declaration that owns the bounded root surface.
  # It contains no secret or mutable host data and deliberately refuses to
  # replace a collision.  Unlike the historical sparkle-01 pilot marker, this
  # module is parameterized so a newly declared fleet host gets its own exact
  # candidate without replaying sparkle-01's five experimental generations.
  environment.etc."dgx-setup/canary" = {
    text = ''
      schema=1
      host=${dgxHostName}
      owner=DGX-setup
      purpose=declarative fleet root controller
      lifecycle=fresh-host
    '';
    replaceExisting = false;
  };

  systemd.services.dgx-setup-canary = {
    description = "DGX setup fleet root-controller canary";
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/test -L /etc/dgx-setup/canary";
    };
  };
}
