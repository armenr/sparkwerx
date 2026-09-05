# Generation-four to headless transaction container test — 2026-09-05

> **Superseded as live authority.** The first host attempt exposed that this
> fixture omitted the factory `dgx-dashboard.service`/`default.target`
> relationship. Preserve this as historical evidence; require a corrected
> Dashboard-aware rerun after the
> [host attempt](2026-09-05-host-attempt-1.md).
> That corrected rerun has now passed; use the
> [current Dashboard-aware stack record](2026-09-05-dashboard-aware-stack.md).

## Result

**PASS** for the exact guarded transaction primitive. The root-assisted wrapper
verified exact live generation four before and after the build. Registration,
activation, target isolation, injected failures, and rollback occurred only in
the disposable container.

```text
PASS|desktop_headless_transaction|failure injection, exact headless switch, idempotent factory rollback, and host non-mutation passed
```

## Exact artifacts

| Field | Value |
| --- | --- |
| Repository commit | `71bd7c409909b9be514321ac99a030cf2d536651` |
| Verified at | `2026-09-05T11:55:21Z` |
| Transaction SHA-256 | `6b62ba0ee094d664ffa059c43cf1da87f39b2790ed0d93708ad9ec0432a60fe4` |
| Test derivation | `/nix/store/z6nh3w3lv0rqk743b4v6b197q99hrgx3-container-test-dgx-desktop-headless-transaction.drv` |
| Test output | `/nix/store/i82zf8kndgzxszcdmnlncyma2sbb5aj6-container-test-dgx-desktop-headless-transaction` |
| Output SRI hash | `sha256-Qalko8rM9ETfGwKnvE3MO8ITgYKDTJXI36B0qVhfS6k=` |
| Output Nix-base32 hash | `sha256:1aabbxcajx50vz49ak43ha0i7hivri6vr9q23ggl9x6crain9aa1` |
| Live generation | `/nix/store/vjw778sf95r42a1zbivlk8z4p45y7qhx-system-manager` |
| Headless candidate | `/nix/store/20qw0af0jwfqi5spgg3b1nrc0yydhlc1-system-manager` |
| Live-host mutation | None |

## Proved cases

All twelve named subtests completed:

1. unretained headless candidate refusal;
2. exact generation-four factory pre-state verification;
3. unknown profile-entry refusal;
4. safe reconciliation after upstream partial registration and foreign-root
   collision;
5. rollback after injected post-registration failure;
6. rollback after injected post-activation failure;
7. rollback after injected post-isolation failure;
8. successful exact generation-five headless transaction;
9. duplicate-apply refusal without mutation;
10. foreign-root preservation during rollback refusal;
11. idempotent exact rollback to factory GNOME; and
12. exact retention roots, Tailscale process, and protected-file preservation.

## Authority boundary

This PASS selects the transaction primitive as an input to the live operator.
It does not authorize retaining the host candidate, registering generation
five, activating it, isolating a target, stopping GDM, or rebooting the host.
The live operator still requires a private snapshot and persistent timed
generation-four rollback installed before mutation, plus its own disposable
lifecycle.
