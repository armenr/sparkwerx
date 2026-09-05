# Dashboard-aware desktop stack validation — 2026-09-05

> This remains the pre-live implementation authority. The later successful
> host transition and complete retained-state rerun supersede it as current
> live convergence authority; see
> [the confirmed headless integration record](2026-09-05-confirmed-headless-integration.md).

## Result

**PASS.** The complete one-command desktop regression passed against repository
commit `abb852d320a01192236d862336bf60c31943714a`.

The three desktop transactions—including target isolation, failure injection,
four aggregate disposable reboots, persistent timed rollback, and cleanup—ran
only inside disposable Ubuntu containers. The final integration then proved
that the live Nix, Home Manager, Nix-managed Tailscale, root generation, desktop
mode, services, and mutable state remained exact no-ops.

```text
PASS|desktop_headless_transaction|failure injection, exact headless switch, idempotent factory rollback, and host non-mutation passed
PASS|desktop_mode_lifecycle|headless/GNOME persistence, access continuity, reversibility, and factory fallback passed; live host stayed exact
PASS|desktop_switch_lifecycle|persistent rollback, same-boot confirmation, reboot recovery, and host non-mutation passed
PASS|post_tailscale_integration|plan, Nix bootstrap lifecycle, Tailscale lifecycle, and live staged-apply no-op all passed
PASS|desktop_stack_integration|transaction, mode lifecycle, guarded rollback, and post-Tailscale integration passed
```

## Exact code and candidates

| Field | Exact value |
| --- | --- |
| Repository commit under test | `abb852d320a01192236d862336bf60c31943714a` |
| Desktop module SHA-256 | `256aa9ef7334143a314014ad68942910b8af4c2b9894383a1856df7ca26570c1` |
| Root transaction SHA-256 | `9318775e0dda09273026d337ca8463479919febe27a49451d14d741bebb3e1b8` |
| Guarded operator SHA-256 | `253cfb76e2c51f40503f867d3a7c1a8f830de167092e5f81871097a01030bf61` |
| Combined regression SHA-256 | `26e39b6fc8e7fdd32fb285f627e4c9049086d5b42899da16a6dfab3954e0fcab` |
| Post-Tailscale regression SHA-256 | `a98765ff6c6c0c2dc40f24ffc523b32010a36ae43205919375f2f47c87d43e2f` |
| Live/rollback generation four | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |
| Current headless candidate | `/nix/store/djp7ap9gc7kq6c5hhbqzzslvmg4vq3m1-system-manager` |
| Current factory-GNOME candidate | `/nix/store/i8224bkma5f805ncarwpfmbnd9yc1dn9-system-manager` |
| Current guarded switch bundle | `/nix/store/4148r540pysd6017n7j6fvyiv7541gzq-dgx-desktop-switch` |

The headless candidate is 312,131,456 closure bytes; the GNOME candidate is
312,131,424 closure bytes. Neither adds a desktop package, global package,
portal, user service, or daemon. The controller only supplies two immutable
orchestration targets, a selected default-target dispatcher, and a non-secret
mode marker.

## Exact container evidence

| Lifecycle | Registered UTC | Derivation | Output | Output SHA-256 (SRI) | Output SHA-256 (Nix base32) | NAR size |
| --- | --- | --- | --- | --- | --- | ---: |
| Generation-four/headless transaction | `2026-09-05T15:06:18Z` | `/nix/store/76x1xcqidxq7s6fn0wsj2d18gq31d5vg-container-test-dgx-desktop-headless-transaction.drv` | `/nix/store/bcby3i7d1ncj14plw4w4sw4x0aj9ni6f-container-test-dgx-desktop-headless-transaction` | `sha256-ZRKBC9IkC2+1sXYXXbTX7ZIiEo5+BYfSNYJNXEz0rnE=` | `sha256:0wdfyi65qkc26p98f1byiq9254pdsys5s5vnn6sny2r4s85q24k5` | 9,816 bytes |
| Headless/GNOME mode lifecycle | `2026-09-05T15:06:48Z` | `/nix/store/yzzf9h9lwd9jj2c54y6xhr4f7b2njppj-container-test-dgx-desktop-mode-lifecycle.drv` | `/nix/store/p0dnfn942gkn0wr5qc8hji26hfv75g8v-container-test-dgx-desktop-mode-lifecycle` | `sha256-UjPlIIjmKS8BopU2qB54iGLeM5DuLeu6dzMF92wK5jY=` | `sha256:0dp619ngf19kfyxfnbgfj0rxwql8g0gahdlml80jyag6i0hfacsj` | 11,136 bytes |
| Persistent guarded switch | `2026-09-05T15:07:51Z` | `/nix/store/b0j7shxdp46vpx0c3mdms2h7xsn3ixxn-container-test-dgx-desktop-switch-lifecycle.drv` | `/nix/store/1j73dimx6ayy774ikxr1az47l6a0igz3-container-test-dgx-desktop-switch-lifecycle` | `sha256-PbEl/QqN6RMz5EocY7/Pc6IYo6yJsloFVf8FOc4f+xI=` | `sha256:04pv3z73j1gzal2mmcl9mjiii8kkryzn672awhri7scd1byjbc9x` | 9,400 bytes |

## Proved Dashboard boundary

- The factory-owned `dgx-dashboard.service` GUI is active with factory GNOME
  and inactive in headless mode.
- The headless target conflicts with that GUI so its existing
  `default.target.wants` link cannot start it during a cold headless boot.
- The named GNOME target non-fatally wants the existing GUI so a direct
  same-boot GNOME isolate starts it without depending on the default-target
  link.
- Nix does not replace, mask, package, or otherwise take ownership of the
  factory Dashboard unit.
- `dgx-dashboard-admin.service`, Docker, NVIDIA persistence, and Nix-managed
  Tailscale remain mode-independent; Tailscale process and identity continuity
  are asserted throughout the applicable lifecycles.

## Authority boundary

This PASS supersedes the earlier desktop container records as current live
retry authority and makes `scripts/dgx-desktop` eligible for a separately
authorized guarded retry from factory GNOME to headless mode. It does not
itself activate generation five, stop GDM or Dashboard, terminate a graphical
session, switch the live host, authorize a reboot, remove a generation, or
remove a retained root. A host transition must still use only the guarded
operator, which installs persistent ten-minute generation-four/factory-GNOME
rollback before mutation.
