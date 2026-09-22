# Temporary Moonlight trial preparation

The [private input hardware check](2026-09-07-wayland-input-host.md) passed.
The next step is the [MacBook client trial](../../docs/moonlight-trial.md).

Locally passed:

- launcher, canvas, network-test wrapper, and policy builds;
- 15 controller/configuration/cleanup/privacy CPU tests;
- repository `dev check`: 179 tests, three expected skips, linters, documentation,
  and flake evaluation;
- unchanged store outputs for ordinary Sunshine and the existing startup,
  changing-frame, and private-input diagnostics.

| Artifact | Exact output |
| --- | --- |
| Trial operator | `/nix/store/1fv499s8awizasnkmy3kz4vyp76wfdvz-sparkwerx-moonlight-trial` |
| CPU/package policy | `/nix/store/nw1y7rs5mw2cwv5dmqwwfvg1612va0jf-sparkwerx-moonlight-trial-policy` |
| Pre-launch gate | `/nix/store/j6r24i3p16v76b8l38f95m75mybfdbj6-sparkwerx-moonlight-trial-gate` |
| Container recipe, **not a passed test** | `/nix/store/1yp60a6xa0rxvrs7jvxafikwc4m61fa8-container-test-dgx-moonlight-trial-lifecycle.drv` |

The privileged lifecycle has not run: this agent cannot satisfy sudo's password
prompt. Its container-only fixture and generated test script build, but that is
not evidence of working firewall rules or shutdown. `dgx-moonlight-trial start`
requires the exact lifecycle to pass before starting any real listener.

No live trial, firewall rule, graphics session, root/Home generation change,
Tailscale restart, device ACL change, KMS change, or reboot was performed here.
Read-only host checks still showed generation-five headless, active Tailscale,
factory graphics inactive, systemd running, and no pending protected-unit reload.
Moonlight pairing, transport, actual input delivery, latency, sustained FPS,
and the new canvas's GPU runtime remain untested.
