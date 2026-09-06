# Repository agent instructions

## Required operational skill

Use `$dgx-spark-ops` for work involving DGX Spark updates, drift, Nix runtime
maintenance, flake dependency updates, NVIDIA playbooks, CUDA/GPU workloads,
containers, Tailscale/Tailscale SSH, Hyprland rollout, or fleet operations.

- Treat an unqualified audit or check as read-only.
- Treat `fleet/hosts.json` and `bootstrap/nix/source.json` as the authoritative
  fresh-host selections. Start with `./scripts/dgx-setup plan [HOSTNAME]` and
  never infer install/apply authority from `PLAN_STATUS`; executable bootstrap
  and retained-state convergence are implemented. Use
  `scripts/update-nix-installer.sh` for installer release checks, and keep the
  provisioning artifact separate from the running Nix runtime.
- `./scripts/dgx-setup bootstrap [HOSTNAME]` is the only bootstrap operator.
  Its exact-existing branch is a tested no-op, and its clean-install branch
  passed the exact disposable install, injected-failure/timed-uninstall,
  clean-retry, and second-adoption lifecycle recorded in
  `docs/2026-09-03-nix-bootstrap-lifecycle.md`. Use it only for the Nix
  bootstrap on a declared clean ARM64 host; never invoke the installer binary
  directly or infer authority for unified apply or another ownership layer.
- `./scripts/dgx-setup apply [HOSTNAME]` composes the proven bootstrap and
  headless Home transactions and verifies the retained Nix-managed Tailscale
  and System Manager headless roles. On exact `sparkle-01`, its complete live
  no-op regression passed with `PLAN_STATUS=READY` and
  `APPLY_STATUS=COMPLETE`; read
  `root/desktop/validation/2026-09-05-confirmed-headless-integration.md`.
  Historical `APPLY_STATUS=PARTIAL` evidence predates the completed desktop
  transition.
- The validated fresh-host front door is `./scripts/dgx-setup converge
  [HOSTNAME]`; read `docs/fresh-host-convergence.md`. It uses a generic Home
  module plus exactly two new-host System Manager generations: factory GNOME
  with optional Nix-owned Tailscale, then headless after one separately
  initiated real reboot. It is resumable and never reboots. Do not replay
  `sparkle-01`'s historical pilot operators on a new host, activate raw root
  outputs, or bypass the declared workflow. Its clean-commit root-assisted
  integration gate passed at
  `cc1069cbce87974a545095b3361b78837d618437`; read
  `docs/2026-09-06-fresh-host-convergence-integration.md`. Use it only after
  factory updates, explicit host declaration, and plan/SBOM review. Any
  functional change requires the complete gate again.
- The Dashboard-aware headless/factory-GNOME candidates passed the
  12-subtest transaction, 10-subtest/three-reboot mode lifecycle, 7-subtest
  persistent rollback lifecycle, and post-Tailscale live no-op integration
  against exact commit `abb852d320a01192236d862336bf60c31943714a`. Read
  `root/desktop/validation/2026-09-05-dashboard-aware-stack.md`. The separately
  authorized retry from commit `fc82217` retained exact generation five in
  headless mode with Tailscale intact and no reboot; current authority is
  `root/desktop/validation/2026-09-05-confirmed-headless-integration.md`, with
  the exact transition in
  `root/desktop/validation/2026-09-05-host-attempt-2.md`. Use only
  `scripts/dgx-desktop` for future transitions; never activate a raw candidate
  or call `systemctl isolate` directly on the host.
- Read `docs/decision-register.md` before changing packages, profiles, desktop
  modes, user overlays, or workloads; ACCEPTED/SELECTED is not activation
  authorization.
- Read `docs/software-manifest.md` before realizing any new package or workload.
- Preserve the NVIDIA-owned DGX OS, driver, CUDA, Docker, and container-toolkit
  boundary.
- Keep the permanent fleet base limited to `ncdu`, `lazydocker`, and
  `devbox`; keep XDG/portals role-scoped and replace global unfree permission
  with exact approved exceptions.
- Keep Ghostty in the shared graphical role for GNOME, Hyprland, and KDE; do not
  pull it into headless mode or Armen's personal overlay.
- Installing `lazydocker` does not authorize Docker-group membership, and
  installing `devbox` does not authorize its installer to replace or update
  the repository-owned Nix runtime.
