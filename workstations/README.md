# Factory GNOME workstation setup

This branch adds a separate workstation package lifecycle for
`deadspark@spark-9667`. The NVIDIA OS, GPU stack, desktop, SSH, Docker, and
existing APT terminal packages keep their existing ownership.

## Scope

The pinned Home Manager configuration supplies the package environment. This
operator activates only that package output through an isolated Nix profile at
`~/.local/state/sparkwerx/profile`. It does **not** execute Home Manager's
file/service activation script or alter the normal `~/.nix-profile`. Dotfile
ownership remains with the existing terminal setup; the two reference files
under `terminal/` document the initial selection, not a new deployment.

The initial packages are the existing Sparkwerx fleet base (`ncdu`,
`lazydocker`, `devbox`) plus `nh`, `nix-output-monitor`, `nix-search-tv`, `fzf`,
and the `spark` management launcher. Dependencies come from the committed
lock file. Workstation package updates have a separate `nixpkgs-workstation`
input; they do not update the root or pilot package pins.

The workstation bootstrap still reads `fleet/hosts.json`. Its
`armen` logical key is used only as a compatibility mapping to `deadspark`;
all personal overlay and Codex flags are false. The actual workstation profile
is defined separately in `workstations/hosts.json`. Neither the existing
headless `converge` nor the pilot-specific Home activation operator applies to
this workstation. The initial installer retains its receipt, snapshots,
checksums, factory-service checks, and timed rollback. The
[workstation bootstrap inputs](bootstrap/README.md) independently pin installer
2.35.2. The original pilot pin remains separate. The workstation accepts healthy
Tailscale with its optional SSH feature off, as declared, and requires exact
connection/service continuity. It does not alter Tailscale settings.

## Setup

The checkout must be at `~/Development/DGX-setup` for the installed launcher.
For access before Nix installation, `~/.local/bin/spark` can symlink to
`~/Development/DGX-setup/scripts/dgx-workstation`; the existing Zsh setup puts
that directory on PATH. The script resolves this link back to the checkout.
Do not copy the script away from the repository: it needs the accompanying
host declaration and flake. After an update, quit and reopen any running menu.
Run the commands on the declared Spark, as `deadspark`, without prefixing the
whole command with sudo. Bootstrap requests sudo internally.

```bash
spark status
spark setup
exec zsh
spark
```

Setup performs bootstrap, candidate build, package activation, and shell
integration in order. It stops on failure. The menu provides the same action
as "Finish setup". Preview displays configuration edits; no edits does not
mean the declared packages are installed. For individual steps instead:

```bash
./scripts/dgx-workstation bootstrap
exec zsh
./scripts/dgx-workstation build
./scripts/dgx-workstation plan
```

After reviewing and saving the configuration, activate and add the
conditional package PATH entry to the existing Zsh local overrides file:

```bash
./scripts/dgx-workstation save
./scripts/dgx-workstation apply
./scripts/dgx-workstation shell
exec zsh
spark
```

The terminal menu uses arrow keys or j/k, Enter, and Esc/q to go back. Its
primary flow is **Find & install packages**: enter a query, filter the results,
use Tab to select multiple packages, then Enter to build them. After the build,
review the exact direct-package versions and confirm activation. Esc cancels
the picker; declining the review restores the flow's configuration edits.
Build output stays visible. Search filters catalog results for ARM64 support.
Kitty and Ghostty SSH sessions use the existing Ubuntu/user terminfo databases,
including when the launcher runs through Nix Python.

The same guided flows are available directly:

```bash
spark install btop
spark uninstall
spark upgrade
spark finish
```

`install` opens the picker rather than installing blindly. `uninstall` lists
selected extras; the guided picker keeps the fleet base and its own nh/fzf
tools. `upgrade` refreshes only the workstation package pin, then builds and
offers a review before activation. The guided flows require a clean checkout,
hold the profile lock throughout, and save accepted changes as a local Git
commit before switching packages. Cancellation or build failure restores only
their own edits; intervening user edits are preserved. A failed activation
keeps the saved selection for diagnosis/retry and uses the profile's existing
automatic recovery. A hard process kill may leave configuration edits for
review under Advanced; it never authorizes an automatic retry.

