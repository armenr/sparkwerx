# Workstation validation, 2026-09-24

Target: `spark-9667`, ARM64, user `deadspark`, factory GNOME.
Upstream base: `fd5cf97b50dacac4692f270aeb76cd6acd4b6d5d`.

## Completed checks

- Thirteen workstation tests passed, including rollback, recovery, locking,
  host checks, shell preservation, and saving only the intended Git files.
- The complete Python suite passed in the disposable Nix container:
  55 tests, one existing environment-dependent skip.
- The real Nix 2.35.2 profile integration test passed in that x86_64 container.
  It uses real store paths, `nix-env` generations, and executable checks,
  without mocked profile switches. It covers failed first installation,
  failed update, recovery from a persisted interrupted transaction, disabling,
  reactivation, and verifies retained generations appear among Nix GC roots.
- The curses menu rendered and quit successfully in PTYs at 90x24 and 40x8.
  The latter exercises its terminal-too-small message.
- The ARM64 workstation derivation evaluated successfully. This alone does
  not establish an ARM64 package build or runtime pass.
- `nix flake check --no-build --all-systems --no-write-lock-file` passed for
  the complete flake. These are evaluations, not executions of its systemd
  container tests.
- Modified Python passed Ruff lint/format; modified Nix passed nixfmt.
  Documentation and whitespace checks passed.

The first wider-suite attempt on the local host lacked `pre-commit`. The first
container attempt needed a per-process Git ownership exception for the
read-only source mount. Both environment issues were resolved in the disposable
container; no development dependencies were installed on the DGX host.

## Live host observations and installation hold

SSH, Docker, GDM, and NVIDIA persistence were active. The live GPU reported
NVIDIA GB10, driver 580.178.04. Nix was absent from PATH and no workstation
profile had been activated.

Systemd reported degraded because NVIDIA's
`nvidia-remove-gnome-software-once.service` failed during first boot when another
APT process held the dpkg lock. Its script retries at a subsequent boot and
uses `apt-get -y --auto-remove purge gnome-software gnome-contacts`.

A read-only APT simulation proposed eleven removals, including `gnome-core`,
GNOME Software, Contacts, and `nvidia-firmware-580` version 580.82.09. That
firmware package is older than the separately installed
`nvidia-firmware-580-580.178.04` matching the active driver. No claim is made
that the proposed removal would break GPU operation; it nevertheless changes
factory packages and requires an explicit maintenance decision.

The failed service has not been restarted, disabled, or reset. The upstream
Nix bootstrap requires a healthy systemd state, so host installation is held.
Do not clear the failure merely to pass that check. Either deliberately keep
these applications and disable their pending one-time removal, or review and
complete NVIDIA's cleanup; then recheck host health before bootstrap.

No OS snapshots, host reboot, Nix installation, or package-profile activation
are claimed by these tests. Existing terminal dotfiles remain managed by their
previous deployment.

## Later host checkpoint: desktop retention selected

The owner explicitly chose to keep the desktop applications. They executed
the reviewed `~/keep-desktop.sh` through their own sudo terminal. It recorded
the unit's previous state under `~/.local/state/terminal-setup/`, disabled only
the one-time package-removal service, and acknowledged that unit's failure.
Independent SSH checks then confirmed:

- systemd status `running`;
- the one-time service `disabled`, `inactive`, result `success`;
- GNOME Software and Contacts still installed;
- GDM, SSH, Docker, NVIDIA persistence, Dashboard, and Dashboard Admin active.

The original health hold is resolved. No packages were removed and no reboot
occurred. Re-enabling this unit would restore its pending removal at a future
boot; that would reverse the owner's selected policy and is not automatic
recovery behavior.

The official installer freshness check found a separate hold:
the repository pins 2.35.1, while the currently published installer is 2.35.2
(ARM64 SHA-256 `a1b35e56da5adadbc117c3cf17b83948ac657f3c0bd79d47bbe0aa70832b5c8e`).
The check verified the downloaded artifact and returned its documented
update-needed exit status. The pin has not been changed and host Nix remains
absent. Updating it affects the existing bootstrap lifecycle evidence and
must receive matching installation/uninstall/recovery tests before activation.

## Native ARM64 package validation

The separate `sparkwerx-workstation-validation` Docker container built the
workstation package successfully on the Spark. Its only host bind mount was
the checkout, read-only; it had no GPU access, Docker socket mount, privileged
mode, host Nix store, or host home-directory mount.

Image: `nixos/nix:2.35.2`, manifest digest
`sha256:7a007c766426c1877758ddc5cb87a965ac131fc78c582ce0083d922d51ae945c`.
Docker inspected its selected architecture as `arm64`.