- Keep Armen's graphical apps in the named `armen` overlay. Do not add VS Code,
  NIM, or NVIDIA AI Enterprise; Chromium and Zed are the selected browser and
  editor.
- Chromium 152.0.7977.75, Zed 1.18.0, and LM Studio 0.4.23-1 are exact ARM64
  packages with passed closure-policy checks, but remain candidate-only and
  absent from every Home profile. Read `docs/2026-09-03-chromium-package.md`,
  `docs/2026-09-03-zed-package.md`, and
  `docs/2026-09-03-lmstudio-package.md` before changing them. Chromium requires
  an exact root sandbox integration; never
  browse with `--no-sandbox` or globally relax AppArmor's user-namespace rule.
  Keep Zed's self-update disabled through its documented wrapper. Do not patch
  LM Studio's bundled Deno `lms` binary: it must stay byte-identical and use the
  factory loader. Its vendor Electron launcher falls back to `--no-sandbox`
  because Ubuntu AppArmor blocks Bubblewrap's user namespace; never weaken the
  host policy or activate the package without resolving that explicit gate.
- The first headless Home activation completed through `scripts/dgx-home`; read
  `docs/2026-09-03-home-headless-preflight.md` and
  `docs/2026-09-03-home-headless-host.md`. The real rollback and fresh
  reactivation passed, and snapshot `20260903T120519Z` is current authority. Do
  not invoke the raw activation package or `home-manager switch`. Headless
  deliberately disables Home Manager's user-systemd layer; preserve that
  zero-unit boundary. `activate-headless` is now only for another pristine host,
  not for updating this active generation.
  User snapshots belong under `inventory/<host>/private/`; `raw/` is the
  root-owned System Manager evidence tree and must not be repurposed.
- Later headless generations must use `scripts/dgx-home update-headless` after
  reading `docs/2026-09-03-home-headless-update-lifecycle.md`. It is a no-op
  when current, otherwise retains the candidate, snapshots both exact profile
  inventories, arms rollback before activation, preserves the previous
  generation, and verifies twice before automatic disarming. A reviewed update
  commit may make `currentCandidate` differ from recorded `observedCandidate`;
  reconcile the deployment record after successful activation and before a
  subsequent update. Never bypass this with a raw activation command.
- Keep Armen's Codex defaults maximally permissive in every desktop mode:
  `approval_policy = "never"`, `default_permissions = ":danger-full-access"`,
  automatic review/approval, and destructive/open-world app tools enabled.
  The exact current Codex CLI bundle belongs to Armen's all-modes overlay, not
  the fleet base; disable its startup self-update because the repository owns
  version updates. Reconcile only those keys; preserve mutable auth, plugins,
  MCP servers, project trust, desktop preferences, and history. Keep the old
  standalone release tree until its now-completed Nix launcher migration has
  been exercised long enough for separately reviewed cleanup.
- Keep Hyprland opt-in and do not change the active Home generation or GDM
  unless the exact transition has its reviewed rollback path.
- Never expose secrets or place mutable model/application data in the Nix store.
- Tailscale 1.102.3 and `tailscaled.service` are Nix-managed and active through
  System Manager generation five, inherited unchanged from generation four;
  its identity, online state, SSH setting, and
  real reboot persistence are confirmed. The apt package/repository remain
  installed only as reviewed fallback and do not own the loaded unit. Read the
  skill's Tailscale reference before changing package, unit, state, SSH,
  fallback, or headless-mode behavior; never restart or migrate the live daemon
  outside the guarded operator.
- Never run plain `nix upgrade-nix` from an availability result. Audit its
  Nixpkgs fallback target separately from upstream stable and follow
  `root/nix/README.md`; the current default target is a blocked downgrade.
