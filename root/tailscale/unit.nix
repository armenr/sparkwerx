{
  runCommand,
  tailscale,
  writeText,
}:
let
  unitText = ''
    [Unit]
    Description=Tailscale node agent (DGX fleet access plane)
    Documentation=https://tailscale.com/docs/
    Wants=network-pre.target
    After=network-pre.target NetworkManager.service systemd-resolved.service

    [Service]
    # Defaults are explicit and non-secret. A future root manager may generate
    # this optional file for reviewed host-specific flags; never put auth keys
    # or mutable node identity in the Nix store.
    Environment="PORT=41641"
    Environment="FLAGS="
    EnvironmentFile=-/etc/dgx-setup/tailscaled.env
    ExecStart=${tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=''${PORT} $FLAGS
    ExecStopPost=${tailscale}/bin/tailscaled --cleanup
    Restart=on-failure
    RuntimeDirectory=tailscale
    RuntimeDirectoryMode=0755
    StateDirectory=tailscale
    StateDirectoryMode=0700
    CacheDirectory=tailscale
    CacheDirectoryMode=0750
    Type=notify

    [Install]
    WantedBy=multi-user.target
  '';
  waitOnlineUnitText = ''
    [Unit]
    Description=Wait for Tailscale to be online
    After=tailscaled.service
    Requires=tailscaled.service

    [Service]
    Type=oneshot
    ExecStart=${tailscale}/bin/tailscale wait
    RemainAfterExit=yes

    [Install]
    WantedBy=tailscale-online.target
  '';
  onlineTargetText = ''
    [Unit]
    Description=Tailscale is online
    Requires=tailscale-wait-online.service
    After=tailscale-wait-online.service
  '';
  tailscaledUnitFile = writeText "tailscaled.service" unitText;
  waitOnlineUnitFile = writeText "tailscale-wait-online.service" waitOnlineUnitText;
  onlineTargetFile = writeText "tailscale-online.target" onlineTargetText;
in
{
  inherit unitText waitOnlineUnitText onlineTargetText;
  package = runCommand "tailscale-systemd-units" { } ''
    install -Dm644 ${tailscaledUnitFile} \
      "$out/lib/systemd/system/tailscaled.service"
    install -Dm644 ${waitOnlineUnitFile} \
      "$out/lib/systemd/system/tailscale-wait-online.service"
    install -Dm644 ${onlineTargetFile} \
      "$out/lib/systemd/system/tailscale-online.target"
  '';
}
