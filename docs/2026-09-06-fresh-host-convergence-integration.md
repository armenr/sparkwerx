# Fresh-host convergence integration — 2026-09-06

## Result

**PASS.** The complete operator-facing fresh-host gate ran from clean commit
`cc1069cbce87974a545095b3361b78837d618437` on `sparkle-01`:

```console
./scripts/test-fresh-host-convergence-integration.sh
```

The wrapper refuses a dirty tree. Its final results were:

```text
PASS|dgx_home_rollback_test|exact first-generation profile, files, launcher, and config restored
PASS|dgx_home_update_rollback_test|completed and partial updates restored exact previous profile, roots, managed links, and config
PASS|fleet_root_bootstrap_lifecycle|optional access, pristine install, reboot recovery, headless switch, and host non-mutation passed
PASS|dgx_setup_plan_test|declaration, bootstrap adoption, Nix-managed Tailscale, headless generation five, privacy, and zero-mutation checks passed
PASS|dgx_setup_apply_test|Nix, Home, Nix-managed Tailscale, and headless generation five converged as no-ops; root, services, and mutable state stayed exact
PASS|dgx_setup_converge_test|historical convergence was recognized and every live layer remained an exact no-op
PASS|fresh_host_convergence_integration|bootstrap, optional access, factory-to-headless lifecycle, Home rollback, and live no-op convergence passed
```

The clean-host Nix bootstrap lifecycle also returned success inside the
wrapper. It is intentionally quiet on success.

## Coverage

The one clean-tree gate composed all of these previously separate boundaries:

- first Home generation failure/rollback in a private temporary home;
- completed and partial later Home update rollback, including exact profile,
  GC-root, managed-link, launcher, and config restoration;
- official pinned Nix installation from a clean boundary, an injected failure
  followed by receipt-driven timed uninstall, a clean retry to Nix 2.35.2 with
  persistent flakes, and a second exact no-mutation adoption;
- both selected and unselected Tailscale declarations, with existing identity
  preserved when the service moves from an apt-shaped fixture to Nix;
- exact pristine rollback after an injected factory-generation failure;
- automatic persistent rollback of an unconfirmed factory generation across a
  reboot, then confirmation and survival across another reboot;
- exact factory rollback after an injected headless-generation failure;
- automatic rollback of an unconfirmed headless transition without changing
  access, then confirmation and survival across the third reboot; and
- the real historical `sparkle-01` through plan, apply, and converge only as
  read-only or exact no-op operations.

All Nix installation, System Manager registration/activation, Tailscale
ownership changes, desktop transitions, rollbacks, and reboots occurred only
inside disposable Ubuntu containers or private temporary homes. The wrapper
snapshotted the live root paths, protected files, and protected unit metadata
before and after the root lifecycle and required exact equality. It did not
reboot or transition `sparkle-01`.

## Exact disposable evidence

| Lifecycle | Derivation | Output | NAR hash | NAR size |
| --- | --- | --- | --- | ---: |
| Clean Nix install/failure/uninstall/retry/adoption | `/nix/store/z9x6kgqrs5905gj7wqdycr7sbi8x9pmd-container-test-dgx-nix-bootstrap-lifecycle.drv` | `/nix/store/s5pzsb82hixjcc9kcjw50nm37g9r8lpi-container-test-dgx-nix-bootstrap-lifecycle` | `sha256-DcCCVdIob23Q/gYSu/hv+mF76NFvKH62NXSsKjQ63Iw=` | 7,104 bytes |
| Optional access/factory/headless/rollback/three-reboot lifecycle | `/nix/store/yfa7ghk13b0hdg0xg57v4m6an87ad75n-container-test-dgx-fleet-bootstrap-lifecycle.drv` | `/nix/store/r0bmci24jwpb57w9svhmhnad0fbpbp3q-container-test-dgx-fleet-bootstrap-lifecycle` | `sha256-A1lI9Ak8PXnaV5NMo3cTsCKUxqlr08Vzluykw+YFmz4=` | 11,160 bytes |

The exact fleet candidates and bundle were:

