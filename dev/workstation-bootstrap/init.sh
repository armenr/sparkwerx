#!/usr/bin/env bash
set -euo pipefail
[[ -e /.dockerenv ]] || exit 1
# The container has a PRIVATE cgroup namespace, never a host cgroup bind mount.
mount -o remount,rw /sys/fs/cgroup
exec /sbin/init
