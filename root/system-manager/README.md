# System Manager root canary

This directory documents the bounded non-NixOS root-manager pilot for the
existing Ubuntu-based DGX OS substrate. The configuration is defined by
`hosts/sparkle-01/system.nix` and `modules/system/minimal-root.nix`.

Nothing in this directory, the flake input, or a successful build activates the
manager. As of 2026-08-23, no System Manager profile has been registered and no
System Manager configuration has been applied to the host.

## Reviewed candidate

| Field | Reviewed value |
| --- | --- |
| Manager | System Manager 1.1.0, MIT |
| Source | `numtide/system-manager` `release-26.05` |
| Revision | `05e08c6dd739d7f3204e71322594bb8095334cfb` |
| Source timestamp | 2026-08-14 14:22:29 UTC |
| Platform | `aarch64-linux` |
| Private Nix runtime | Official Nix 2.35.2 release flake at `2c73b59da29606068c0c98db015dd3a66955525d` |
| Built canary closure | 109 paths, 230.0 MiB NAR |
| Host activation | **Not performed** |

The release branch deliberately matches stable Nixpkgs/Home Manager 26.05.
System Manager is a candidate for small reviewed root integration above DGX OS;
it is not allowed to turn the machine into NixOS or own NVIDIA components.

## Exact canary ownership

The evaluated configuration has no global packages and declares only:

- `/etc/dgx-setup/canary`, a repository-identifying symlink that refuses to
  replace a collision;
- `/etc/systemd/system`, containing only the three units below;
- `dgx-setup-canary.service`, a no-network oneshot that tests the canary link;
- `system-manager.target`, started explicitly by the activation engine; and
- `sysinit-reactivation.target`, System Manager activation infrastructure.

It declares no port, socket, secret, user, group, setuid wrapper, application
state, desktop change, Tailscale unit, Nix daemon unit, Docker unit, or GDM unit.
It is not linked into the factory default target and cannot start at boot.

System Manager itself writes operational rollback bookkeeping at
`/var/lib/system-manager/state/system-manager-state.json` during low-level
activation. Deactivation removes managed links/units and empties that state,
but deliberately leaves the empty state file. That exact residual path is part
of the SBOM; it is not application data.

The canary build and isolated test do not register a generation. Registration
would separately write:

- `/nix/var/nix/profiles/system-manager-profiles/system-manager`; and
- `/nix/var/nix/gcroots/system-manager-current`.

Both paths must remain absent until generation registration receives explicit
approval.

## Defaults we rejected

Upstream's nominally empty configuration is broader than this project's empty
root role. The repository explicitly disables or removes:

- Nix configuration ownership and `/etc/nix/nix.conf` generation;
- `userborn.service` and all user/group/passwd/shadow ownership;
- setuid/setgid wrappers and the wrapper mount;
- global system packages;
- login-wide PATH/XDG hooks in `/etc/profile.d` and `/etc/environment.d`;
- `system-manager-path.service`;
- tmpfiles configuration;
- `/run/current-system`; and
- the boot-time `default.target` link.

The policy check fails if these defaults return, if any unexpected service or
`/etc` entry appears, or if Nix 2.34.8 or a real `userborn` runtime re-enters the
closure.

## Runtime versus lock graph

Stable Nixpkgs currently exposes Nix 2.34.8. System Manager normally wraps its
engine with that `pkgs.nix`, even though this host runs verified Nix 2.35.2. The
repository therefore pins the official Nix 2.35.2 release flake independently
and overlays only System Manager's private wrapper. This does not update or own
the host Nix installation. The final closure contains Nix 2.35.2 and contains
no Nix 2.34.8.

Upstream's deactivation script also adds `services.userborn.package` to `PATH`
unconditionally. Because this canary forbids user ownership, that package is an
empty `disabled-userborn` directory. The real `userborn` binary is absent from
the runtime closure.

`flake.lock` still records System Manager's `userborn` source input and both
upstreams' development/test inputs. Those records make source evaluation
reproducible; they are not services or runtime packages. Do not confuse lock
graph membership with installation or activation.

No persistent substituter or trusted key was added for System Manager. Builds
use the host's existing Nix cache policy.

## Read-only evaluation and SBOM

Run from the repository root:

```bash
./scripts/check.sh

nix --extra-experimental-features "nix-command flakes" \
  eval --json .#lib.dgxRootManagerManifest.aarch64-linux
```

The first command evaluates invariants only. The second emits the exact manager
revision, private Nix runtime, ownership surface, state, registration paths,
and activation status.

