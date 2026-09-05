{
  pkgs,
  transactionProgram,
  generationOne,
  generationTwo,
  generationThree,
  generationFour,
  headlessGeneration,
  rollbackDelay ? "10min",
  name ? "dgx-desktop-switch",
}:

let
  stateDirectory = "/var/lib/dgx-setup/desktop-switch";
  armedPath = "${stateDirectory}/armed";
  headlessPath = "${stateDirectory}/headless";
  rolledBackPath = "${stateDirectory}/rolled-back";

  runTransaction = action: ''
    ${pkgs.bash}/bin/bash ${transactionProgram} \
      ${action} \
      ${generationOne} \
      ${generationTwo} \
      ${generationThree} \
      ${generationFour} \
      ${headlessGeneration}
  '';

  runner = pkgs.writeShellScript "${name}-runner" ''
    set -uo pipefail

    if [ "$#" -ne 1 ]; then
      printf 'Usage: %s apply-headless|apply-guarded|rollback-factory|rollback-guarded|verify-factory|verify-headless\n' "$0" >&2
      exit 2
    fi

    action="$1"
    case "$action" in
      apply-headless)
        exec ${runTransaction "apply-headless"}
        ;;
      rollback-factory)
        exec ${runTransaction "rollback-factory"}
        ;;
      verify-factory)
        exec ${runTransaction "verify-factory"}
        ;;
      verify-headless)
        exec ${runTransaction "verify-headless"}
        ;;
      apply-guarded)
        ${pkgs.coreutils}/bin/rm -f -- \
          ${headlessPath} ${rolledBackPath}
        ${pkgs.coreutils}/bin/touch -- ${stateDirectory}/applying
        # Give an interactive caller time to print reconnect/status guidance
        # before a local graphical terminal is intentionally stopped.
        ${pkgs.coreutils}/bin/sleep 2
        ${runTransaction "apply-headless"}
        status="$?"
        ${pkgs.coreutils}/bin/rm -f -- ${stateDirectory}/applying
        if [ "$status" -eq 0 ]; then
          ${pkgs.coreutils}/bin/touch -- ${headlessPath}
          exit 0
        fi
        if ${runTransaction "verify-factory"}then
          ${pkgs.coreutils}/bin/rm -f -- ${armedPath}
          ${pkgs.coreutils}/bin/touch -- ${rolledBackPath}
        fi
        exit "$status"
        ;;
      rollback-guarded)
        ${runTransaction "rollback-factory"}
        status="$?"
        if [ "$status" -eq 0 ]; then
          ${pkgs.coreutils}/bin/rm -f -- \
            ${armedPath} ${stateDirectory}/applying ${headlessPath}
          ${pkgs.coreutils}/bin/touch -- ${rolledBackPath}
          exit 0
        fi
        exit "$status"
        ;;
      *)
        printf 'Unknown desktop-switch action: %s\n' "$action" >&2
        exit 2
        ;;
    esac
  '';
in
pkgs.runCommand name { } ''
  mkdir -p "$out/bin" "$out/lib/systemd/system"
  ln -s ${runner} "$out/bin/dgx-root-desktop-switch"

  cat >"$out/lib/systemd/system/dgx-desktop-switch-rollback.service" <<EOF
  [Unit]
  Description=Rollback an unconfirmed DGX headless-mode switch
  ConditionPathExists=${armedPath}
  IgnoreOnIsolate=yes
  StartLimitIntervalSec=5min
  StartLimitBurst=6

  [Service]
  Type=oneshot
  ExecStart=$out/bin/dgx-root-desktop-switch rollback-guarded
  Restart=on-failure
  RestartSec=15s
  EOF

  cat >"$out/lib/systemd/system/dgx-desktop-switch-rollback.timer" <<EOF
  [Unit]
  Description=Rollback an unconfirmed DGX headless-mode switch
  ConditionPathExists=${armedPath}
  IgnoreOnIsolate=yes

  [Timer]
  OnActiveSec=${rollbackDelay}
  AccuracySec=1s
  Unit=dgx-desktop-switch-rollback.service

  [Install]
  WantedBy=timers.target
  EOF
''
