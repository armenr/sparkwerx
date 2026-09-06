# Set up a Spark

[Documentation](README.md) · [Configuration](configuration.md) · [Operations](operations.md)

This is the supported initial-setup route, not a replay of the pilot's
development history. Read [status](status.md) first: the complete workflow
currently produces a headless host with the tested Home package set.

## Before you start

You need:

- A factory DGX Spark running its supported ARM64 Ubuntu/DGX OS with systemd.
  Complete NVIDIA/DGX Dashboard updates first.
- The intended local account, with UID 1000 and its normal `/home/<user>` home.
  The current Home operator requires UID 1000; it does not create accounts.
- GitHub access to this private repository, plus Git, Bash, Python 3, curl,
  sudo, systemd tools, and `nvidia-smi`. The root operator also uses `jq`.
  A missing prerequisite is a setup issue to resolve explicitly, not a reason
  to let an unrelated installer replace the factory stack.
- A working physical console or another recovery route independent of Tailscale.
  Switching access or stopping the desktop can disconnect the current terminal.
- Enough time to complete the displayed ten-minute root rollback windows,
  including one separately initiated reboot.

An exact existing Nix installation can be adopted. A different or partial
installation is not silently overwritten. Don't run Devbox's Nix installer or
a generic Nix installer as a shortcut.

## 1. Clone

For a new checkout only:

```bash
mkdir -p ~/Development
git clone https://github.com/armenr/sparkwerx.git ~/Development/DGX-setup
cd ~/Development/DGX-setup
```

Authenticate to GitHub before cloning; do not put a token in the URL. On the
existing pilot, use its existing checkout. Do not move it: private recovery
records refer to its path.

## 2. Declare the host

Use `hostname -s` and `id` to identify the actual local host and user. Add a
new entry to [`fleet/hosts.json`](../fleet/hosts.json), following
[the configuration guide](configuration.md).

Do not rename or overwrite `sparkle-01`'s entry. Keep the current supported
headless/controller selections, decide whether this host needs Tailscale, and
leave workloads disabled.

Review and commit the declaration before applying it:

```bash
git diff -- fleet/hosts.json
git add -- fleet/hosts.json
git commit -m "declare new Spark host"
```

The operator requires a clean committed tree so a transition uses one exact
configuration. Don't use `git add -A` to sweep unrelated changes into it.

## 3. Inspect the plan

Run on the declared host, as the declared user:

```bash
./scripts/dgx-setup plan
```

Review the selected roles and [software manifest](software-manifest.md).
`PLAN_STATUS=READY` is not an instruction to install; `HOLD` lines deserve
attention even when the command exits successfully.

Planning does not change a profile or service, but Nix evaluation may fetch
missing locked sources. Planning another host by name from this machine gives
declaration-only information, not remote execution or a remote health check.

## 4. Converge

When the installation scope is approved:

```bash
./scripts/dgx-setup converge
```

Do not prefix the whole command with sudo. It elevates the root phases itself
and runs Home as the declared user.

Use the same command to resume. It installs/adopts Nix, launches the factory
root phase, verifies its reboot, transitions to headless, then activates Home.
The [lifecycle contract](fresh-host-convergence.md) explains exactly what each
phase owns.

| Output | Your next action |
| --- | --- |
| `FACTORY_TRANSITION_LAUNCHED` or `HEADLESS_TRANSITION_LAUNCHED` | Let the worker finish; reconnect if needed and rerun `converge` |
| `APPLYING` or `ARMED_WAITING_FOR_WORKER` | Wait briefly, then rerun; don't start a second low-level transaction |
| `AWAITING_TAILSCALE_LOGIN` | Use the exact enrollment command printed by the operator; keep credentials out of chat and Git |
| `AWAITING_REBOOT` | Verify recovery access, perform the separate reboot, reconnect, and rerun before the displayed deadline |
| `ROLLED_BACK_CLEAN` | Read the reported snapshot/failure before retrying |
| `COMPLETE` | Setup has verified the declared Nix, root, access, desktop, and Home state |

Only at the explicit reboot checkpoint, after deciding to reboot:

```bash
sudo systemctl reboot
```

The setup command never executes that reboot for you. A disconnected terminal
does not stop a detached worker or its rollback timer. If you're unsure what
happened, use status—not manual timer deletion.

## 5. Verify and carry on

```bash
./scripts/dgx-setup plan
./scripts/dgx-home status
./scripts/dgx-fleet-bootstrap status
```

The last command is for hosts using the generic fresh-host lifecycle. On
historical `sparkle-01`, use the pilot-specific status routes in
[operations](operations.md#status-checks).

Re-running `converge` after completion is designed to verify and make no changes
when the declaration and live state still match. It remains a mutating command
when there is supported work to apply; don't use it as a casual status probe.
