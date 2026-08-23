#!/usr/bin/env bash
set -euo pipefail

package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

command_version() {
  "$@" 2>/dev/null | head -n 1 || true
}

# Keep Tailscale inventory deliberately narrow. Raw status and preferences can
# contain node, address, identity, and tailnet data that must never enter Git.
tailscale_version=""
tailscale_backend=""
tailscale_self_online=""
tailscale_want_running=""
tailscale_run_ssh=""
if command -v tailscale >/dev/null 2>&1; then
  tailscale_version="$(
    tailscale version --json 2>/dev/null |
      jq -r '.short // .majorMinorPatch // empty' 2>/dev/null || true
  )"
  tailscale_backend="$(
    timeout 10s tailscale status --json 2>/dev/null |
      jq -r '.BackendState // empty' 2>/dev/null || true
  )"
  tailscale_self_online="$(
    timeout 10s tailscale status --json 2>/dev/null |
      jq -r 'if .Self.Online == null then empty else (.Self.Online | tostring) end' \
        2>/dev/null || true
  )"
  tailscale_want_running="$(
    timeout 10s tailscale debug prefs 2>/dev/null |
      jq -r 'if .WantRunning == null then empty else (.WantRunning | tostring) end' \
        2>/dev/null || true
  )"
  tailscale_run_ssh="$(
    timeout 10s tailscale debug prefs 2>/dev/null |
      jq -r 'if .RunSSH == null then empty else (.RunSSH | tostring) end' \
        2>/dev/null || true
  )"
fi

jq --null-input \
  --arg schema_version "1" \
  --arg captured_at "$(date --iso-8601=seconds)" \
  --arg hostname "$(hostnamectl --static)" \
  --arg architecture "$(uname -m)" \
  --arg debian_architecture "$(dpkg --print-architecture)" \
  --arg os "$(. /etc/os-release && printf '%s' "$PRETTY_NAME")" \
  --arg kernel "$(uname -r)" \
  --arg cpu_count "$(getconf _NPROCESSORS_ONLN)" \
  --arg memory "$(free -h | awk '/^Mem:/ { print $2 }')" \
  --arg root_filesystem "$(findmnt -no FSTYPE /)" \
  --arg secure_boot "$(mokutil --sb-state 2>/dev/null || true)" \
  --arg gpu "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || true)" \
  --arg nvidia_driver "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || true)" \
  --arg display_manager "$(systemctl is-active display-manager 2>/dev/null || true)" \
  --arg nix "$(command_version nix --version)" \
  --arg nix_daemon "$(systemctl is-active nix-daemon 2>/dev/null || true)" \
  --arg codex "$(command_version codex --version)" \
  --arg chatgpt "$(package_version chatgpt)" \
  --arg docker "$(command_version docker --version)" \
  --arg nvidia_container_toolkit "$(package_version nvidia-container-toolkit)" \
  --arg tailscale "$tailscale_version" \
  --arg tailscale_package "$(package_version tailscale)" \
  --arg tailscale_daemon "$(systemctl is-active tailscaled 2>/dev/null || true)" \
  --arg tailscale_enabled "$(systemctl is-enabled tailscaled 2>/dev/null || true)" \
  --arg tailscale_backend "$tailscale_backend" \
  --arg tailscale_self_online "$tailscale_self_online" \
  --arg tailscale_want_running "$tailscale_want_running" \
  --arg tailscale_run_ssh "$tailscale_run_ssh" \
  '{
    schema_version: $schema_version,
    captured_at: $captured_at,
    host: $hostname,
    platform: {
      architecture: $architecture,
      debian_architecture: $debian_architecture,
      os: $os,
      kernel: $kernel,
      cpu_count: $cpu_count,
      memory: $memory,
      root_filesystem: $root_filesystem,
      secure_boot: $secure_boot
    },
    graphics: {
      gpu: $gpu,
      nvidia_driver: $nvidia_driver,
      display_manager_state: $display_manager
    },
    software: {
      nix: $nix,
      nix_daemon_state: $nix_daemon,
      codex: $codex,
      chatgpt_deb_version: $chatgpt,
      docker: $docker,
      nvidia_container_toolkit_version: $nvidia_container_toolkit
    },
    fleet_access: {
      tailscale: {
        client_version: $tailscale,
        apt_package_version: $tailscale_package,
        daemon_state: $tailscale_daemon,
        unit_enabled: $tailscale_enabled,
        backend_state: $tailscale_backend,
        self_online: $tailscale_self_online,
        want_running: $tailscale_want_running,
        ssh_enabled: $tailscale_run_ssh
      }
    }
  }'
