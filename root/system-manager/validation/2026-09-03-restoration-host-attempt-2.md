# Generation-three restoration host attempt 2

Date: 2026-09-03 UTC

Host: `sparkle-01`

Result: generation three restored, verified, and retained

## Attempt

The retry-safe restoration used private snapshot `20260903T083058Z` and the
hash-pinned helper from repository commit
`1a191e246cbfacbff9946887f7b2b594b4486ff3`. The helper verified the exact
registered/live no-boot generation-two pre-state, snapshot completeness and
checksums, protected services, GPU health, and sanitized Tailscale SSH health.
After the operator independently checked the local console and pressed Enter,
it armed the ten-minute exact generation-two rollback before mutation.

After arming, the same exact resume validator confirmed the in-flight timer and
snapshot binding. At `2026-09-03T08:31:04Z`, the transaction registered
generation three, selected and upstream-rooted it, activated its exact
six-path/three-service canary, and restored the declarative boot edge.
Generations one and two and all three direct pilot roots remained retained. The
helper then completed two full automatic postflights. Both found systemd
running with no failed units, the NVIDIA GB10 healthy, Tailscale running/online
with SSH enabled, protected services unchanged, and exact generation three
live and boot-linked.

Only after both postflights passed did the helper disarm the transient
generation-two rollback. Its rollback service did not run. No reboot was
performed or authorized by the restoration.

## Independent verification

At `2026-09-03T08:35:31Z`, the repository classifier independently returned:

```text
ACTIVE_REGISTERED_GENERATION_THREE_BOOT_LINKED_RETAINED
```

The selected profile, numbered generation-three link, upstream root, and
generation-three direct pilot root all resolved to
`/nix/store/w8kn2idc0ix6x1024qphv2fvmaf664d7-system-manager`. Numbered
generations one and two and their direct pilot roots still resolved to their
exact candidates. The one declarative `default.target` boot edge was present.
The persistent recovery units and transient restoration rollback units were
all unloaded/inactive. Systemd remained `running` with zero failed units; the
GPU reported `NVIDIA GB10, 580.173.02, P8, 35`; sanitized Tailscale state was
`backend=Running;online=true;WantRunning=true;RunSSH=true`.

This record supersedes attempt 1 as current live-state authority. Attempt 1
remains historical proof that a missed retention confirmation safely rolled
back. Both private snapshots are spent transaction evidence and must not be
reused manually.
