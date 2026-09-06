# Fresh-host convergence

[Getting started](getting-started.md) · [Configuration](configuration.md) ·
[Status](status.md)

## Status

**Validated for newly declared ARM64 DGX Spark hosts.** The complete
clone-and-converge implementation passed its clean-commit, root-assisted
disposable lifecycle and retained-host no-op regression on 2026-09-06 at
`cc1069cbce87974a545095b3361b78837d618437`. See the
[exact integration record](2026-09-06-fresh-host-convergence-integration.md).

That validation establishes the guarded `converge` entry point as ready for
initial setup within an approved deployment task, after factory updates,
an explicit declaration, and plan/SBOM review. It does not authorize a workload, graphical
application, Hyprland/KDE integration, cleanup of fallback material, or a raw
Nix/Home/System Manager activation. Any functional change to this lane must
pass and record the same complete gate again.

## Intended operator experience

On a factory DGX Spark:

1. Finish supported NVIDIA/DGX Dashboard updates.
2. Clone this repository at a reviewed clean commit.
3. Add the host and its explicit choices to `fleet/hosts.json`.
4. Review `./scripts/dgx-setup plan <hostname>` and the software manifest.
5. Run the same resumable command until it reports complete:

   ```bash
   ./scripts/dgx-setup converge <hostname>
   ```

The command may disconnect its own terminal while taking ownership of
Tailscale or while stopping the graphical session. Reconnect and run the same
command again. It classifies the exact retained state and advances only the
next safe phase.

The operator never reboots the machine. When it reports
`CONVERGE_STATUS=AWAITING_REBOOT`, arrange independent local recovery and run a
separate reboot yourself. Reconnect and rerun `converge` before the displayed
rollback deadline.

## What the workflow owns

The fresh-host lane is data-driven. A normal host needs only a declaration in
`fleet/hosts.json`; `modules/home/fleet-host.nix` supplies the generic Home
composition and `modules/system/fleet-host.nix` supplies a host-specific,
minimal System Manager marker.

The state sequence is:

```text
factory DGX
  -> exact Nix install or adoption
  -> System Manager generation 1: factory GNOME + optional Nix Tailscale
  -> separately initiated reboot
  -> confirmed generation 1
  -> System Manager generation 2: headless + same optional access role
  -> confirmed generation 2
  -> exact Home Manager profile
  -> complete
```

Generation 1 deliberately leaves the factory graphical stack available. It
must survive one real reboot before the workflow is allowed to enter headless
mode. Generation 2 stops GDM and the Dashboard GUI but does not uninstall the
factory desktop. Both transitions arm an exact ten-minute rollback before
mutation.

If Tailscale is selected and an existing healthy identity is present, the
first generation preserves it while moving unit ownership to Nix. If the host
is a new, unenrolled node, status reports
`FLEET_BOOTSTRAP_STATUS=AWAITING_TAILSCALE_LOGIN` and prints the exact
Nix-store `tailscale up --ssh` command. Enrollment credentials, node identity,
and tailnet policy remain mutable external state. If Tailscale is not selected,
the role and its unit are omitted and the lifecycle leaves any vendor access
surface unowned.

## Recovery and status

Within the approved setup, rerun this command to resume the next phase. It can
install or change configuration; it is not a read-only status check:

```bash
./scripts/dgx-setup converge <hostname>
```

For direct diagnosis of an in-flight root phase:

```bash
./scripts/dgx-fleet-bootstrap status
```

The guarded root operator also exposes `rollback` and
`cleanup-rolled-back`. Use those only for the exact state it reports; never
activate a generated System Manager output directly or delete its guard paths
by hand.

The fresh lane does not replay `sparkle-01`'s five historical pilot
generations. The current pilot is recognized explicitly and remains on its
proven retained-state/no-op path.

## Current boundary

This workflow converges a newly declared ARM64 Spark to the currently selected
headless base, optional Tailscale role, and user overlay. It does not yet:

- deploy an enabled workload;
- install Hyprland or KDE host integration;
- remove an apt Tailscale fallback after adopting an existing node; or
- perform a later System Manager root-generation upgrade after the initial
  two-generation deployment.

Those remain separate reviewed lifecycles. Home package updates continue
through `scripts/dgx-home update-headless`.

The complete user lifecycle currently requires the explicit Armen mapping,
UID 1000, and tested Codex/base composition. See
[current configuration limits](configuration.md#current-limits). The full
fresh-host sequence has passed in disposable environments; a second physical
DGX has not yet been provisioned with it.

## Validation gate

From a clean committed tree, run as the declared user:

```bash
./scripts/test-fresh-host-convergence-integration.sh
```

It runs Home rollback mechanics in private temporary homes, then uses root only
for disposable Ubuntu container tests of Nix installation and the complete
optional-Tailscale/factory/reboot/headless/rollback lifecycle. Its final checks
exercise the live pilot only through read-only or exact no-op entry points.
It never reboots or transitions the live host.

The gate passed from clean commit
`cc1069cbce87974a545095b3361b78837d618437` on 2026-09-06. The exact
derivations, hashes, subtests, live no-op results, and authority boundary are
recorded in
[the fresh-host convergence integration evidence](2026-09-06-fresh-host-convergence-integration.md).
