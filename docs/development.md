# Development

The Nix development shell supplies the same tools locally and in CI. It adds
nothing to your permanent package profile and does not configure the host.
Use an ARM64 Linux machine with Nix and Git installed.

```bash
./scripts/dev shell         # Interactive development environment
./scripts/dev lint          # Fast repository checks
./scripts/dev check         # Lint, small tests, and Nix evaluation
./scripts/dev hooks         # Install the repository's pre-commit hook
./scripts/dev unhook        # Remove that hook
```

The hook works outside the development shell too. It invokes the same pinned
workspace, checks staged changes through pre-commit, and blocks a failing
commit. Existing hooks and custom hook directories are left alone.

## Tools and formatting

| Files | Tools |
| --- | --- |
| Shell | ShellCheck and shfmt |
| Python | Ruff lint and format; Python 3.12 syntax compatibility |
| Nix | nixfmt and `nix flake check --no-build` |
| GitHub Actions | Actionlint |
| Documentation | Local links, shell/JSON examples, SVG, and writing checks |
| JSON and shell scripts | Parsing and syntax checks |

Format specific files, then inspect the diff:

```bash
./scripts/dev format dev/quality.py scripts/dev dev/tools.nix
./scripts/dev check
```

No Prettier. The existing Nix shell is the workspace; a Devbox manifest would
duplicate its pins. Betterer can be added when we have a broader set of quality
metrics to track; it is not needed for this initial lint gate.

Hyprland's version metadata is read from the locked input, not its filtered
build source. This lets a fresh runner evaluate it without a previous build.

Some older recovery files have formatting or ShellCheck findings.
[`dev/legacy-checks.json`](../dev/legacy-checks.json) records exceptions against
their exact SHA-256 hashes. Unchanged files keep their tested contents; editing
one invalidates its exception. Fix its findings and remove the entry in the same
PR. New files get no exceptions. Syntax and documentation checks always run.

## Pull requests and CI

Use a Conventional Commit PR title:

```text
fix: preserve SSH during a desktop switch
feat(desktop): add a GNOME return command
docs: simplify setup instructions
feat!: change the host declaration format
```

PRs are squash-merged, using their title as the commit title. Local intermediate
commit messages can be whatever helps you work.

`main` requires an up-to-date passing **CI gate** and resolved review threads.
PRs are required, but reviewer approval is not: a solo maintainer can merge
their own work. Force pushes and branch deletion are blocked, including for
admins. The configuration is in
[`.github/branch-protection.json`](../.github/branch-protection.json).

CI runs on GitHub-hosted ARM64 Ubuntu runners. It runs `./scripts/dev check`,
not DGX provisioning, host activation, or the root container lifecycle suite.
For changes to host behavior, also run the relevant
[lifecycle tests](operations.md#validation) on a suitable development machine.

Actions are pinned to full commit hashes. Dependabot groups their weekly
updates into a PR; it does not merge them automatically.

## Releases

[Release Please](https://github.com/googleapis/release-please) maintains a release
PR from changes merged into `main`. The PR updates `version.txt`, the version
manifest, and [`CHANGELOG.md`](../CHANGELOG.md).

- `fix:` produces a patch bump.
- `feat:` produces a minor bump.
- `!` marks a breaking change. Before 1.0 it bumps the minor version; from
  1.0 onward it bumps the major version.
- Documentation, tests, and maintenance alone do not cut a new release.

Merge the release PR when you want to ship. After CI passes on `main`, the
automation creates the `vX.Y.Z` tag and GitHub release with its generated notes.
No separate changelog editing, version command, or manual tag is needed.
The initial version is `0.0.0`; the first feature release becomes `0.1.0`.
Release tags cannot be moved or deleted; ship a new version for corrections.

The workflow uses GitHub's repository token, not a personal access token.
Because bot-created PRs do not trigger normal PR workflows, it explicitly
dispatches CI for the release branch. That run verifies the PR's commit and
title and executes the real checks. Publishing runs only after main's checks,
never from a PR checkout.

If a release job fails, rerun the failed job in Actions. To retry release PR
preparation, dispatch **CI** on `main`; it checks main before running the bot.
Release PRs still need a human merge. Releases do not deploy to a DGX.

## Updating development tools

```bash
nix flake update nixpkgs-devtools
./scripts/dev check
```

The development input is separate from the installed package and root-manager
inputs. [`dev/sources.json`](../dev/sources.json) also pins pre-commit and Ruff
because their latest releases were ahead of Nixpkgs when this shell was set up.
Update each version, official download URL, and published SHA-256 together.
Remove its adapter in [`dev/tools.nix`](../dev/tools.nix) when the stock package
catches up. Never copy the previous version's hash to a new version.

Upstream breadcrumbs: [pre-commit releases](https://github.com/pre-commit/pre-commit/releases),
[PyPI artifacts](https://pypi.org/pypi/pre-commit/json),
[Ruff releases](https://github.com/astral-sh/ruff/releases).
