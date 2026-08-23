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
  overlays, root module, test, state, registration, or activation. The candidate
  is built but inactive/unregistered; its private wrapper must stay on reviewed
  Nix 2.35.2, and the closure must contain neither Nix 2.34.8 nor real
  `userborn`.
- Do not run the root-canary helper or any System Manager activation merely to
  complete an audit. The helper is a separately approved disposable-container
  build; host activation additionally requires local recovery, collisions,
  snapshots, timed rollback, and explicit authorization.
- Validate on `aarch64-linux` and pilot on one host before fleet rollout.

Follow the skill's routed references rather than duplicating update policy in
ad hoc instructions.
