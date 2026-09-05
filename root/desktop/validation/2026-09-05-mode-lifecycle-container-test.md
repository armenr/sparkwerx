# Desktop-mode lifecycle container test — 2026-09-05

## Result

**PASS** for the exact committed headless/factory-GNOME controller design.

The root-assisted wrapper first proved that `sparkle-01` remained on exact
System Manager generation four with factory GNOME, Nix-managed Tailscale, no
desktop-controller paths, no failed units, and unchanged protected services.
All target isolation and reboot operations then ran only inside the disposable
Ubuntu container. The wrapper repeated the exact live-host boundary after the
build and reported:

```text
PASS|desktop_mode_lifecycle|headless/GNOME persistence, access continuity, reversibility, and factory fallback passed; live host stayed exact
```

## Exact artifacts

| Field | Value |
| --- | --- |
| Repository commit | `e80dec6979663dcffd80834294dd0405e744e3f9` |
| Registered at | `2026-09-05T11:23:31Z` |
| Test derivation | `/nix/store/qv3v6lglnqigqa60qs3zg4x5qkcy6hsw-container-test-dgx-desktop-mode-lifecycle.drv` |
| Output | `/nix/store/58ca2p4a20hfsvy5is4dzk0g5zs60rqg-container-test-dgx-desktop-mode-lifecycle` |
| Output SRI hash | `sha256-+/qYifYr8D2anu1gDOqkx43Cb9oaa461uR+45rX4PoE=` |
| Output Nix-base32 hash | `sha256:109yz2sydf0zp6sqwsqsv9pw53f7lkm0qq7dksd3vw1bys4riypv` |
| Headless host candidate | `/nix/store/20qw0af0jwfqi5spgg3b1nrc0yydhlc1-system-manager` |
| GNOME host candidate | `/nix/store/rri20h082q9qkcvwdg1zarp7i46nscy2-system-manager` |
| Live/rollback generation four | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |

## Proved lifecycle

All ten named subtests completed:

1. install a factory-GDM fixture and exact generation four;
2. declare headless without changing the live runtime target;
3. isolate headless while preserving Nix-managed Tailscale;
4. reboot into persistent headless mode;
5. declare GNOME without prematurely starting graphics;
6. isolate GNOME and start only the factory graphical stack;
7. reboot into persistent factory GNOME;
8. return from GNOME to headless;
9. remove the controller and restore the factory GNOME default; and
10. reboot once more with factory fallback and managed access intact.

This is three disposable container reboots. System Manager activation changed
only persistent declaration; explicit target isolation performed each runtime
transition. Both candidates retained generation four's exact four-entry
active-service map and empty global package set. The mode targets existed only
as immutable unit files.

## Failed-feedback history

Three earlier disposable attempts failed closed and changed nothing on the
host. They established, in order, that a Nix-store-linked `default.target`
reports its lookup name, that a direct immutable alias does not activate the
named target, and that putting inactive mode targets in System Manager's
active-service map produces a non-fatal stop error during controller removal.
The final design uses a tiny dispatcher and keeps mode targets outside that
active-service map.

The top-level Nix 2.35.2 warning about `auto-allocate-uids` is the already
documented cosmetic direct-store warning. The hash-valid output and completed
container lifecycle determine the verdict.

## Authority boundary

This PASS authorizes repository design and testing of a guarded live switch.
It does not authorize registration or activation of either candidate,
`systemctl isolate` on the host, GUI-session termination, a reboot, generation
cleanup, or removal of any retained root.
