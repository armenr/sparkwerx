# Repository agent instructions

## Required operational skill

Use `$dgx-spark-ops` for work involving DGX Spark updates, drift, Nix runtime
maintenance, flake dependency updates, NVIDIA playbooks, CUDA/GPU workloads,
containers, Tailscale/Tailscale SSH, Hyprland rollout, or fleet operations.

- Treat an unqualified audit or check as read-only.
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
- Keep Armen's Codex defaults maximally permissive in every desktop mode:
  `approval_policy = "never"`, `default_permissions = ":danger-full-access"`,
  automatic review/approval, and destructive/open-world app tools enabled.
  The exact current Codex CLI bundle belongs to Armen's all-modes overlay, not
  the fleet base; disable its startup self-update because the repository owns
  version updates. Reconcile only those keys; preserve mutable auth, plugins,
  MCP servers, project trust, desktop preferences, and history. Keep the old
  standalone release tree until the Nix launcher migration is activated and
  verified.
- Keep Hyprland opt-in and do not activate Home Manager or change GDM unless the
  user explicitly approves that exact activation.
- Never expose secrets or place mutable model/application data in the Nix store.
- Treat the existing apt-installed Tailscale as migration input, not a permanent
  exception. Read the skill's Tailscale reference before changing its package,
  unit, state, SSH preference, or headless-mode behavior. The repository's
  package/unit outputs are build-validated but deliberately inactive; never
  replace or restart the live daemon without the explicit migration gates.
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
  two postflights and automatically retained generation three. Current
  classifier authority is
  `ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`: all three
  generations are registered and directly rooted, generation three is
  selected/upstream-rooted/live, its declarative boot edge exists, and recovery
  is unarmed. Read the
  generation-switch, boot-persistence, reboot-recovery, and
  `2026-09-03-restoration-host-attempt-1.md` and
  `2026-09-03-restoration-host-attempt-2.md` records before touching this state.
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
  authority from their spent snapshots. Preserve all three pilot roots;
  generation cleanup, rollback, and any future reboot are exact reviewed
  actions, not automatic tidying.
- Do not run the root-canary helper or any System Manager activation merely to
  complete an audit. The helper is a separately approved disposable-container
  build; host activation additionally requires local recovery, collisions,
  snapshots, timed rollback, retained store closure, and explicit authorization.
- Low-level System Manager activation does not register or GC-root its output.
  The live pilot therefore still requires the documented
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` symlink. The guarded
  registration, switch, and boot-persistence work retained three direct pilot
  roots. The current restored state has all three numbered generations,
  selects generation three, points
  `/nix/var/nix/gcroots/system-manager-current` to generation three, and keeps
  generation three's declarative boot edge. Preserve that exact surface plus
  all three direct pilot roots; never infer
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