**Generations & rollback** offers a searchable history. It restores packages;
it does not rewrite the saved package selection or pin. **Advanced** retains
the individual selection, preview, build, save, apply, setup, and recovery
commands. Those manual selection/pin actions only edit the working tree until
you build, save, and activate them. `spark --help` lists all CLI actions.
Configuration commits use a local `sparkwerx@localhost` author and never push.

The owner's workload utility `vllm_stop` is also available globally from this
profile. It stops local vLLM Docker containers and unloads their processes
while retaining model files and caches. See the
[workload controls](../workloads/huihui-qwen38/README.md#stop-restart-and-retained-state).
This helper is separate from the three-package fleet base.

The newer branch candidate also supplies `gpustack-spark` for the optional
[private model-manager trial](../workloads/gpustack/README.md) and teaches
`vllm_stop` to stop managed deployments before standalone containers. Updating
the checkout alone does not activate those new helpers or start services.
See the [maintainer handoff](REVIEW.md) for the observed deployment state and
remaining limits, including the unresolved NVIDIA nvtop dependency rejection.

If a manual edit or interrupted selection leaves pending changes, choose
**Review & apply pending changes**, or run `spark finish`. It builds the current
selection, shows the configuration and actual package differences, asks once,
saves locally, then activates the exact reviewed build. Cancellation and build
failure preserve edits that existed before this flow. It also handles a saved
selection whose activation was interrupted; an armed recovery journal must
first be resolved through `spark recover`.

Preview compares the last manual candidate with the current Nix output and
labels an outdated candidate **STALE**. It never presents an old build as the
new selection. Unrelated repository changes are listed by path and must be
reviewed and committed separately; the package manager never silently includes
application files in a package commit. Search checks this before opening the
picker. `spark setup` checks before bootstrap too: an existing installation
with pending edits needs `spark finish`, not another bootstrap attempt.

Before setup completes, the menu puts Finish setup first. Search reports an
exact command already available on this machine; catalog search requires
`nh`. Missing Nix tools report setup guidance instead of a missing-file error.

`nh` provides package search and build inspection. Catalog search uses the
workstation's selected stable channel; the committed lock file determines
the actual build version, which may lag the live catalog. `nix-search-tv` provides
search data for fzf/Television. Use the Sparkwerx operator to activate or roll
back this profile: an unrelated `nh home switch` would use a different profile
and activation contract. There is no generation-deletion or garbage-collection
action in the menu.

## Recovery

```bash
spark generations
spark rollback 1
```

The number is an example: select an actual retained generation from the list.
Activation checks the candidate's host/account manifest, serializes operations,
and writes a recovery journal before changing the profile. The profile switch
uses Nix's atomic generation selection. If command checks fail, the prior
profile is restored immediately. If the process is forcibly killed, the
journal survives; after reconnecting run:

```bash
./scripts/dgx-workstation recover
```

To deactivate all packages from this isolated profile while keeping recovery
history:

```bash
spark disable
```

Use the checkout's script to restore a generation after disabling its launcher.
Disabling removes only the active profile symlink; previous generation roots
remain. The conditional Zsh hook becomes inactive. Its original file is backed
up before the first edit, and unrelated overrides are preserved.

These package generations are not an OS snapshot or an application-data backup.
The Nix installer has its own receipt-based recovery; do not treat package
rollback as uninstalling Nix. No OS reinstall or factory reset is part of this
workstation lifecycle.

## Checks

```bash
python3 -m unittest discover -s dev -p 'test_workstation*.py'
python3 scripts/check-docs.py
```

The failure tests cover first-install rollback, update rollback, interrupted
operation recovery, concurrent operations, symlink refusal, shell-file
preservation, and wrong-host refusal. See [validation](VALIDATION.md) for real
Nix-profile lifecycle results and the current host installation hold.

Existing tool references:
[nh](https://github.com/nix-community/nh),
[nix-search-tv](https://github.com/3timeslazy/nix-search-tv),
[Nixmate](https://github.com/daskladas/nixmate).
Nixmate's NixOS rebuild workflow is not the workstation's Ubuntu lifecycle.