Built derivation:
`/nix/store/w46bph3llxr3yb5wam67s4g527503aia-sparkwerx-deadspark.drv`.
Output:
`/nix/store/19ppl4g73746z67i8xwnd0apfdnrz8yp-sparkwerx-deadspark`.

Version checks passed for ncdu 2.9.2, lazydocker 0.25.2, Devbox 0.18.0,
nh 4.4.2, and fzf 0.72.0. Help/startup checks passed for nix-output-monitor
2.2.0 and nix-search-tv 2.2.7; their versions came from the built manifest.
nix-search-tv does not implement `--version`, so its initially rejected version
flag was replaced with its supported help check. The packaged `spark` launcher
ran after its expected checkout path was provided inside the container.

The real Nix-profile lifecycle test passed again natively on ARM64. In
addition, the actual package output above was activated, disabled, and restored
in a temporary container-only profile, with its executable postflight passing
on both activations. These checks did not create a host package profile.

## Workstation installer hold resolved

A separate workstation bootstrap input root now pins official installer
2.35.2, while relative symlinks reuse the original bootstrap, updater, and
rollback code without modification. The pilot's installer pin and root
lifecycle derivations are unchanged. The setup entry point composes that
bootstrap with the previously validated user-package lifecycle.

The new installer passed a native ARM64 Ubuntu 24.04/systemd lifecycle test:

1. Real installation from the exact plan with the recovery timer armed.
2. Deliberately injected post-runtime failure.
3. The timer's systemd service performed receipt-driven uninstall and proved
   the clean boundary, restored shell/configuration files, removed build
   accounts, and preserved the synthetic protected services/GPU output.
4. A successful clean retry installed installer/runtime 2.35.2, passed all
   postflights, and disarmed recovery.
5. A repeat invocation as the normal user adopted the exact installation,
   preserving installer, receipt, configuration hashes, and profile target.

The test image used Ubuntu manifest
`sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3`
with its ARM64 image. Its container had private cgroups and no host filesystem,
host cgroup, Docker socket, or GPU mounts. Systemd required `SYS_ADMIN` and
container-specific AppArmor/seccomp exceptions; host security policy was not
changed. Memory/CPU limits were 4 GiB/four CPUs.

The first harness attempt lacked real sudo ownership context; the second
checked an asynchronous service too early. The corrected harness uses real
sudo and waits for the rollback completion marker. The full final run passed
with exit zero. The bootstrap fixture commit was
`d22e665d967c7a7746ac172e5920e94559e9b00c`; the subsequent changes correct the
test harness, add regression tests, and make the completed setup's tools
immediately available inside the menu. Upstream bootstrap code and pins under
`bootstrap/nix/` stayed byte-identical.

Nineteen workstation regression tests passed, including bootstrap-failure
short-circuiting, adapter/pin isolation, search before setup, and the previous
package recovery tests. Host installation can now use `spark setup`; its sudo
phase remains interactive and its actual hardware/service postflight is
required separately. These disposable results do not claim host activation.

## Healthy Tailscale with optional SSH disabled

The first actual host setup stopped before Nix installation. Sanitized
inspection showed an active Tailscale daemon, `BackendState=Running`,
`Online=true`, `WantRunning=true`, and `RunSSH=false`. This is a healthy VPN;
the optional Tailscale SSH server is not selected for this workstation. The
owner explicitly requires Tailscale to remain running.

The workstation bootstrap is now a dedicated copy of the upstream operator,
with one policy difference (plus shell formatting): it accepts the healthy
VPN state above when `sshDesired=false`. If SSH is desired, it still requires
that feature. Unreadable/offline/unhealthy state still fails. Existing exact
before/after state, service PID/start-time, and recovery checks remain intact.
The updater and rollback remain symlinks to unchanged upstream code; the
original pilot bootstrap remains unchanged.

The full native Ubuntu/systemd lifecycle was repeated from a fresh container
at fixture commit `e5443c0`, with a synthetic active Tailscale service and VPN
reporting `RunSSH=false`. Offline Tailscale was first rejected before Nix
installation. After restoring its healthy fixture state, installation with
injected failure, systemd-driven receipt rollback, clean reinstall, recovery
disarming, and idempotent normal-user adoption all passed. The protected
Tailscale service and sanitized connection/preferences stayed exact throughout.
No actual host Tailscale setting or service was changed by this test.

## Live workstation setup complete

The owner reran `spark setup` from commit `c427082` in their sudo terminal.
Independent postflight confirmed:

- official installer and runtime 2.35.2; the repeated bootstrap verification
  reported exact adoption with zero mutation;
