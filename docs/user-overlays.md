# User overlays

[Documentation](README.md) · [Configuration](configuration.md) ·
[Current status](status.md)

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
declares the overlay selected. Codex CLI is its first packaged all-modes tool.
Exact current Chromium, Zed, and LM Studio graphical candidates have completed
package and closure review but remain absent from every profile until their
real graphical gates pass. In the active headless generation, graphical
selection persists in Git while its computed activity is false and Codex is
present through its Nix-managed launcher.

Every future mapping must be explicit in that host's configuration. Creating
another Unix user must not give that user Armen's applications, browser
extensions, settings, accounts, or secrets.

## Selected graphical components

| Component | Intended ownership | Important boundary |
| --- | --- | --- |
| Chromium | Exact locked 152.0.7977.75 ARM64 Nixpkgs package, built candidate-only | Chromium, not Google Chrome; no autostart or MIME defaults; requires a separately reviewed root sandbox helper and must never use `--no-sandbox` for browsing |
| 1Password extension for Chromium | Declarative browser-extension submodule after pin/update review | Vault data, login state, and account secrets remain mutable and external |
| 1Password extension for Firefox | Declarative browser-extension submodule after pin/update review | Firefox is currently factory/manual context; do not replace its profile |
| Zed | Exact official stable 1.18.0 ARM64 bundle, built candidate-only | Needs factory-GNOME Vulkan/portal integration tests; self-update is disabled, settings may be declarative, credentials are not |
| LM Studio desktop | Exact official 0.4.23-1 ARM64 AppImage, built candidate-only with one exact unfree exception | Resolve the vendor Electron no-sandbox fallback before activation; model files and application state stay outside Nix; no server exposure by default |
| ChatGPT desktop | Reviewed pinned package derived from an official artifact if feasible | Existing Debian package is migration input; credentials and session state stay outside Nix |

Current package evidence:

- [Chromium 152.0.7977.75](2026-09-03-chromium-package.md)
- [Zed 1.18.0](2026-09-03-zed-package.md)
- [LM Studio 0.4.23-1](2026-09-03-lmstudio-package.md)

The graphical overlay is inactive in `headless` mode. Its selection persists in
Git, but selecting a graphical mode does not yet install these candidate apps:
their profile wiring and runtime checks remain unfinished. Headless activation
must not launch or autostart them. The intended overlay model is broader than
the currently tested user lifecycle; see
[configuration limits](configuration.md#current-limits).

## Codex permission defaults

Armen explicitly selected maximally permissive Codex defaults in every desktop
mode, including headless. The overlay reconciles only these non-secret settings
in `~/.codex/config.toml` during Home Manager activation:

```toml
approval_policy = "never"
default_permissions = ":danger-full-access"
approvals_reviewer = "auto_review"
check_for_update_on_startup = false

[notice]
hide_full_access_warning = true

[apps._default]
approvals_reviewer = "auto_review"
default_tools_approval_mode = "approve"
destructive_enabled = true
open_world_enabled = true
```

This is intentionally high trust: Codex can read and modify the whole machine,
use the network, and run commands without pausing for user approval. The narrow
reconciler preserves all unrelated mutable Codex/ChatGPT configuration,
including authentication, model selection, plugins, MCP servers, project trust,
desktop preferences, and history. It refuses a symlinked or foreign-owned
config rather than replacing it. Codex CLI package ownership remains a separate
concern from mutable state: Armen's all-modes overlay now owns the current
official ARM64 package and `~/.local/bin/codex` launcher, while login, plugins,
MCP servers, project trust, preferences, and history remain mutable. Startup
self-update is disabled because `scripts/update-codex.sh` owns release checks.
The old standalone release tree remains untouched as temporary rollback input;
the first Home activation, real rollback, and fresh reactivation are verified.

## Separate decisions that must stay separate

- The LM Studio desktop application does not imply the headless `llmster`
  daemon, LM Link, an API listener, or any model download.
- Zed does not imply VS Code, an AI-provider subscription, or stored API keys.
- The two 1Password browser extensions do not imply the 1Password desktop app.
- Chromium does not imply Google Chrome.
- Ghostty is shared graphical infrastructure, not a personal application.
- ChatGPT desktop does not own or update Codex CLI.
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
