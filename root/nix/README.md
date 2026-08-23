# Nix runtime ownership and guarded updates

Nix is not part of the DGX factory substrate. Devbox triggered the official
NixOS `nix-installer`, which provisioned the multi-user daemon and root default
profile at Nix 2.35.1. The repository's guarded update procedure later moved
the active default profile and daemon to Nix 2.35.2. Devbox neither owns nor
updates that runtime.

## Why `upgrade-nix` proposes 2.34.8

`nix upgrade-nix` does not resolve the newest version or compare the target
with the installed version. Nix 2.35.1's implementation downloads Nixpkgs'
default `nix-fallback-paths.nix`, selects the current system's literal store
path, and passes that path to `nix-env -i`. Even its dry-run message is
unconditionally phrased as “would upgrade.”

On 2026-08-23 the independent facts are:

| Fact | Version |
| --- | --- |
| Initial runtime and retained `nix-installer` release | 2.35.1 |
| Active default-profile runtime after guarded rollout | 2.35.2 |
| Nixpkgs manual fallback pointer for `aarch64-linux` | 2.34.8 |
| Newest final upstream Nix tag and ARM64 artifact | 2.35.2 |

Therefore the default command remains a real downgrade and is on hold. This is
an upstream metadata/design failure, not a dependency solver recommendation.

## Audited 2.35.2 release

[`release.json`](release.json) records the signed tag commit, official ARM64
artifact URL and published SHA-256, exact top-level Nix store path, and its NAR
hash in the signed `cache.nixos.org` metadata. The release artifact was
downloaded to a temporary directory, checksum-verified, and inspected to derive
that store path. A read-only binary-cache query confirmed that the path is
available with a valid `cache.nixos.org-1` signature.

[`store-paths.nix`](store-paths.nix) is the deliberately narrow input accepted
by `nix upgrade-nix --nix-store-paths-url`. It exists so the update can be
reviewed and reproduced; it does not update anything by itself.

From the repository root, the no-change proof is:

```bash
nix --extra-experimental-features "nix-command flakes" \
  upgrade-nix --dry-run --refresh \
  --profile /nix/var/nix/profiles/default \
  --nix-store-paths-url "file://$PWD/root/nix/store-paths.nix"
```

It must name 2.35.2 or report that exact release already current. The default
dry-run must remain a separate audit because its result may change
independently.

## Pilot activation record

Armen explicitly approved the pilot activation on 2026-08-23. Immediately
before mutation, the tag commit, official artifact SHA-256, signed-cache NAR
hash/signature, ARM64 binary, store path, and custom dry run were re-verified.
The signed closure was fetched without activation first. The sanitized
[host checkpoint](../../inventory/sparkle-01/2026-08-23-nix-2.35.2.md) records
the before/after evidence.

The approved root command installed Nix 2.35.2, after which systemd was reloaded
and only `nix-daemon.service` was restarted. Postflight proved:

- the PATH client and default-profile client both report 2.35.2;
- the daemon store protocol reports version 2.35.2;
- Nix diagnostics pass PATH, GC-root, and client/store protocol checks;
- a real policy derivation builds through the restarted daemon;
- all repository evaluations pass; and
- apt-owned `tailscaled.service` retained its original PID, start time, unit,
  backend/online state, and Tailscale SSH availability.

The explicit profile path produced this observed topology:

```text
/nix/var/nix/profiles/default
  -> default-1-link
  -> /nix/store/9lznxxcs35sn5zs899hfpyk2v1jcxpn5-user-environment
  -> Nix /nix/store/fw98swa1g4ysvmv6p6m6xf51kzhvpp6p-nix-2.35.2
```

The installer-created root-user profile remains a separate GC root:

```text
/nix/var/nix/profiles/per-user/root/profile
  -> profile-1-link
  -> /nix/store/qing8va3nif2ydr6mw3pw41i58g11m5w-user-environment
  -> Nix 2.35.1
```

Because the retained environment is not an older generation in the new
`default` profile lineage, do not use an unqualified `--rollback`. If a
reviewed rollback becomes necessary, set the exact retained environment:

```bash
sudo /nix/store/fw98swa1g4ysvmv6p6m6xf51kzhvpp6p-nix-2.35.2/bin/nix-env \
  --profile /nix/var/nix/profiles/default \
  --set /nix/store/qing8va3nif2ydr6mw3pw41i58g11m5w-user-environment
sudo systemctl daemon-reload
sudo systemctl restart nix-daemon.service
```

Then verify client and daemon version 2.35.1 plus repository behavior. Do not
garbage-collect the retained environment until the pilot is accepted. Review
store database compatibility before relying on rollback.

For a future release or another host, the release files still grant no
automatic activation authority. Re-run the full provenance, downgrade,
profile-generation, dry-run, service-restart, and rollback gates.

Do not reinstall Nix, rerun the Devbox bootstrap, or replace `/nix/receipt.json`
or `/nix/nix-installer` just to update the root Nix package. Those are
provisioning/repair artifacts and may legitimately remain at the installer
release that created the installation.

## Authoritative sources

- [`upgrade-nix` 2.35.2 manual](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-upgrade-nix.html)
- [Nix 2.35.1 upgrader implementation](https://github.com/NixOS/nix/blob/2.35.1/src/nix/upgrade-nix.cc)
- [default manually maintained fallback paths](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/tools/nix-fallback-paths.nix)
- [official community installer and its update guidance](https://github.com/NixOS/nix-installer#upgrading-nix)
- [signed Nix 2.35.2 tag](https://github.com/NixOS/nix/releases/tag/2.35.2)
- [official Nix 2.35.2 ARM64 artifact](https://releases.nixos.org/nix/nix-2.35.2/nix-2.35.2-aarch64-linux.tar.xz)
