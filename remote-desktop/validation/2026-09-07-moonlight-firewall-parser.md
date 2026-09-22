# Moonlight trial firewall parser fix

The first `start 4k60` attempt at `41db5d0` stopped in the disposable
container's JSON firewall check. The failed recipe was
`/nix/store/1yp60a6xa0rxvrs7jvxafikwc4m61fa8-container-test-dgx-moonlight-trial-lifecycle.drv`.
The gate reported that no live trial launched; the real trial services,
runtime directory, retention root, and private trial history remained absent.

## Cause and correction

The generated rule used `{"counter": {}}`. Both the pinned nftables 1.1.6
parser and the factory parser rejected it with `Invalid counter reference`.
Anonymous counters now explicitly start with zero packets and bytes. Rule
comparison ignores those changing counts but still rejects a named counter,
unexpected properties, or a changed verdict.

The install path and parser test now share one batch generator. A new
unprivileged regression runs the exact pinned `nft --check --json` parser:
the old empty counter must fail parsing, while the corrected batch must reach
only the expected kernel-cache permission error. This checks parsing, not
packet behavior. [`--check` does not apply rules](https://netfilter.org/projects/nftables/manpage.html).
The full privileged network/lifecycle gate remains mandatory.

The network fixture now includes nftables' actual error in a failed test.
That diagnostic route refuses the initial network namespace and only invokes
the fixture's firewall tool. The live controller still suppresses raw command
output; no host address, pairing, or authentication logging was enabled.

## Verification

- All 20 targeted controller/parser/privacy tests passed, including inside the
  Nix policy build with the pinned nftables executable and no skipped tests.
- `./scripts/dev check` passed: 184 tests, three expected skips, lint,
  documentation checks, and flake evaluation.
- The corrected trial, policy, network-test wrapper, and pre-launch gate built.
- The existing Sunshine, startup, changing-frame, private-input, and headless
  root outputs stayed exact. No dependency pin changed.

| Artifact | Corrected output |
| --- | --- |
| Trial | `/nix/store/bkqrdd8a9y1f0x9jrzas4spy4nxd0p8b-sparkwerx-moonlight-trial` |
| Policy | `/nix/store/s4bhlnni3pbd7abvyq44scbn8qnhwhjm-sparkwerx-moonlight-trial-policy` |
| Network test | `/nix/store/qc71xlxhjs0gnd2rfp1rdnji3jy86ah5-sparkwerx-moonlight-trial-network-test` |
| Pre-launch gate | `/nix/store/85axim0azsbbqdl9q0ys4p0j0nkbss9d-sparkwerx-moonlight-trial-gate` |
| Container recipe, not yet passed | `/nix/store/jgl38lpjc49qa96byscqdg2wyb6nbrv6-container-test-dgx-moonlight-trial-lifecycle.drv` |

The corrected privileged lifecycle needs the operator's sudo prompt. Use the
same [trial launcher](../../docs/moonlight-trial.md); it cannot start the live
session unless that exact test passes. No firewall reset, service restart,
desktop switch, KMS change, or reboot is needed for this correction.
