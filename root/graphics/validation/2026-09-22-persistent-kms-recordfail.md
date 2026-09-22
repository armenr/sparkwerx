# Persistent KMS: failed-boot menu timeout

Date: 2026-09-22

## Cause and host result

The corrected filename got past the first menu-order failure. The next enable
attempt reported successful retention of the old recovery material, then:

```text
PASS|recovery|exact pre-transaction boot configuration restored
FAIL|kms_persistent|fallback menu timeout missing or outside 5-30 seconds
```

The factory `/etc/default/grub.d/no-grubmenu.cfg` also sets
`GRUB_RECORDFAIL_TIMEOUT=0`. The previous override changed only
`GRUB_TIMEOUT_STYLE` and `GRUB_TIMEOUT`. The installed Ubuntu `00_header`
generator uses the separate recordfail value in its failed-boot branch;
`grub-mkconfig` exports that setting to the generator. A zero timeout skips
the menu, as described in the [GRUB manual](https://www.gnu.org/software/grub/manual/grub/html_node/timeout.html).
Rejecting this configuration was correct. The earlier factory-order fixture
omitted the recordfail setting and therefore missed the problem.

The operator reported recovery before returning failure. Unprivileged checks
found the corrected-at-that-time executable retained at
`/nix/store/d493yyvp92209gyh9xk5a5zi91sn7kbp-dgx-kms-persistent`, with the first
attempt's code retained separately. The private journal and boot bytes still
require sudo; the new retry verifies them before any archive or boot change.

## Correction and retry

The optional Nix drop-in now sets `GRUB_RECORDFAIL_TIMEOUT=30`. Ordinary boot
keeps the selected five-second menu. No factory file is edited and the strict
5–30-second generated-menu check is unchanged.

Retry recognizes only the two known failed bundles/configurations. It still
requires a private checksum-valid recovered initial transaction, no published
candidate, unchanged factory inputs, exact restored GRUB, absent managed
links, and current host/EFI/access preflight. Active, interrupted, unknown,
stale, or foreign state is refused.

This second attempt is archived at
`/var/lib/dgx-setup/kms-persistent-before-recordfail-fix`; its executable is
retained at `/nix/var/nix/gcroots/dgx-setup-kms-persistent-before-recordfail-fix`.
The first attempt's `before-menu-fix` archive/root remains untouched. Both
retry paths resume safely if interrupted after retention, archiving, or code
selection. Store IDs in the recovery table are exact transaction identities,
not dependency pins or a general package-upgrade mechanism.

## Validation

The updated factory-order regression first failed against the previous actual
Nix configuration: it observed `menu`, `5`, **`0`**, instead of `menu`, `5`,
**`30`**. The corrected tests cover the complete factory timeout settings,
Ubuntu's separate timeout branches, native GRUB syntax, unchanged strict
rejection, and both retry histories including interruption and collision cases.

Both enabled and disabled Nix policy builds passed all 51 tests. The full
`./scripts/dev check` passed 250 tests with six expected skips, lint, and flake
evaluation. Documentation checks passed for 123 documents and 648 local links.
An additional read-only check ran the installed Ubuntu `make_timeout` function
with the corrected Nix drop-in: it generated timeout values `30`, `5`, and `5`
and passed the host's `grub-script-check`. This exercised the real timeout
generator only, not privileged full boot generation or activation.

Corrected operator:
`/nix/store/d3jx2shywafyzyq5prcwjnkdh7vdhcg5-dgx-kms-persistent`.

Passed enabled policy derivation:
`/nix/store/1a5yfbv68jyc8v6ihh7ww46il2ccynr0-dgx-kms-persistent-policy.drv`.

Passed disabled policy derivation:
`/nix/store/al5yhwiv79f8zd7nj17jbw1ywdrzlhzx-dgx-kms-persistent-policy.drv`.

Successful corrected host activation, a physical fallback boot, and an ordinary
KMS-enabled reboot remain unverified. Work here was limited to repository edits,
builds, and unprivileged checks. No host activation, boot-file write, recovery-root
change, explicit service operation, driver/module operation, desktop switch, or
reboot was performed.

With independent local recovery available, use the existing operator:

```bash
./scripts/dgx-kms-persistent enable --console-ready
```

It runs fresh checks itself. Do not remove retained state manually or reboot
after a failed check.