- active user generation 1 points to
  `/nix/store/19ppl4g73746z67i8xwnd0apfdnrz8yp-sparkwerx-deadspark`, identical
  to the native container-tested candidate;
- a fresh Zsh shell resolves `spark`, `nh`, ncdu, lazydocker, and Devbox from
  the isolated user profile and resolves Nix from its installed default profile;
- `spark search btop` succeeds against the selected `nixos-26.05` catalog;
- no pending user recovery transaction or armed installer rollback timer;
- systemd is `running`; Tailscale, GDM, OpenSSH, Docker, NVIDIA persistence,
  Dashboard, and Dashboard Admin are active;
- NVIDIA GB10 still reports driver 580.178.04;
- sanitized Tailscale state remains `Running`, online, wanting to run, with
  optional Tailscale SSH off, exactly as observed before setup.

The active tool set is ncdu 2.9.2, lazydocker 0.25.2, Devbox 0.18.0, nh 4.4.2,
nix-output-monitor 2.2.0, nix-search-tv 2.2.7, fzf 0.72.0, and the `spark`
launcher. btop was searched successfully but was not selected or installed.
The completed Docker test containers were stopped; their evidence/cache were
retained. No host reboot, desktop transition, Tailscale reconfiguration, or
driver replacement occurred.

## Guided package manager and SSH terminals

Commit `654a6a7` fixes Nix Python's missing Ubuntu terminfo search paths while
preserving the real terminal type and user overrides. Commit `784bd67` adds
guided install/remove/update, an ARM64-filtered multi-select package picker,
a generation picker, and a smaller main menu with the manual controls under
Advanced. Non-login SSH launches discover the installed Nix/profile tools.

Thirty-three workstation tests passed. Guided-flow tests use real temporary
Git repositories with controlled build/activation outcomes and cover:
cancelled selections and pin updates, build failure, keyboard interruption,
commit-before-activation, retained configuration after activation failure,
removal, successful pin updates, unchanged selections, and preservation of
preexisting/intervening edits. Catalog tests cover ARM64 filtering and exact
attribute ordering; picker tests cover cancellation and unexpected output.
The existing real Nix profile-recovery evidence above still applies; the
guided-flow unit tests do not claim to perform real Nix builds.

All 75 Python tests passed in the existing disposable Nix container, with one
existing environment-dependent skip. The first local wider-suite attempt
lacked pre-commit; the successful container run used its cached dependency.
Ruff, documentation, and whitespace checks passed. The container was stopped
afterward.

The new menu rendered through the active Nix Python launcher in actual SSH
PTYs with `TERM=xterm-kitty` at 100x24 and `TERM=xterm-ghostty` at 90x24. Kitty
search displayed ARM64 btop results, and Tab/Enter returned the exact selected
attribute. The attempted follow-on build was correctly refused because the
owner was already running an install; no competing package transaction ran.

The owner's first guided install produced clean local commit `710cd8d` and
active generation 2, adding `networkmanager` 1.56.0. Ubuntu already supplies
`/usr/bin/nmtui`; this selection adds a separate user-profile package and does
not configure its daemon. Independent inspection confirmed NetworkManager,
Tailscale, GDM, SSH, and Docker remained active.

The owner's subsequent guided upgrade completed as clean commit `00d6115`
and active generation 3. It advanced only `nixpkgs-workstation` to
`c508844df6c28fa6dabc1b6af70f3ccbd65c5201`; the other existing input pins
remained unchanged. Direct package versions were unchanged, while the new
dependency/build outputs required downloads. The active output was
`/nix/store/2cnalb5znwld82lhaxv4qlgb5mlny74g-sparkwerx-deadspark` and no
user recovery journal was pending.

## Branch publication checks

The complete `./scripts/dev check` passed natively on ARM64 at `d34ebdd` in
the existing disposable validation container: repository lint/format checks,
documentation checks, 76 Python tests (one existing environment-dependent
skip), the systemd whole-record parser regression, and the full flake
evaluation with `--no-build`. This evaluated the container-test derivations;
it did not rerun their host-transition scenarios.

The initial full-check attempts exposed container setup issues: Git ownership
of the read-only source mount, Ruff's default cache location, and the minimal
image's absent `/etc/os-release`. These were resolved inside the container.
The check also exposed duplicate lint findings through the reused bootstrap
symlinks. The checker now recognizes an in-repository alias's existing target
exception only while the exact content hash matches. Regression coverage
rejects changed content, copied scripts, external links, and unlisted checks.
No historical script or exception hash was rewritten to pass validation.

A comparison against the upstream base confirmed every pre-existing flake
input pin remains unchanged. The branch adds only `nixpkgs-workstation` to
that graph. The final documentation-only evidence update passed the local
documentation and whitespace checks separately.

