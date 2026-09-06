# Inventory policy

Inventory committed to this repository is intentionally sanitized. It may
contain hostnames and software versions, but must not contain:

- serial numbers or device UUIDs;
- MAC or IP addresses;
- usernames other than those intentionally used by the configuration;
- environment variables, tokens, cookies, credentials, or SSH material;
- complete logs or process command lines;
- Tailscale node names, IP addresses, machine/node IDs, tailnet membership,
  unfiltered status/preferences, auth keys, or policy contents;
- 1Password item names or secret references.

Use `scripts/collect-baseline.sh` to print the selected JSON inventory reviewed by
this project. Raw diagnostic bundles belong outside Git.

Keep the original dated baseline intact. Record later approved host changes as
separate sanitized checkpoints, such as
[`sparkle-01`'s Nix 2.35.2 activation](sparkle-01/2026-08-23-nix-2.35.2.md).
