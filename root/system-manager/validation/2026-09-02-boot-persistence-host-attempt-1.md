# Retained System Manager generation three — host attempt 1

Date: 2026-09-02

Status: **generation three retained, registered, selected, live, and
boot-linked; rollback disarmed; generations one and two retained; host not
rebooted**

## Authority and exact inputs

Armen created the private snapshot
`inventory/sparkle-01/raw/system-manager-boot-persistence/20260902T110421Z`,
verified the independent local console, and explicitly authorized that exact
snapshot:

> I verified the local console and authorize System Manager generation-three
> boot-persistence activation using snapshot 20260902T110421Z. I understand
> this does not authorize reboot.

The clean repository authority was commit
`2e58f537e92ef0522fb0b9e8748de192fb62d230`. The reviewed inputs were:

| Input | Exact value |
| --- | --- |
| Generation one | `/nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager` |
| Generation two | `/nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager` |
| Generation three | `/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager` |
| Transaction SHA-256 | `53eb8c4d03a4c24764f519e358f3c5c813e66f189efc07e50f82cd19841d8288` |
| Passed transaction test | `/nix/store/i5skjqyw16qgbvb4azr68msrqfz64d7k-container-test-dgx-root-canary-boot-persistence-transaction.drv` |
| Passed test output | `/nix/store/d3ymf91l07rvai5pzz9ygj3vl3g9xss3-container-test-dgx-root-canary-boot-persistence-transaction` |
| Passed output hash | `sha256:0lxm3pjsd4yy9zl49zx6cbydc9iid1i7mdrajkinkfzszg5k7ikn` |
| Snapshot helper SHA-256 | `bb726566b5e11ed466aaab0ab7ab12e3f40f7f93af4561767bfbdb500f4640ff` |
| Activation wrapper SHA-256 | `464f2b8283fbed336722ae96ee3786d3188b1cfba09f588974dd9381b8a58e70` |

The snapshot helper reported exact registered/live no-boot generation two,
generation three absent from the profile and host roots, and the boot edge
absent. It performed no retention, registration, activation, boot-link,
daemon-reload, reboot, or service operation. The private snapshot remains
root-owned, mode `0700`, untracked, and is not reproduced here.

## Execution and rollback evidence

The live state changed at `2026-09-02T11:16:42Z`. The system journal records
the exact transient rollback timer starting at `11:16:42.043511Z` and stopping
successfully at `11:16:50.041999Z`. No start or execution of
`dgx-root-boot-persistence-rollback.service` occurred. Later read-only
inspection found both transient units unloaded and inactive.

The wrapper can stop that timer only after all of these gates complete:

- exact generation-three registration, selection, upstream rooting, and
  activation;
- exact six-path/three-service state and boot-edge verification;
- unchanged snapshot hashes for `/etc/nix/nix.conf`, passwd, group, and shadow;
- unchanged protected unit fragments, PIDs, and active-enter timestamps;
- healthy systemd, GPU, and sanitized Tailscale/Tailscale SSH state;
- exact `KEEP GENERATION THREE` after local-console verification; and
- the same complete postflight repeated before timer disarm.

Armen reported the guarded command complete as `done`; its terminal transcript
was not pasted into this repository session. The retained exact state plus the
stopped, unloaded rollback timer is compatible only with the reviewed wrapper's
successful confirmation path. This record preserves that code-and-state
inference instead of inventing verbatim wrapper output.

## Independent direct observation

A read-only audit beginning at `2026-09-02T11:23:23Z` observed:

- `system-manager -> system-manager-3-link`;
- exact `system-manager-{1,2,3}-link` entries pointing directly to generations
  one, two, and three;
- `system-manager-current ->` exact generation three;
- all three dedicated pilot roots pointing directly to their exact candidates;
- version-1 state with exactly six managed paths and the same three service
  keys, SHA-256
  `513bc468705ed5322cd50e734172621c5b87aef59af805682ef9ae5f70d5fba8`;
- all five original canary/control links plus the one exact
  `default.target.wants/system-manager.target` edge resolving to reviewed Nix
  store payloads;
- canary markers `registration-test-generation=2` and
  `boot-persistence-generation=3`;
- every forbidden PATH, wrapper, userborn, and `/run/current-system` path
  absent; and
- the extended repository classifier returning
  `ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED`.

Systemd was `running` with zero failed units. All seven protected
factory/access services were active from their original fragments with no
pending daemon reload: `nix-daemon`, `tailscaled`, `gdm`, `docker`,
`dgx-dashboard`, `dgx-dashboard-admin`, and `nvidia-persistenced`. The three
managed units were active with no pending reload. The GPU reported `NVIDIA
GB10`, driver `580.173.02`, P8, and 35 C. Sanitized Tailscale state remained
`backend=Running;online=true;WantRunning=true;RunSSH=true`.

The host boot time remained `2026-09-01 13:08:38 +04`, proving this activation
did not reboot the machine. The unchanged active-enter times for the existing
managed target/service are expected because generations two and three have
byte-identical service definitions; the activation changed tracked `/etc`
state and the boot edge without restarting those already-active units.

## Retained boundary

The host is now declaratively boot-linked, but real-host boot recovery has not
been tested. The container's two restart proofs validate the mechanism only;
they are not a substitute for a guarded `sparkle-01` reboot.

Snapshot `20260902T110421Z` is spent. Do not rerun either boot-persistence
snapshot/activation helper against this post-state. Do not reboot, invoke
rollback, remove any generation or pilot root, change the selected profile,
remove the boot edge, broaden System Manager ownership, migrate Tailscale, or
switch desktop mode without the next exact plan and authorization. A first
real reboot still requires recovery that survives reboot, a fresh snapshot,
physical-console availability, explicit reboot authorization, and post-boot
classification.
