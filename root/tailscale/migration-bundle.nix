{
  pkgs,
  transactionProgram,
  generationOne,
  generationTwo,
  generationThree,
  generationFour,
  rollbackDelay ? "10min",
  name ? "dgx-tailscale-migration",
}:

let
  stateDirectory = "/var/lib/dgx-setup/tailscale-migration";
  armedPath = "${stateDirectory}/armed";
  rolledBackPath = "${stateDirectory}/rolled-back";

  runner = pkgs.writeShellScript "${name}-runner" ''
    set -uo pipefail

    if [ "$#" -ne 1 ]; then
      printf 'Usage: %s apply|apply-guarded|rollback|verify-before|verify-after\n' "$0" >&2
      exit 2
    fi

    action="$1"
    case "$action" in
      apply | verify-before | verify-after)
        exec ${pkgs.bash}/bin/bash ${transactionProgram} \
          "$action" \
          ${generationOne} \
          ${generationTwo} \
          ${generationThree} \
          ${generationFour}
        ;;
      apply-guarded)
        ${pkgs.coreutils}/bin/rm -f -- \
          ${stateDirectory}/migrated ${rolledBackPath}
        ${pkgs.coreutils}/bin/touch -- ${stateDirectory}/applying
        # Let the detached launcher print reconnect instructions before the
        # intentional daemon restart cuts a Tailscale SSH transport.
        ${pkgs.coreutils}/bin/sleep 3
        ${pkgs.bash}/bin/bash ${transactionProgram} \
          apply \
          ${generationOne} \
          ${generationTwo} \
          ${generationThree} \
          ${generationFour}
        status="$?"
        ${pkgs.coreutils}/bin/rm -f -- ${stateDirectory}/applying
        if [ "$status" -eq 0 ]; then
          ${pkgs.coreutils}/bin/touch -- ${stateDirectory}/migrated
          exit 0
        fi
        if ${pkgs.bash}/bin/bash ${transactionProgram} \
          verify-before \
          ${generationOne} \
          ${generationTwo} \
          ${generationThree} \
          ${generationFour}; then
          ${pkgs.coreutils}/bin/rm -f -- ${armedPath}
          ${pkgs.coreutils}/bin/touch -- ${rolledBackPath}
        fi
        exit "$status"
        ;;
      rollback)
        ${pkgs.bash}/bin/bash ${transactionProgram} \
          rollback \
          ${generationOne} \
          ${generationTwo} \
          ${generationThree} \
          ${generationFour}
        status="$?"
        if [ "$status" -eq 0 ]; then
          ${pkgs.coreutils}/bin/rm -f -- \
            ${armedPath} ${stateDirectory}/applying ${stateDirectory}/migrated
          ${pkgs.coreutils}/bin/touch -- ${rolledBackPath}
          exit 0
        fi
        exit "$status"
        ;;
      *)
        printf 'Unknown migration action: %s\n' "$action" >&2
        exit 2
        ;;
    esac
  '';
in
pkgs.runCommand name { } ''
  mkdir -p "$out/bin" "$out/lib/systemd/system"
  ln -s ${runner} "$out/bin/dgx-root-tailscale-migration"

  cat >"$out/lib/systemd/system/dgx-tailscale-migration-rollback.service" <<EOF
  [Unit]
  Description=Rollback the guarded DGX Tailscale ownership migration
  ConditionPathExists=${armedPath}
  StartLimitIntervalSec=5min
  StartLimitBurst=6

  [Service]
  Type=oneshot
  ExecStart=$out/bin/dgx-root-tailscale-migration rollback
  Restart=on-failure
  RestartSec=15s
  EOF

  cat >"$out/lib/systemd/system/dgx-tailscale-migration-rollback.timer" <<EOF
  [Unit]
  Description=Rollback unconfirmed DGX Tailscale ownership migration
  ConditionPathExists=${armedPath}

  [Timer]
  OnActiveSec=${rollbackDelay}
  AccuracySec=1s
  Unit=dgx-tailscale-migration-rollback.service

  [Install]
  WantedBy=timers.target
  EOF
''