- Read `root/system-manager/README.md` before changing the System Manager pin,
  overlays, root module, test, state, registration, or activation. The exact
  candidate's bounded host canary is active and directly retained. Its recorded
  activation, registration-lifecycle, guarded
  first-registration, and guarded generation-switch failure-injection container
  tests all passed, and the separately guarded live registration was retained
  after repeated postflight and independent console confirmation. The
  marker-only generation-two candidate and guarded switch transaction passed
  their disposable gate. The separately authorized live pilot then retained,
  registered, selected, and activated exact generation two after repeated
  postflight and local-console confirmation. At that milestone, generation one
  remained registered and both pilot roots were recovery anchors. The
  historical generation-two classifier was
  `ACTIVE_REGISTERED_GENERATION_TWO_RETAINED`. The later separately authorized
  boot-persistence pilot retained exact generation three and its boot edge. The
  first real reboot recovery and first restoration attempt both safely timed
  back to exact generation two; the retry-safe second restoration then passed
  two postflights and automatically retained generation three. The later
  guarded Tailscale handoff registered, selected, activated, and boot-linked
  exact generation four, preserving the node identity and Tailscale SSH across
  a real reboot. The later guarded desktop retry retained exact generation five
  in headless mode without rebooting. Current classifier authority is
  `ACTIVE_REGISTERED_GENERATION_FIVE_HEADLESS_TAILSCALE_NIX_MANAGED`: all five
  generations are registered and directly rooted, generation five is
  selected/upstream-rooted/live and boot-persistent, Nix owns the running
  Tailscale unit, factory GNOME remains installed but inactive, and recovery is
  unarmed. Read the
  generation-switch, boot-persistence, reboot-recovery, and
  `2026-09-03-restoration-host-attempt-1.md` and
  `2026-09-03-restoration-host-attempt-2.md` records plus
  `root/tailscale/validation/2026-09-05-host-attempt-2.md` and
  `root/desktop/validation/2026-09-05-host-attempt-2.md`, then the current
  `root/desktop/validation/2026-09-05-confirmed-headless-integration.md` before
  touching this state.
  Do not rerun the one-time activation, registration, snapshot, switch, or
  boot-persistence helpers; reboot; change boot linkage; select or remove a
  generation; remove any current root; or broaden ownership without a separate
  plan and authorization. Its
  private wrapper must stay on reviewed Nix 2.35.2, and the closure must contain
  neither Nix 2.34.8 nor real `userborn`. Any derivation change makes that test's
  prior evidence stale.
- The generation-switch and boot-persistence snapshot helpers were read-only
  with respect to host configuration but created private root-owned evidence.
  Their distinct live wrappers completed under separate authorization. Never
  rerun any of those helpers against the current post-state or infer new
  authority from their spent snapshots. Preserve all five numbered pilot roots;
  generation cleanup, rollback, and any future reboot are exact reviewed
  actions, not automatic tidying.
- Do not run the root-canary helper or any System Manager activation merely to
  complete an audit. The helper is a separately approved disposable-container
  build; host activation additionally requires local recovery, collisions,
  snapshots, timed rollback, retained store closure, and explicit authorization.
- Low-level System Manager activation does not register or GC-root its output.
  The live pilot therefore still requires the documented
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` symlink. The guarded
  registration, switch, boot-persistence, Tailscale migration, and desktop
  switch retained five direct numbered pilot roots. The current state has all
  five numbered generations, selects generation five, points
  `/nix/var/nix/gcroots/system-manager-current` to generation five, and keeps
  the declarative boot edge plus headless dispatcher. Preserve that exact
  surface plus all five direct numbered pilot roots; never infer
  permission to rerun upstream
  `register-profile`, remove registration, select a different generation, or
  retire any pilot root.
- Preserve the helper's root-only `--store local` path: Nix 2.35 strips
  experimental-feature overrides on daemon connections, while this test needs
  temporary `auto-allocate-uids` plus `cgroups`. Do not persist those settings
  or restart/reconfigure the daemon for the test.
- Preserve `NIX_USER_CONF_FILES=/dev/null` in that helper so root-only user
  configuration cannot add hidden behavior; the system Nix config remains read.
  This isolation does not suppress the observed non-fatal top-level Nix 2.35.2
  `auto-allocate-uids` warning; use the derivation result as the test verdict.
- System Manager 1.1.0 must retain the exact-version
  `skip-empty-tmpfiles` patch and unmanaged-rule regression sentinel. Treat any
  global tmpfiles invocation, missing patch, changed patch hash, or processed
  sentinel as a stop condition; never weaken the test to tolerate factory-rule
  processing.
- Validate on `aarch64-linux` and pilot on one host before fleet rollout.

Follow the skill's routed references rather than duplicating update policy in
ad hoc instructions.