## Pending-selection repair, 2026-09-25

The owner encountered a pending `btop` edit while independent workload files
were untracked. The save guard refused unrelated files, but did not identify
them. Preview also displayed an older candidate beside newer selections.
Implementation `4e86563` adds `spark finish`, file-specific blockers before
selection/bootstrap, and exact candidate checks in Preview. It preserves the
clean-commit activation boundary and existing edits on cancellation/failure.

The full `./scripts/dev check` passed in the retained disposable ARM64 Nix
container against the implementation bytes: lint, docs, 86 Python tests
(one existing environment skip), systemd parser checks, and flake evaluation
without builds. The 43 workstation tests cover completion, cancellation,
interruption, intervening edits, unrelated files, stale builds, and candidate
mismatch. Real Nix profile integration separately passed failed first
install/update recovery, interrupted recovery, disable/re-enable, rollback,
and retained GC roots. The validation container was stopped after use.

Workload files were separately committed at `98809ba`; original untracked
files and user selection were backed up privately before deployment. The
pending selection was preserved, built, reviewed, committed by the operator
at `f581800`, and activated as generation 4:
`/nix/store/97xhrzndr722m1v04fmiqdyn6aclgdp5-sparkwerx-deadspark`.
It adds `btop` 1.4.7. Its binary reports `BTOP_GPU=ON`; its terminal interface
opened and exited successfully. GPU metric accuracy was not measured.

Generations 1–3 remain retained, Git is clean, and no recovery journal is
pending. The menu rendered and exited under `xterm-kitty` and `xterm-ghostty`
pseudoterminals. GDM, Tailscale, OpenSSH, and Docker remained active; the model
container stayed healthy. No bootstrap, service migration, or reboot was used.

The guided test fixture was then made independent of the owner's live package
list so installing `btop` cannot invalidate its install/cancel scenarios. All
43 workstation tests and scoped lint/docs checks passed again.

## Zombie-process correction, 2026-09-28

Live inspection found 30 exited Git processes parented by `sleep` in the
retained `sparkwerx-workstation-validation` container. It had been restarted
for later checks, lacked Docker's init process, and was left idle afterward.
Stopping only that idle container cleared these zombies; its stopped filesystem
and cached results remain available. Do not restart it for future checks.

The new [container runner](../scripts/dev-container) runs a foreground task with
`--init`, automatic removal, signal cleanup, and an in-container deadline. Its
source mount is read-only; checks use a private writable copy. It uses the same
pinned Nix image with no pull, GPU access, Docker socket mount, or host Nix/home
mount. See [development](../docs/development.md#disposable-docker-checks).

The explicit [Docker lifecycle test](../dev/container_lifecycle.py) passed on
the real ARM64 host: 30 deliberately orphaned children were reaped while the
task was still alive; successful exit, exit 42, a one-second deadline (124),
and runner SIGTERM (143) all left no test container. ShellCheck, shfmt, Ruff,
Python syntax, documentation, and whitespace checks passed. This change did
not rerun the full Nix build/flake suite or activate a package profile.

Five real `spark status` invocations completed without new tool-owned zombies.
Inspection of `spark`, `vllm_stop`, and the GPUStack control source confirmed
their direct subprocess calls wait for children using `subprocess.run`.
This does not claim every third-party workload can never create a zombie.

One separate zombie belonged to factory Speech Dispatcher 0.12.0-rc2. A service
restart cleared it temporarily, but optional `espeak-ng-mbrola` failed during
initialization and recreated it. The normal `espeak-ng` and `openjtalk` modules
were working. The user requested correction of the reported zombies.

The reviewed [speech configuration](speech-dispatcher.conf) was copied to the
previously absent `~/.config/speech-dispatcher/speechd.conf` for deadspark only.
It includes the factory configuration and explicitly selects the existing
working modules and dummy fallback, avoiding the failed optional backend.
This is a user-owned workaround, not Nix ownership of the factory speech
package or service. The pre-change record is under
`~/.local/state/sparkwerx/speech-module-fix/before.json`.

The service stayed active, its advertised speech modules stayed identical,
and the factory configuration hash stayed unchanged. Zero zombies were observed
after both the initial application and a second service restart. No audible
speech test was performed. Rollback removes only the added user configuration
and restarts `speech-dispatcher.service` through `systemctl --user`; that returns
to factory autodetection and can restore the original MBROLA zombie.

Model containers were not started, stopped, or modified by this correction.
The owner stopped Ornith independently during the work. GPUStack's server and
worker remained running; GNOME, Docker, Tailscale, and SSH ownership did not change.