| Role | Store path |
| --- | --- |
| Tailscale-selected factory generation | `/nix/store/i4k101nsm0jkbrq7ddzhr6l8l2wxkm84-system-manager` |
| Tailscale-selected headless generation | `/nix/store/ry411kd0pw6c8b23qbv01jrfz8p7ckrx-system-manager` |
| Tailscale-disabled factory generation | `/nix/store/sjibzd6sf1ps8izzajqswb06z186lmgb-system-manager` |
| Tailscale-disabled headless generation | `/nix/store/7fv59vjf3bc738clq27s0sm10g6s8g1d-system-manager` |
| Accelerated test rollback bundle | `/nix/store/vg4bda13179ysf7h938z2bxfyfqlva7s-dgx-fleet-bootstrap-test` |
| Exact transaction program | `/nix/store/8zmam1dv3pa78g1myh7l151v3iz2k54y-root-fleet-bootstrap-transaction.sh` |

Relevant source hashes at the tested commit:

| Source | SHA-256 |
| --- | --- |
| `scripts/test-fresh-host-convergence-integration.sh` | `24a89dd08ac9e51c79a184b7ce3183db7f7f4ae7403d84889ba1a67ad3eb2c59` |
| `scripts/test-nix-bootstrap-lifecycle.sh` | `bd235b2b07bab0db7904cbb5b499d4f4ec91b40610368f1658cc63840b16a1f6` |
| `scripts/test-dgx-home-rollback.sh` | `2883f7f5a8e7c0509920946b292f36d48a5c87dca8ba993e3bb14051e8d089ea` |
| `scripts/test-dgx-home-update-rollback.sh` | `0d49deb61e46626d8683ebcfe60a72ec4c0e1e7f81a1815cd44fd0c05d521986` |
| `scripts/root-fleet-bootstrap-transaction.sh` | `903db6f603113e407d27528bd2673f881bdc90a0b8fefd20eae9a6c51623d780` |
| `root/fleet/bootstrap-lifecycle-test.nix` | `e8d9645b10f9bc2518c1f314390dde9f518a6404c613e0c05f429b80ae432744` |
| `root/fleet/bootstrap-bundle.nix` | `991cef364af83cf91e0705fb2890fbfcf24e11f4f4aff8c0301fb68562803ff6` |
| `scripts/dgx-fleet-bootstrap` | `69727a368376a1a8a793d1f682c751a83f17afad08f4e246c2b01b8aea4c45ba` |
| `scripts/dgx-setup` | `77fc5b096dd63875fa8e2b22486f3309cbaac1a37cfd3162acfe6a3cd38ae5ec` |

## Failures closed during qualification

The integration gate was not made green by weakening assertions. Three
cross-boundary defects were exposed, fixed in separate commits, and followed
by a complete clean-tree rerun:

- `371178f6d23a28be41026d7af99a7141e9729dcd` made Home symlink inventory
  comparison deterministic while retaining exact rollback checks.
- `02d8f0f6c35c1eaebadaada9226c627dbace95aa` corrected unit verification to
  compare resolved immutable payloads. systemd legitimately reports a stable
  `/etc/systemd/system` `FragmentPath` for a link whose payload is in the Nix
  store.
- `cc1069cbce87974a545095b3361b78837d618437` persisted the disposable host's
  declared name through reboot and replaced a silent 15-minute wait with a
  bounded diagnostic wait. Before that fix, the generic transaction correctly
  rejected the `sparkle-01` candidate after the fixture reverted to `ubuntu`;
  the refusal was useful proof that cross-host candidates fail closed.

## Authority boundary

This record promotes `./scripts/dgx-setup converge <hostname>` for initial
convergence of a newly declared, supported ARM64 DGX Spark after NVIDIA factory
updates and explicit plan/SBOM review. The operator remains resumable and never
reboots; every reported reboot checkpoint requires a separate human-initiated
reboot with independent recovery available.

This PASS does not authorize enabled AI workloads, Hyprland or KDE host
integration, Chromium/Zed/LM Studio activation, ChatGPT or browser-extension
packaging, removal of apt fallback material, later System Manager generation
updates, secret enrollment, or mutable model/data placement. Those remain
independent decisions and lifecycles. Any functional change to the validated
fresh-host path invalidates this exact evidence until the complete clean-tree
gate passes again.
