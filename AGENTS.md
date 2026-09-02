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
  candidate's bounded host canary is active and directly retained. Exact
  generation one and the upstream extra GC root are also retained; no boot link
  exists. Its recorded activation, registration-lifecycle, guarded
  first-registration, and guarded generation-switch failure-injection container
  tests all passed, and the separately guarded live registration was retained
  after repeated postflight and independent console confirmation. The
  marker-only generation-two candidate and guarded switch transaction passed
  only their disposable gate; the host generation-two pilot root must remain
  absent and no live switch is authorized. Read both 2026-09-02 generation-
  switch records before touching them. Do not rerun the one-time registration
  helper, reboot, add boot linkage, switch generations, remove either current
  root, or broaden ownership without a separate plan and authorization. Its
  private wrapper must stay on reviewed Nix 2.35.2, and the closure must contain
  neither Nix 2.34.8 nor real `userborn`. Any derivation change makes that test's
  prior evidence stale.
- Do not run the root-canary helper or any System Manager activation merely to
  complete an audit. The helper is a separately approved disposable-container
  build; host activation additionally requires local recovery, collisions,
  snapshots, timed rollback, retained store closure, and explicit authorization.
- Low-level System Manager activation does not register or GC-root its output.
  The live pilot therefore still requires the documented
  `/nix/var/nix/gcroots/dgx-setup-root-canary-pilot` symlink. The later guarded
  registration added the exact selected profile, generation-one link, and
  `/nix/var/nix/gcroots/system-manager-current` root. Preserve all of them while
  this state is retained; never infer permission to rerun upstream
  `register-profile`, remove registration, or retire the pilot root.
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
