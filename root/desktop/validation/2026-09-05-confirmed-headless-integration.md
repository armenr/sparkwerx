# Confirmed headless retained-state integration — 2026-09-05

## Result

**PASS. `sparkle-01` is fully converged for its current declared state.**

After the guarded Tailscale migration and guarded factory-GNOME-to-headless
transition were confirmed, the complete operator-facing regression passed from
repository commit `9883d6cded75932abf1db7d452a397e013b1ced4`:

```console
./scripts/test-desktop-stack-integration.sh
```

The final run reported:

```text
PASS|desktop_headless_transaction|failure injection, exact headless switch, idempotent factory rollback, and host non-mutation passed
PASS|desktop_mode_lifecycle|headless/GNOME persistence, access continuity, reversibility, and factory fallback passed; live host stayed exact
PASS|desktop_switch_lifecycle|persistent rollback, same-boot confirmation, reboot recovery, and host non-mutation passed
PASS|dgx_setup_plan_test|declaration, bootstrap adoption, Nix-managed Tailscale, headless generation five, privacy, and zero-mutation checks passed
PASS|tailscale_unit_lifecycle|container handoff/reboot/rollback passed; live host stayed exact
PASS|dgx_setup_apply_test|Nix, Home, Nix-managed Tailscale, and headless generation five converged as no-ops; root, services, and mutable state stayed exact
PASS|post_tailscale_integration|plan, Nix bootstrap lifecycle, Tailscale lifecycle, and complete live headless apply no-op all passed
PASS|desktop_stack_integration|transaction, mode lifecycle, guarded rollback, and complete headless integration passed
```

The destructive-looking desktop, reboot, rollback, and apt-to-Nix migration
cases ran only in disposable Ubuntu containers. The live-host part verified the
already-retained state as a no-op. It did not activate a profile, switch a
target, restart a service, change Tailscale identity, alter mutable state, or
reboot the host.

## Exact retained host state

| Field | Verified value |
| --- | --- |
| Host classifier | `ACTIVE_REGISTERED_GENERATION_FIVE_HEADLESS_TAILSCALE_NIX_MANAGED` |
| Selected/live/boot-linked generation | `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager` |
| Fleet plan result | `PLAN_STATUS=READY` |
| Fleet apply result | `APPLY_STATUS=COMPLETE` |
| Desktop result | `DESKTOP_STATUS=HEADLESS_CONFIRMED` |
| Tailscale result | `MIGRATION_STATUS=CONFIRMED_NIX_OWNED` |
| systemd | `running`; zero failed units |
| Active mode | `dgx-headless.target`; factory GNOME remains installed |
| Active access/base services | Nix-managed Tailscale, Docker, Dashboard Admin, NVIDIA persistence |
| Intentionally inactive graphical services | GDM and the Dashboard GUI |
| Transition guards | Absent; no recovery countdown is active |

The preceding Snap refresh of `snapd-desktop-integration` revision 396 changed
the generated unit graph and set `NeedDaemonReload=yes`. The reviewed
`scripts/reload-systemd-and-test-post-desktop.sh` helper performed only a daemon
reload and proved that process identities, unit fragments, selected generation,
Tailscale identity, and headless mode remained unchanged. Both desktop and
Tailscale status were exact afterward.

## Exact code and disposable derivations

Evidence was captured at `2026-09-05T18:00:52Z` with a clean worktree at the
commit above.

| Artifact | Exact value |
| --- | --- |
| Complete desktop regression SHA-256 | `e6366208647641a177058db202c08092cfcc5623766b2206c23242e1c70d2e88` |
| Post-Tailscale regression SHA-256 | `654475ebe2924db1740ec232e4de5d08fc1970b70a0a66f6574a2a6f70818547` |
| Fleet plan test SHA-256 | `c8996488ee38d2fa471d38a1e281fdba9078bf91a8d5871dfcdc0e8918f52968` |
| Fleet apply test SHA-256 | `633b9aabcad6353778f4216e9ce67e2f9d3329bd3f4cffc4bdc8926e1fa83e7d` |
| Fleet operator SHA-256 | `ca4d58243ef6d0aca3f1dae801934e800d8cbce023b0fa7a6d5767147928d50d` |
| Home operator SHA-256 | `6857ee75df36ba580ed7cac97b23a33ab9f5fee56743f920a30540fee2d0de4e` |
| Tailscale operator SHA-256 | `8566c7c4ecdc3b85cfb2a6df0ab827b47fd918e090b655f583c25f2ba3c156c1` |
| Desktop operator SHA-256 | `253cfb76e2c51f40503f867d3a7c1a8f830de167092e5f81871097a01030bf61` |
| Headless transaction derivation | `/nix/store/76x1xcqidxq7s6fn0wsj2d18gq31d5vg-container-test-dgx-desktop-headless-transaction.drv` |
| Desktop mode lifecycle derivation | `/nix/store/yzzf9h9lwd9jj2c54y6xhr4f7b2njppj-container-test-dgx-desktop-mode-lifecycle.drv` |
| Guarded desktop switch derivation | `/nix/store/b0j7shxdp46vpx0c3mdms2h7xsn3ixxn-container-test-dgx-desktop-switch-lifecycle.drv` |
| Tailscale lifecycle derivation | `/nix/store/z3ygmg4cm0hhc3bvng7kgcwy09a2p0ba-container-test-dgx-tailscale-unit-lifecycle.drv` |
| Nix bootstrap lifecycle derivation | `/nix/store/p7s3xffskdk9mycrmmxr673xx1k3gwg9-container-test-dgx-nix-bootstrap-lifecycle.drv` |

## Scope boundary

This is the current authority for an already bootstrapped host whose guarded
Tailscale migration and desktop transition have completed. On such a host,
`scripts/dgx-setup plan` can honestly report `READY`, and
`scripts/dgx-setup apply` can honestly report `COMPLETE` while converging every
enabled declared layer as a no-op.

This does **not** yet mean that one `dgx-setup apply` invocation on a pristine
DGX automatically performs the one-time apt-to-Nix Tailscale handoff or the
factory-GNOME-to-headless transition. Those transitions have independently
passed their guarded container and live-host lifecycles, but the top-level
operator still refuses to cross either boundary implicitly. Composing those
proven operators into a fresh-host workflow is the remaining fleet-bootstrap
milestone.
