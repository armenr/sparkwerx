# Persistent KMS: factory menu ordering and retry

Date: 2026-09-07

## First host attempt

Armen ran `dgx-kms-persistent check`, which reported
`READY_FOR_SEPARATE_ACTIVATION`, then `enable --console-ready`. Activation
stopped with `fallback menu is not visible` before publishing the candidate
`grub.cfg`.

The installed Ubuntu `grub-mkconfig` sources `/etc/default/grub.d/*.cfg` in
shell filename order. The factory `menu.cfg` selects a five-second visible
menu, but the later `no-grubmenu.cfg` sets `GRUB_TIMEOUT=0` and
`GRUB_TIMEOUT_STYLE=hidden`. Our original `90-sparkwerx-kms.cfg` sorted before
both, so NVIDIA's file overrode it. The generated-menu verifier correctly
rejected that result; the fixture had tested our drop-in alone and missed the
factory ordering.

The failure path automatically attempts exact recovery. Subsequent unprivileged
inspection found both attempted `/etc` links absent, the private recovery
directory and original code root retained, and headless/Tailscale/Docker/NVIDIA
persistence active with GDM inactive and no pending reload. Reading the private
journal and comparing protected boot bytes still requires sudo; do not infer
that verification from file absence alone. The retry performs it before any
archive or boot change.

## Correction

- The optional drop-in is now `zz-sparkwerx-kms.cfg`, after the factory files.
  No NVIDIA file or package is edited or removed.
- The generated-menu requirement remains mandatory. Status also rejects
  hidden/zero-timeout headers, including conflicting later assignments.
- Successful automatic recovery now prints its result before the original
  failure, so the operator does not leave the outcome implicit.
- The same enable command can retry only the exact original recovered initial
  attempt: known old executable/configuration, private checksum-valid journal,
  no published candidate, absent old/new links, unchanged factory inputs, exact
  restored original GRUB, and fresh host/EFI/access preflight.
- It preserves the previous complete state at
  `/var/lib/dgx-setup/kms-persistent-before-menu-fix`, retains the old executable
  at `/nix/var/nix/gcroots/dgx-setup-kms-persistent-before-menu-fix`, and atomically
  selects the corrected code before starting a fresh transaction. There is no
  state deletion or migration of active/unknown configurations.

The old store IDs in `kms-persistent.py` describe this recovery case. They are
not floating package pins or a general upgrade mechanism. Preserve those old
roots and snapshots; future changes need their own explicit compatibility path.

## Tests

The new shell-glob regression first failed against the original Nix drop-in:
it observed `hidden` and `0`. With the corrected filename, both enabled and
disabled Nix policies passed all 37 tests, including the actual generated
drop-in, factory-order fixture, native GRUB syntax parser, and existing
generation/recovery cases.

New retry tests cover read-only preflight, exact history/code retention,
refusal of active/interrupted/unknown/stale predecessors, foreign roots and old
drop-ins, interruption after each retention/archive/selection step, and a
second failed activation followed by a successful retry.

The complete `./scripts/dev check` passed: 236 tests with six expected skips,
Python/shell/Nix checks, flake evaluation, and 122-document link/example checks.
The two configuration-dependent KMS tests skip outside the Nix environment;
both package policies supplied that environment and ran them successfully.

Corrected operator:
`/nix/store/d493yyvp92209gyh9xk5a5zi91sn7kbp-dgx-kms-persistent`.

Passed enabled policy derivation:
`/nix/store/6yp9gjv47s1d2aawpm2cp4wcgararnsn-dgx-kms-persistent-policy.drv`.

Passed disabled policy derivation:
`/nix/store/w01am0i1w45fyyr5ikcazy1c76f3mxab-dgx-kms-persistent-policy.drv`.

These tests use temporary boot trees and simulated transactions. No corrected
host activation, reboot, physical fallback boot, graphics launch, driver change,
or service operation has been performed. The old one-boot KMS operator and
System Manager generations remain untouched.

Next, with local recovery available:

```bash
./scripts/dgx-kms-persistent enable --console-ready
```

The operator verifies the recovered pre-state itself. Do not manually delete
its recovery directory or roots, and do not reboot if any check fails.
