# Guarded first-generation registration transaction — 2026-09-01

## Status

**PASS FOR THE EXACT DISPOSABLE DERIVATION. THE LIVE HOST REMAINS
`ACTIVE_RETAINED`, UNREGISTERED, AND NOT BOOT-LINKED.**

The transaction, private snapshot helper, guarded live wrapper, extended
read-only classifier, and a distinct failure-injection container test are
implemented. The separately authorized root-local test completed and its exact
hash-valid output was verified at `2026-09-01T15:04:47Z`. All nine subtests
passed and independent host postflight was clean.

No host profile, generation link, upstream extra GC root, activation,
deactivation, boot link, daemon reload, or service change occurred.

## Exact design inputs

| Field | Value |
| --- | --- |
| Host | `sparkle-01` |
| Required host pre-state | `ACTIVE_RETAINED` |
| Exact candidate | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Transaction program | `scripts/root-registration-transaction.sh` |
| Transaction SHA-256 | `86c4be22ed350782920905897d80616b3949998d2662fd04ab9d1f5c3f4078a9` |
| Test derivation | `/nix/store/lxnykcyvjn18pdv7y9rr1ryhvjgicazg-container-test-dgx-root-canary-registration-transaction.drv` |
| Test output | `/nix/store/mrslm372127pgwbfv3r7kprj2igxpki2-container-test-dgx-root-canary-registration-transaction` |
| Test output hash | `sha256:1smdvp76zf0hz5cxzjjghf8c2z4hjkvbkwf4ikmgpf2cz8fv4ram` |
| Prior lifecycle derivation | `/nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv` (unchanged) |
| Original activation derivation | `/nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv` (unchanged) |
| Repository commit at execution | `458d1e640f89a7986b1a33b6ca41741d597096da` |
| Result record | [transaction container-test evidence](2026-09-01-first-registration-transaction-container-test.md) |
| Live registration performed | No |
| Live activation performed | No |

Before execution, the no-build plan contained only the generated test script,
closure metadata, and new disposable container output. The completed build
retains only Nix test/store bookkeeping on the host; all registration mutations
occurred inside the disposable container.

## Why this is separate from upstream registration

Pinned System Manager 1.1.0 advances the Nix profile before creating its
separate extra GC root. A collision at the latter can therefore leave a partial
profile. Its GC-root replacement is also remove-then-create.

The guarded program still exercises the exact upstream helper, but wraps it
with an exact pre-state, full post-state verification, and bounded cleanup:

1. require the dedicated profile directory and upstream extra root to be
   entirely absent;
2. require the direct pilot root to retain the exact candidate;
3. invoke the exact candidate's `register-profile`;
4. verify only `system-manager`, `system-manager-1-link`, and
   `system-manager-current`, all resolving to the exact candidate;
5. on failure, remove only exact transaction-owned links;
6. never delete a foreign collision or unknown profile entry; and
7. never call activation, deactivation, systemd reload, or a service command.

The program accepts failure injection only when
`/run/systemd/container` identifies a systemd-nspawn container. The live
wrapper has no failure-injection path.

## Disposable test matrix

The distinct test keeps the exact canary active inside its Ubuntu container and
asserts protected-file hashes and the bounded five-path/three-service state
through every case:

1. active retained canary starts exactly unregistered;
2. a collision visible at preflight causes no profile mutation;
3. a collision introduced after preflight forces the proven upstream partial
   profile advancement, after which the wrapper removes only its profile links
   and preserves the foreign file;
4. a forced failure after complete registration rolls profile and extra root
   back to absence;
5. missing pilot retention refuses registration;
6. unknown profile contents make rollback fail closed without deleting them;
7. successful first registration adds exactly two profile links plus the
   direct extra root without changing live activation; and
8. exact rollback is idempotent and restores the active-unregistered state.

The test finally deactivates only its disposable container and verifies exact
empty version-0 state. All nine named subtests completed in the immutable Nix
build log.

The separately authorized invocation was:

```bash
sudo ./scripts/test-root-registration-transaction.sh
```

The helper requires host state `ACTIVE_RETAINED` before and after, uses the
same root-local process-scoped `auto-allocate-uids`/`cgroups` path as the
prior tests, and performs all registration mutations inside the disposable
container. Repeating it is not an ordinary audit action: if the transaction or
derivation changes, review and separately authorize a new run.

## Proposed live registration SBOM

A future approved live transaction creates exactly:

- `/nix/var/nix/profiles/system-manager-profiles/`, a root-owned dedicated
  directory that was absent beforehand;
- `system-manager-1-link`, directly targeting the exact candidate;
- `system-manager`, the selected-profile link resolving through generation
  one; and
- `/nix/var/nix/gcroots/system-manager-current`, directly targeting the exact
  candidate.

It does not change the version-1 manager state, the five active managed paths,
the three active service keys, the pilot retention root, the boot graph, any
protected service process, Tailscale/Tailscale SSH, GDM/GNOME, Docker, DGX
Dashboard, NVIDIA persistence, the GPU stack, users, wrappers, PATH, or Nix
configuration.

## Future live gate

This disposable PASS does not authorize live registration. Before a live
invocation:

1. commit the exact reviewed repository state;
2. create a fresh root-owned snapshot with
   `scripts/snapshot-root-registration.sh`;
3. verify snapshot checksums, exact active state, protected files, service
   process continuity, sanitized GPU/Tailscale health, and a clean repository;
4. obtain explicit authorization bound to that snapshot;
5. arm the exact ten-minute registration-only rollback;
6. register and verify generation one without activation;
7. repeat all postflight checks;
8. independently verify the local console and enter exactly
   `KEEP REGISTRATION`; and
9. stop the timer only after the repeated postflight passes.

The timed and manual rollback run the root-owned transaction copy embedded in
the private snapshot. They remove only the exact profile/generation-one/extra
root surface. They deliberately leave the active canary and
`dgx-setup-root-canary-pilot` intact.

## Stop conditions

Stop without live registration if the disposable test is not a hash-valid PASS,
either prior passed derivation changes, the host is not exactly
`ACTIVE_RETAINED`, the profile directory or extra root exists, the pilot root
differs, the transaction checksum differs, the repository is dirty, a protected
service restarted or needs reload, Tailscale SSH is unhealthy, systemd/GPU
health fails, the snapshot is older than 30 minutes, or rollback cannot restore
the exact active-unregistered state.
