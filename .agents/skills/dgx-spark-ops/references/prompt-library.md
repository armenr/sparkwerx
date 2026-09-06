# Sparkwerx prompt library

[Agent guide](../../../../docs/agent-guide.md) · [Skill](../SKILL.md)

Use `$dgx-spark-ops` in an agent that supports the repository skill.
For another agent, point it to [AGENTS.md](../../../../AGENTS.md) and the
skill file explicitly. Replace angle-bracket placeholders before requesting work.

These prompts describe task scope, not a second approval ritual. Don't copy a
host-mutation prompt when you only want an explanation.

## Resume without guessing

```text
$dgx-spark-ops Orient yourself in Sparkwerx. Read the current status and agent
guide, inspect Git and the appropriate host-status routes, and summarize
what's active, what is only built/planned, and the next useful step.
Make no changes and don't replay historical pilot commands.
```

## Check updates

```text
$dgx-spark-ops Audit this host for updates and drift, read-only. Compare
installed versions, repository pins, stock Nixpkgs, and official releases.
Separate availability from ARM64/GB10 applicability and test evidence.
Don't change locks, install packages, pull images, or restart anything.
```

```text
$dgx-spark-ops Do an offline inventory only. Compare local state with Git,
mark remote release information unknown, and make no changes.
```

## Understand configuration

```text
$dgx-spark-ops Explain this host's declaration and effective package list.
Distinguish schema options from choices supported by the current operators.
Include closure sizes where recorded, service effects, and anything still
manually installed. Do not build or activate anything.
```

## Prepare another Spark

```text
$dgx-spark-ops Prepare a repository-only declaration for <hostname> and
<unix-user>, with Tailscale <enabled-or-disabled>. Check the current UID,
Armen-overlay, package-set, and headless workflow constraints first.
Show the plan and any unsupported choice. Do not apply it or reboot.
```

After reviewing that declaration and the installation/recovery scope:

```text
$dgx-spark-ops Run the reviewed initial setup for this declared host using
./scripts/dgx-setup converge. I authorize its documented Nix, optional
Tailscale, root/headless, and Home transitions with their rollback guards.
Independent console access is available. Stop at the separate reboot
checkpoint; this request does not authorize reboot or workload deployment.
```

## Review or implement an update

```text
$dgx-spark-ops Plan an update of <component> to <version>. Verify the source,
ARM64 support, current adapter/stock-package comparison, affected layer,
downloads, tests, activation procedure, and rollback. Make no changes.
```

```text
$dgx-spark-ops Implement the reviewed repository update for <component>.
Update only its approved pins/configuration and documentation, build the
agreed candidates with no activation, and run the relevant tests.
Keep the frozen root lane unchanged. Report anything blocking deployment.
```

## Check Tailscale ownership

```text
$dgx-spark-ops Audit Tailscale and SSH without changing them. Check the
pinned/running versions, loaded service owner, sanitized health, identity
continuity verdict, and SSH setting. Explain whether the direct package
adapter is still needed. Keep apt fallback and never print private node,
tailnet, preference, or credential data.
```

## Work on desktops or AI applications

```text
$dgx-spark-ops Plan <current-mode> to <target-mode>. Inspect what the operator
actually supports before proposing commands. Include GDM, Dashboard GUI
versus Admin, Tailscale, GPU/portal checks, session interruption, and recovery.
Do not switch the host or disable security protections.
```

```text
$dgx-spark-ops Design the selected <workload> from its official Spark playbook.
Choose Nix, an ARM64 container digest, or a pinned source build as appropriate.
Document all downloads, storage, models, ports, secrets, health checks, and
rollback. Do not pull, build, start, or expose the workload yet.
```

## Investigate a failure

```text
$dgx-spark-ops Diagnose the attached failure. Start with the correct
lifecycle's current status and any active rollback deadline. Distinguish a
real fault from a stale verifier or historical precondition. Make no changes;
give the exact repair or recovery step and why it is appropriate.
```

## Hand off cleanly

```text
$dgx-spark-ops Capture this session's verified changes, commit, tests, host
state, remaining work, and next command in the appropriate documentation.
Don't invent a new test pass. Flag any worker or rollback deadline that needs
attention, and keep private snapshots and credentials out of the handoff.
```
