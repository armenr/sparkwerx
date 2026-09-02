{
  config,
  lib,
  ...
}:

let
  cfg = config.dgx.root.bootPersistence;
  expectedWantedBy = lib.optional cfg.enable "default.target";
in
{
  options.dgx.root.bootPersistence.enable = lib.mkEnableOption ''
    the reviewed System Manager boot edge from default.target
  '';

  config = {
    # System Manager activates this target explicitly during every switch. The
    # only additional effect of enabling this option is the declaratively
    # managed /etc/systemd/system/default.target.wants/system-manager.target
    # symlink. Keep the default false until the reboot/rollback milestone has
    # passed its disposable test and received separate live-host approval.
    systemd.targets.system-manager.wantedBy = lib.mkForce expectedWantedBy;

    assertions = [
      {
        assertion = config.systemd.targets.system-manager.wantedBy == expectedWantedBy;
        message = "The DGX System Manager boot edge must exactly match its explicit policy switch.";
      }
    ];
  };
}
