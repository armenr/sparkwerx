{
  pkgs,
  transactionProgram,
  factoryGeneration,
  headlessGeneration,
  rollbackDelay ? "10min",
  name ? "dgx-fleet-bootstrap",
}:

let
  stateDirectory = "/var/lib/dgx-setup/fleet-bootstrap";
  phasePath = "${stateDirectory}/phase";
  armedPath = "${stateDirectory}/armed";
  factoryPath = "${stateDirectory}/factory";
  headlessPath = "${stateDirectory}/headless";
  rolledBackPath = "${stateDirectory}/rolled-back";

  runTransaction = action: ''
    ${pkgs.bash}/bin/bash ${transactionProgram} \
      ${action} \
      ${factoryGeneration} \
      ${headlessGeneration}
  '';

  runner = pkgs.writeShellScript "${name}-runner" ''
    set -uo pipefail

    if [ "$#" -ne 1 ]; then
      printf 'Usage: %s install-factory|install-factory-guarded|install-headless|install-headless-guarded|rollback|verify-pristine|verify-factory|verify-headless\n' "$0" >&2
      exit 2
    fi

    action="$1"
    phase="$(${pkgs.coreutils}/bin/cat ${phasePath} 2>/dev/null || true)"
    if [ "$phase" = factory ] && [ -f ${stateDirectory}/context ]; then
      snapshot="$(${pkgs.gawk}/bin/awk -F= \
        '$1 == "snapshot" { sub(/^[^=]*=/, ""); print; exit }' \
        ${stateDirectory}/context)"
      if [ -n "$snapshot" ] && [ -f "$snapshot/tailscale-state.before.sha256" ] && \
        ${pkgs.gnugrep}/bin/grep -Fx \
          'ABSENT|/var/lib/tailscale/tailscaled.state' \
          "$snapshot/tailscale-state.before.sha256" >/dev/null; then
        export DGX_FLEET_BOOTSTRAP_TAILSCALE_WAS_ABSENT=1
      fi
    fi
    case "$action" in
      install-factory)
        exec ${runTransaction "install-factory"}
        ;;
      install-headless)
        exec ${runTransaction "install-headless"}
        ;;
      verify-pristine)
        exec ${runTransaction "verify-pristine"}
        ;;
      verify-factory)
        exec ${runTransaction "verify-factory"}
        ;;
      verify-headless)
        exec ${runTransaction "verify-headless"}
        ;;
      install-factory-guarded)
        [ "$phase" = factory ] || {
          printf 'Fresh-host guard is not armed for the factory phase\n' >&2
          exit 1
        }
        ${pkgs.coreutils}/bin/rm -f -- \
          ${factoryPath} ${headlessPath} ${rolledBackPath}
        ${pkgs.coreutils}/bin/touch -- ${stateDirectory}/applying
        ${runTransaction "install-factory"}
        status="$?"
        ${pkgs.coreutils}/bin/rm -f -- ${stateDirectory}/applying
        if [ "$status" -eq 0 ]; then
          ${pkgs.coreutils}/bin/touch -- ${factoryPath}
          exit 0
        fi
        if ${runTransaction "verify-pristine"}then
          ${pkgs.coreutils}/bin/rm -f -- ${armedPath}
          ${pkgs.coreutils}/bin/touch -- ${rolledBackPath}
        fi
        exit "$status"
        ;;
      install-headless-guarded)
        [ "$phase" = headless ] || {
          printf 'Fresh-host guard is not armed for the headless phase\n' >&2
          exit 1
        }
        ${pkgs.coreutils}/bin/rm -f -- ${headlessPath} ${rolledBackPath}
        ${pkgs.coreutils}/bin/touch -- ${stateDirectory}/applying
        # Give a local graphical caller time to receive the reconnect message.
        ${pkgs.coreutils}/bin/sleep 2
        ${runTransaction "install-headless"}
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
      rollback)
        case "$phase" in
          factory)
            ${runTransaction "rollback-pristine"}
            ;;
          headless)
            ${runTransaction "rollback-factory"}
            ;;
          *)
            printf 'Fresh-host rollback phase is invalid: %s\n' "$phase" >&2
            exit 1
            ;;
        esac
        status="$?"
        if [ "$status" -eq 0 ]; then
          ${pkgs.coreutils}/bin/rm -f -- \
            ${armedPath} ${stateDirectory}/applying \
            ${factoryPath} ${headlessPath}
          ${pkgs.coreutils}/bin/touch -- ${rolledBackPath}
          exit 0
        fi
        exit "$status"
        ;;
      *)
        printf 'Unknown fresh-host action: %s\n' "$action" >&2
        exit 2
        ;;
    esac
  '';
in
pkgs.runCommand name { } ''
  mkdir -p "$out/bin" "$out/lib/systemd/system"
  ln -s ${runner} "$out/bin/dgx-root-fleet-bootstrap"

  cat >"$out/lib/systemd/system/dgx-fleet-bootstrap-rollback.service" <<EOF
  [Unit]
  Description=Rollback an unconfirmed DGX fresh-host root transition
  ConditionPathExists=${armedPath}
  IgnoreOnIsolate=yes
  StartLimitIntervalSec=5min
  StartLimitBurst=6

  [Service]
  Type=oneshot
  ExecStart=$out/bin/dgx-root-fleet-bootstrap rollback
  Restart=on-failure
  RestartSec=15s
  EOF

  cat >"$out/lib/systemd/system/dgx-fleet-bootstrap-rollback.timer" <<EOF
  [Unit]
  Description=Rollback an unconfirmed DGX fresh-host root transition
  ConditionPathExists=${armedPath}
  IgnoreOnIsolate=yes

  [Timer]
  OnActiveSec=${rollbackDelay}
  AccuracySec=1s
  Unit=dgx-fleet-bootstrap-rollback.service

  [Install]
  WantedBy=timers.target
  EOF
''
