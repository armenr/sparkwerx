# Configure your fleet

[Documentation](README.md) · [Getting started](getting-started.md)

The target experience is a shared foundation plus explicit per-host choices.
Today's implementation has a deliberately small supported combination. This
guide distinguishes a working choice from a schema field reserved for later work.

## Start with the host declaration

[`fleet/hosts.json`](../fleet/hosts.json) is the selection file. Keep its
`schemaVersion` and `hosts` object. Copy an existing host object under the new
machine's actual short hostname, then review each field.

This is the current host-object shape; it belongs inside `hosts`, not at the
top level. Replace the Unix identity only when it matches that host's account.

```json
{
  "system": "aarch64-linux",
  "pilotRing": "pilot",
  "users": {
    "armen": {
      "unixName": "n0b0dy",
      "homeDirectory": "/home/n0b0dy",
      "overlaySelected": true,
      "graphicalAppsSelected": false,
      "codexSelected": true,
      "codexRelaxedPermissions": true
    }
  },
  "fleetBase": {
    "enable": true
  },
  "access": {
    "tailscale": {
      "selected": true,
      "sshDesired": true,
      "ownership": "nix-managed"
    }
  },
  "desktop": {
    "mode": "headless",
    "hyprlandPortal": false,
    "hostController": "system-manager"
  },
  "workloads": {
    "isaacOmniverse": {
      "selected": false,
      "enabled": false
    },
    "lmstudioDaemon": {
      "selected": false,
      "enabled": false
    }
  }
}
```

The Codex permission choice above is Armen's explicitly accepted high-trust
setting: it permits full machine/network access without approval prompts.
It is not a recommendation for arbitrary users. See [user overlays](user-overlays.md).

## Choices that work today

| Field | Meaning |
| --- | --- |
| Host key | Exact local `hostname -s`; not an SSH destination for a remote deployer |
| `users.armen.unixName` / `homeDirectory` | Explicit logical-to-Unix mapping; current Home lifecycle requires UID 1000 |
| `fleetBase.enable` | Must be true; selects exactly ncdu, lazydocker, and Devbox |
| `access.tailscale.selected` | Whether Nix should own Tailscale on this host |
| `access.tailscale.ownership` | Use `nix-managed` as desired state for selected fresh-host access |
| `desktop.mode` / `hostController` | The complete converge lane requires `headless` / `system-manager` |
| `workloads.*.selected` | Records interest, not deployment |
| `workloads.*.enabled` | Must remain false for the current converge lane |
| `pilotRing` | Intent metadata, not an implemented rollout scheduler |

To omit Tailscale on a **new** host, set `selected: false`,
`sshDesired: false`, and `ownership: "disabled"` together. The Nix access
role is omitted; it does not disable an unrelated existing service or create
an alternative remote-access method. Changing these values on an already
managed host is not a supported uninstall/update transaction.

`graphicalAppsSelected` can preserve intent while headless, but no personal
graphical package is currently wired into a Home profile. Enabling the flag
does not install Chromium, Zed, LM Studio, ChatGPT, or browser extensions.

## Current limits

The implementation still requires exactly one logical user key, `armen`.
The tested Home operator also checks the Codex launcher and package set.
Turning off that overlay or Codex is not a proven end-to-end provisioning
choice, even though lower-level Nix modules expose those switches.

Likewise, these are not yet supported by a simple JSON edit:

- adding arbitrary packages to the permanent base;
- provisioning additional logical users or accounts;
- completing converge in a graphical mode;
- deploying enabled workloads;
- upgrading or removing a retained root service generation.

Supporting those choices means extending the matching modules, policy checks,
and guarded lifecycle tests—not bypassing their assertions.

## Where to add an approved package

| Scope | Definition |
| --- | --- |
| Temporary repository tooling | `devShells` in [flake.nix](../flake.nix) |
| Every managed user | [Fleet base module](../modules/home/base.nix), after changing the accepted base decision |
| Shared graphical tools | [Desktop module](../modules/home/desktop.nix) |
| Armen's personal tools | [Armen overlay](../modules/home/user-overlays/armen.nix) |
| Exact upstream package adapter | [packages](../packages) |
| Host services | [System modules](../modules/system), with a root transition and rollback |
| AI applications | A separately designed workload role; no general workload deployer exists yet |

For temporary development tools, use the project dev shell rather than adding
them to every user profile. Entering `nix develop` may download/build its tools;
it is not a read-only operation.

For a permanent addition: capture the choice, source/version, ARM64 support,
closure, services, state, and rollback in the
[software manifest](software-manifest.md); update the matching module and
checks; build/test; then activate through the reviewed operator. Keep package
readiness separate from host activation.

## Pins and hand-written adapters

[`flake.lock`](../flake.lock) records the stable, apps, Home Manager, Hyprland,
and root inputs. The root lane stays separate from routine app updates.
Some release records under [packages](../packages) pin upstream artifacts or
source/vendor hashes because the locked Nixpkgs package was older.

Those adapters are intentional, not mysteries to delete. Audit upstream and
stock Nixpkgs first; retire an adapter only when the stock package catches up
and passes the same checks. The [source map](../.agents/skills/dgx-spark-ops/references/source-map.md)
and [update guide](operations.md#updates) explain where to look.

Commit reviewed selections before applying them. Never store authentication,
Tailscale identity, browser profiles, models, or chat histories in this file.
