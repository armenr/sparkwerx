# Tailscale unit lifecycle container test — 2026-09-03

## Result

PASS. The generation-four Tailscale ownership candidate completed the full
disposable lifecycle, and the wrapper verified that the live host stayed on
its exact generation-three configuration with the same running vendor
`tailscaled.service` process.

The command was:

```bash
sudo ./scripts/test-tailscale-unit-lifecycle.sh
```

Its terminal result was:

```text
PASS|tailscale_unit_lifecycle|container handoff/reboot/rollback passed; live host stayed exact
```

## Exact reviewed outputs

| Artifact | Store path |
| --- | --- |
| Production generation-four candidate | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |
| Production candidate derivation | `/nix/store/cdwy32afchjq31dcz0wyw4d7dxb3blf8-system-manager.drv` |
| Disposable lifecycle test | `/nix/store/xljdzkzxj413mzr534rz55lxklk5mfc1-container-test-dgx-tailscale-unit-lifecycle` |
| Disposable lifecycle derivation | `/nix/store/gn1gz9avs0qn9dbbgbs6jhk8p86p8zy4-container-test-dgx-tailscale-unit-lifecycle.drv` |
| Retained live generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Pinned Tailscale package | `/nix/store/cr8z0ckc23p6kxvsyn9wfslqb5sj3m5p-tailscale-1.102.3` |

The generation-four closure is 297.7 MiB recursively versus 230.0 MiB for
generation three. The 67.7 MiB increase is effectively the pinned static
Tailscale package plus the small declarative unit and marker additions.

## Proven lifecycle

The test used two fake daemons inside a disposable Ubuntu systemd-nspawn
container so it could exercise service ownership without contacting a tailnet
or exposing identity data:

1. Install and enable an apt-shaped vendor unit under `/usr/lib/systemd/system`.
2. Create one mutable identity marker under `/var/lib/tailscale`.
3. Activate exact generation three and prove it neither claims nor restarts the
   vendor access plane.
4. Activate the generation-four fixture and perform the single deliberate
   restart into the Nix-owned binary and `/etc` unit.
5. Restart the container and prove the Nix-owned service returns with the same
   identity marker.
6. Activate generation three, prove System Manager stops and removes only its
   own Tailscale unit links, then explicitly start the still-installed vendor
   unit.
7. Restart again and prove the restored vendor service returns with the same
   identity marker.

The root-only wrapper additionally checked the live host immediately before and
after the container run. Its exact retained System Manager generation, vendor
unit path, boot link, daemon PID, start timestamp, active state, and pending
reload state did not change.

## What this does not authorize

No live Tailscale unit was written, reloaded, stopped, restarted, or replaced.
No host generation was registered or activated. The apt package remains the
live rollback source. A separate persistent rollback transaction and local
console gate are required before the first real handoff.