Review missing builds without realizing anything:

```bash
nix --extra-experimental-features "nix-command flakes" \
  build --dry-run --no-link \
  .#root-system-canary \
  .#checks.aarch64-linux.root-manager-policy \
  .#checks.aarch64-linux.root-canary-container
```

An explicitly approved no-link runtime build is:

```bash
nix --extra-experimental-features "nix-command flakes" \
  build --no-link \
  .#root-system-canary \
  .#checks.aarch64-linux.root-manager-policy
```

This realizes store objects only. It does not create a profile, GC root, host
link, state file, unit, or service.

## Isolated activation/rollback test

The flake defines an Ubuntu 24.04 `systemd-nspawn` test that activates and
deactivates the canary inside a disposable Nix build sandbox. It verifies:

- protected Nix/passwd/group/shadow files are byte-identical;
- no global PATH hooks, `/run/current-system`, boot link, users, or wrappers;
- exactly the canary and three expected units become managed;
- no System Manager profile or GC root is registered;
- deactivation removes the canary and units; and
- the residual manager state is an empty version-0 record.

The test harness requires the Nix `uid-range` system feature plus
`auto-allocate-uids`. UID-range builds are automatically isolated with cgroups,
so the Nix `cgroups` experimental feature is also required. Neither experimental
feature is persistently enabled for the daemon.

Nix 2.35 deliberately removes `experimental-features` from client-to-daemon
setting overrides. Passing these flags through the running daemon therefore
causes it to ignore `auto-allocate-uids` and reject `cgroups`. The reviewed
helper avoids that mismatch by using the same store directly as root with
`--store local`; the ordinary user cannot perform that direct-store build.

The initial 2026-08-24 invocation used the daemon path and stopped before the
container builder ran. It created no System Manager link, unit, profile, GC root,
manager state, or service change. Nix did create its empty UID-allocation lock
at `/nix/var/nix/userpool2/slot-0` and a stale temporary-root record under
`/nix/var/nix/temproots/<exited-pid>`. The latter is not a permanent GC root;
Nix removes stale temporary-root records during a future garbage-collection scan.
No manual cleanup was attempted. That preflight failure is why the direct-store
path is explicit.

After reviewing the command, run this one test with a temporary root-local
build setting:

```bash
sudo ./scripts/test-root-canary.sh
```

The reviewed helper invokes `/nix/var/nix/profiles/default/bin/nix` against the
local store with `auto-allocate-uids` and `cgroups` enabled only in that
root process. It does not edit `nix.conf`, stop/reconfigure/restart the daemon,
create a profile, or activate the host. Like every build, it may add test paths
and build records to the Nix store. UID allocation uses persistent lock files
under `/nix/var/nix/userpool2`; cgroup cleanup tracking may remain under
`/nix/var/nix/cgroups/<uid>`. These are Nix operational bookkeeping, not a
System Manager generation or host configuration. The one-time dry-run was
943.7 MiB download
and 3.9 GiB unpacked, primarily the Ubuntu rootfs, Rust/build tools, Python test
driver, and systemd utilities. Those are test dependencies, not the 230.0 MiB
runtime closure and not a system profile.

## Host activation hold

Do not activate this canary merely because evaluation, build, or the container
test passes. A pilot host activation still requires all of the following in the
same maintenance window:

1. independently verified local console/recovery access—not only Tailscale SSH;
2. an exact collision report for every declared `/etc` and systemd path;
3. snapshots of the relevant `/etc`, System Manager state, profile, and GC-root
   paths;
4. live checks for Tailscale, GDM/GNOME, Nix daemon, Docker, and NVIDIA services;
5. a timed rollback plan and the exact already-built output path; and
6. Armen's explicit authorization for this activation only.

Low-level deactivation for an already-activated, exact built output is:

```bash
sudo /nix/store/<reviewed-system-manager-output>/bin/deactivate
```

Deactivation is not an uninstall: the empty state file remains, and any future
registered generation/profile requires separate cleanup review. Never replace
the placeholder with a floating flake reference in a rollback command.

## Updates

`scripts/update-dependencies.sh` advances the matching System Manager release
branch and reruns its evaluation, closure-policy, and no-link runtime gates. The
root-assisted container test remains the explicit helper above. Any changed
ownership surface or closure fails review rather than being accepted automatically.

The `nix-release` input is an exact tag and is intentionally not auto-advanced.
Audit and activate a new host Nix runtime through `root/nix/README.md` first;
then update the private manager runtime to that same reviewed release in a
separate repository change. Availability is not update authorization.
