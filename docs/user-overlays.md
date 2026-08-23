# User overlays

A user overlay is a named, opt-in layer above the fleet base, host desktop
mode, and shared graphical role. It exists so personal tools never become fleet
defaults.

Ghostty is shared by every graphical mode and therefore does not belong in
Armen's overlay. It is inactive in headless mode.

## Armen overlay

Logical name: `armen`

Pilot mapping:

`armen -> n0b0dy@sparkle-01`

The mapping and graphical/headless activity gate are implemented. The host
declares the overlay selected, but the module intentionally contains zero
application packages until each item completes its own manifest and closure
review. In the staged headless profile, the selection persists in Git while
its computed graphical activity is false.

Every future mapping must be explicit in that host's configuration. Creating
another Unix user must not give that user Armen's applications, browser
extensions, settings, accounts, or secrets.

## Selected graphical components

| Component | Intended ownership | Important boundary |
| --- | --- | --- |
| Chromium | Nix package in Armen's graphical overlay | Chromium, not Google Chrome; no autostart |
| 1Password extension for Chromium | Declarative browser-extension submodule after pin/update review | Vault data, login state, and account secrets remain mutable and external |
| 1Password extension for Firefox | Declarative browser-extension submodule after pin/update review | Firefox is currently factory/manual context; do not replace its profile |
| Zed | Current pinned ARM64 Nix package or reviewed derivation | Needs Vulkan and desktop integration tests; settings may be declarative, credentials are not |
| LM Studio desktop | Current pinned ARM64 package with one exact unfree exception | Model files and application state stay outside Nix; no server exposure by default |
| ChatGPT desktop | Reviewed pinned package derived from an official artifact if feasible | Existing Debian package is migration input; credentials and session state stay outside Nix |

The graphical overlay is inactive in `headless` mode. Its selection persists in
Git so returning to a graphical mode restores the intended package graph, but
headless activation must not launch or autostart these applications.

## Separate decisions that must stay separate

- The LM Studio desktop application does not imply the headless `llmster`
  daemon, LM Link, an API listener, or any model download.
- Zed does not imply VS Code, an AI-provider subscription, or stored API keys.
- The two 1Password browser extensions do not imply the 1Password desktop app.
- Chromium does not imply Google Chrome.
- Ghostty is shared graphical infrastructure, not a personal application.
- ChatGPT desktop does not imply Codex CLI ownership.
- Isaac Sim/Lab and Omniverse are a host workload role, not part of this
  overlay.

## Mutable state and secrets

Nix may manage application packages, launchers, non-secret preferences, and
carefully reviewed extension policy. It must not put any of these in the Nix
store or Git:

- browser profiles, cookies, history, sync data, or extension account state;
- 1Password vault data, credentials, device keys, or recovery material;
- ChatGPT, Zed, or LM Studio authentication tokens;
- model weights, model caches, chat history, project indexes, or generated
  output;
- per-machine GPU shader caches and crash logs.

Existing mutable profiles are migration inputs. Before Home Manager owns a path,
inspect it for collisions and back it up; never replace it merely because the
package definition evaluates.

## Packaging sequence

For each selected component:

1. recheck the official release and ARM64 support;
2. choose an immutable source and record it in the software manifest;
3. add the package behind `dgx.userOverlays.armen.graphical.enable`;
4. add only the exact unfree exception, if one is required;
5. evaluate and inspect its closure;
6. build without installation only after approval;
7. validate under factory GNOME first, then Hyprland;
8. authorize activation separately and preserve the previous profile.

Browser extensions need an additional decision: whether to pin exact artifacts
or declare an update channel. Either can be reproducible only if the update and
rollback semantics are written down.
