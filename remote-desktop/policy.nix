{ lib, hostSpec }:
let
  defaults = builtins.fromJSON (builtins.readFile ./defaults.json);
  presets = builtins.fromJSON (builtins.readFile ./client-presets.json);
  declared = hostSpec.desktop.remoteDesktop or { };
  cfg = defaults // declared;
  unknown = builtins.filter (key: !(builtins.hasAttr key defaults)) (builtins.attrNames declared);
in
assert lib.assertMsg (
  unknown == [ ]
) "Unknown remoteDesktop setting; see remote-desktop/defaults.json.";
assert lib.assertMsg (builtins.isBool cfg.selected) "remoteDesktop.selected must be boolean.";
assert lib.assertMsg (cfg.backend == "sunshine") "The selected remote desktop backend is Sunshine.";
assert lib.assertMsg (cfg.transport == "tailscale") "Remote desktop must use Tailscale.";
assert lib.assertMsg (builtins.hasAttr cfg.clientPreset presets) "Unknown Moonlight client preset.";
assert lib.assertMsg (
  !cfg.selected || (hostSpec.access.tailscale.selected or false)
) "Remote desktop requires the optional Tailscale role.";
{
  inherit (cfg)
    selected
    backend
    transport
    clientPreset
    ;
  client = presets.${cfg.clientPreset};
  # Selection is durable intent, not authority to start a graphical session.
  # There is deliberately no enable/start command until capture, driver access,
  # input permissions, and a guarded desktop round trip have been tested.
  state =
    if !cfg.selected then
      "DISABLED"
    else if hostSpec.desktop.mode == "headless" then
      "DORMANT_HEADLESS"
    else
      "PREPARATION_REQUIRED";
  activationSupported = false;
  installedPackages = [ ];
  network = {
    interface = "tailscale0";
    tcp = [
      47984
      47989
      48010
    ];
    udp = [
      47998
      47999
      48000
    ];
    managementTcp = 47990;
    managementAccess = "ssh-forward-only";
  };
}
