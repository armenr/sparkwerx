# Fresh-host Nix bootstrap lifecycle — 2026-09-03

## Result

**PASS.** The exact clean-host Nix bootstrap completed its five-stage lifecycle
inside a disposable Ubuntu 24.04 `systemd-nspawn` container on
`aarch64-linux`.

The test proved the repository operator can recover from a failure after the
runtime upgrade, return to the exact clean boundary, perform a successful
fresh install, and classify a second invocation as a zero-mutation adoption.
It did not install, uninstall, or reconfigure Nix on `sparkle-01`; host effects
were limited to Nix-store/build bookkeeping for the disposable test.

## Exact evidence

| Field | Value |
| --- | --- |
| Verified at | `2026-09-03T18:21:54Z` |
| Platform | `aarch64-linux` |
| Container rootfs | Ubuntu 24.04 |
| Installer | Official `NixOS/nix-installer` 2.35.1 ARM64 Linux |
| Installer SHA-256 | `7e6e2f753144d7f19b16a9fce4b354cb0f46d1d47e6908bfb9186c89e0e0e649` |
| Desired runtime | Nix 2.35.2 at `/nix/store/fw98swa1g4ysvmv6p6m6xf51kzhvpp6p-nix-2.35.2` |
| Bootstrap script SHA-256 | `6d3f601789683b8472b536a04757768366fb12982c41c71de4f691fe8513797a` |
| Rollback script SHA-256 | `a3aaa8cdc760f7ae675ba9489406f85a628b8bee412463b9df1e8fe478449790` |
| Test wrapper SHA-256 | `bd235b2b07bab0db7904cbb5b499d4f4ec91b40610368f1658cc63840b16a1f6` |
| Derivation | `/nix/store/81pb42kcc2i4h6kasdkg7b26b599vqws-container-test-dgx-nix-bootstrap-lifecycle.drv` |
| Output | `/nix/store/3zkfhmnvd0nc0hnc84j37b1fffnr953d-container-test-dgx-nix-bootstrap-lifecycle` |
| Output NAR size | 7,104 bytes |
| Output Nix hash | `sha256:0zvnf2ppjfjlnav7xkr7npfs08m0fdi6bf8g8kwlgd69s4brh864` |
| Output SRI hash | `sha256-xCCYF9HJtEf5RA+5ZWJzoCKg3bUnz362slQ6ea9wdn8=` |
| Output deriver | Exact derivation above |
| Exit status | `0` |

Operator command:

```console
sudo ./scripts/test-nix-bootstrap-lifecycle.sh
```

The dirty-tree warning was expected because the implementation was being
validated before its milestone commit. The derivation records the exact input
files and hashes above. The non-fatal top-level `auto-allocate-uids` warning is
the already documented Nix 2.35 direct-store behavior; the root-only build
explicitly enabled both `auto-allocate-uids` and `cgroups`, and the container
test completed.

## Passed lifecycle

The daemon log records all five subtests as complete:

1. A committed declared-host fixture was prepared outside the Nix store with
   the exact bootstrap declaration, operator, rollback helper, runtime path,
   and a factory-style GPU probe.
2. The test driver's own Nix installation was removed to establish an exact
   clean-host boundary.
3. An injected failure after upgrading to Nix 2.35.2 left the already-armed
   rollback in control. The test invoked the timer's exact service immediately,
   rather than waiting 15 minutes, and the retained official installer used its
   receipt to uninstall. Installer-created root profile, expression, state, and
   cache residuals were moved into private rollback evidence rather than
   deleted. `/nix`, `/etc/nix`, the build group/users, and all declared root
   Nix paths were absent afterward.
4. A clean retry installed from the reviewed official Linux/systemd plan,
   enabled persistent `nix-command` and `flakes`, advanced the default profile
   to exact Nix 2.35.2, passed systemd/GPU/access continuity checks, and
   disarmed its rollback only after postflight.
5. A second invocation through `scripts/dgx-setup bootstrap` returned
   `BOOTSTRAP_STATUS=ADOPTED`; installer, receipt, Nix configuration, and the
   default-profile target remained byte-for-byte unchanged.

The container intentionally had no external network. Its test-only file cache
contained the exact already pinned 2.35.2 store path. Production bootstrap
continues to use the repository's reviewed runtime path and normal signed
upstream cache policy; the unsigned local cache exception exists only inside
this isolated test.

## Issues exposed and closed

The disposable lifecycle did its job and found several test or rollback gaps
without changing the host:

- generated-test Python lint rejected a stray f-string;
- the copied fixture needed writable ownership before its local Git commit;
- the network-isolated container needed an exact local cache for runtime
  2.35.2;
- the official receipt uninstall left root `nix-env` compatibility paths, so
  rollback now preserves those pre-state-absent residuals in private evidence
  and verifies the clean boundary; and
- the final feature assertion incorrectly assumed one textual `nix.conf`
  serialization and now checks Nix's parsed effective setting instead.

Every corrected path was included in the final exact derivation above.

## Independent host postflight

After the PASS, read-only host inspection returned:

```text
ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED
BOOTSTRAP_TRANSIENT_UNITS=0
SYSTEM_STATE=running
FAILED_UNITS=0
NIX_CLIENT=nix (Nix) 2.35.2
NIX_STORE=2.35.2
```

The live System Manager generation, all three registered generations and
direct roots, its one boot edge, factory services, Tailscale ownership, and
desktop mode were not changed.

## Operational boundary

This PASS closes the clean-host Nix bootstrap test gate. On a newly
factory-updated, declared ARM64 DGX, the supported Nix-only operation is now:

```bash
./scripts/dgx-setup plan <hostname>
./scripts/dgx-setup bootstrap <hostname>
```

The bootstrap command still requires a clean committed repository, a matching
host declaration, the current verified installer pin, local `sudo`, and all of
its own preflight checks. Operators must not invoke the installer binary
directly.

This evidence authorizes no unified configuration apply, Home activation,
Tailscale enrollment or migration, desktop transition, workload deployment,
service restart outside the bootstrap's own Nix daemon handling, or reboot.
Those remain independent milestones.
