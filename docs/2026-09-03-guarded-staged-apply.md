# Guarded staged host apply — 2026-09-03

## Result

**PASS for the retained pilot's idempotent path.** Commit
`1e19371d9aa4e225e20291c6d925a7e345a320a8` added the first executable
`scripts/dgx-setup apply [HOSTNAME]` front door. It composes only the two
lifecycles that have already passed independently:

1. exact Nix install-or-adopt through `scripts/dgx-setup bootstrap`; and
2. exact headless Home first activation or later update through
   `scripts/dgx-home`.

It does not pretend the whole declaration is converged. On `sparkle-01`, the
apt-to-Nix Tailscale handoff and the root systemd/GDM desktop controller remain
explicit holds. A successful run therefore ends with `APPLY_STATUS=PARTIAL`
while returning success for the proven layers it did converge.

## Fail-closed boundary

Before either lifecycle can mutate state, `apply` requires:

- the declared target to be the local ARM64 host and the caller to match its
  explicit user/home mapping;
- a clean repository, binding the transaction to one commit;
- `headless` user composition, because no graphical Home activation lifecycle
  is approved yet;
- `hostController = "not-implemented"`, preventing an accidental root desktop
  transition; and
- every workload to remain disabled.

A selected Tailscale role is accepted only in the recorded
`migration-pending-apt` state. The command preserves that daemon, unit, node
identity, SSH preference, and apt ownership. Claiming `nix-managed` ownership
before its migration lifecycle exists fails before bootstrap or Home mutation.

After bootstrap, an absent Home Manager profile selects the guarded
`activate-headless` transaction. An existing symlink selects the idempotent
`update-headless` transaction. A non-symlink at the profile path is treated as
unsupported drift and refused.

## Live no-op evidence

`scripts/test-dgx-setup-apply.sh` ran on the exact retained pilot and passed:

```text
PASS|dgx_setup_apply_test|Nix and Home converged as no-ops; Tailscale, desktop, root, services, and mutable state stayed exact
```

The test captured state before and after the real operator and proved:

- the root Nix default profile did not change;
- the selected Home Manager and user profiles did not change;
- mutable `~/.codex/config.toml` bytes did not change;
- Tailscale, GDM, Docker, both DGX Dashboard services, and NVIDIA persistence
  retained their exact process, fragment, activation time, and daemon-reload
  state; and
- System Manager remained
  `ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`.

At `2026-09-03T18:52:29Z`, the retained Home generation was
`/nix/store/naw1cln02ark00v6wxss5flijlh3nr57-home-manager-generation`, the
user environment was
`/nix/store/6cdhd5n7m5agcrnr8pg6jxkpsadmfpba-user-environment`, systemd was
`running`, no failed unit was present, and the repository was clean.

Exact tested script hashes:

- `scripts/dgx-setup`:
  `6eceef67414eef86013561a497195c53a0f0229cc65bd39c0931ac78577e6f37`
- `scripts/test-dgx-setup-apply.sh`:
  `acddd237a8b4d9ad64a01bdb66872383618e37d0710b2cb1d0dd4c01ed5e408a`

## Remaining gates

This closes the pilot no-op orchestration gate, not the complete new-machine
contract. Still open are an integrated clean-host `apply` test, generic
post-deployment evidence for additional hosts, Tailscale migration and reboot
validation, the root desktop controller, graphical profiles/apps, and enabled
workloads. Rerunning `apply` is safe on the retained pilot, but
`APPLY_STATUS=PARTIAL` must not be interpreted as full desired-state
convergence.
