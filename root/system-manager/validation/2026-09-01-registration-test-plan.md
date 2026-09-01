# System Manager registration lifecycle test — 2026-09-01

## Status

**PASS FOR THE EXACT DISPOSABLE DERIVATION; HOST REMAINS UNREGISTERED.**

This record defines the disposable registration/switching test that passed
before any live generation-registration plan may be proposed for sparkle-01.
The test ran every registration, switch, activation, and deactivation operation
inside its Ubuntu container. It did not run `register-profile` on the host,
create either host registration path, change the retained canary, reload host
systemd, or touch a host service.

## Exact immutable inputs

| Field | Value |
| --- | --- |
| Retained baseline generation | /nix/store/alrczwil6s2ljh1514css13s79rb5fxj-system-manager |
| Disposable second generation | /nix/store/pmrqryvdrws80cg988vvm975v1ygv82q-system-manager |
| Registration-test derivation | /nix/store/m4zm42h6f8dch5mfm6aq6cpjp9jwzk90-container-test-dgx-root-canary-registration.drv |
| Test output | /nix/store/jkl1lsqnvmv5iznk7q70xjk9l6xfvf6j-container-test-dgx-root-canary-registration |
| Test output hash | sha256:0jkwb59zdilvdaadw826wfa6vkjmsj0agd58ns16gywsny1yf2mv |
| Original activation-test derivation | /nix/store/jcrdk9p9lz3qiya2l1021339lsdvyxcg-container-test-dgx-root-canary.drv |
| Repository commit at execution | 759997de70c92147204c120c900f03fca488f859 |
| Read-only verification | 2026-09-01T12:54:16Z |
| Host state before and after | ACTIVE_RETAINED |
| System Manager | 1.1.0 at 05e08c6dd739d7f3204e71322594bb8095334cfb |
| Private Nix | 2.35.2 |
| Host registration performed | No |
| Host activation performed by this work | No |

Evaluation-only flake checks pass. The retained baseline output and original
passing activation-test derivation are unchanged. Before execution, a no-build
dry-run reported eight derivations, all scoped to the second marker, closure
metadata, test script, and disposable test output. After execution, Nix reports
the exact planned output as valid and bound to the exact planned derivation.
The detailed result and independent host postflight are in the
[registration container-test record](2026-09-01-registration-container-test.md).

## Source-level lifecycle facts

Pinned System Manager 1.1.0 performs registration in this order:

1. create the profile directory;
2. run nix-env --profile
   /nix/var/nix/profiles/system-manager-profiles/system-manager --set
   against the candidate;
3. canonicalize the selected profile;
4. remove the existing system-manager-current symlink, if any; and
5. create /nix/var/nix/gcroots/system-manager-current as a direct store link.

That sequence is not transactional. A failure while creating the extra GC root
can leave the Nix profile already advanced. The extra root replacement is also
remove-then-create, not an atomic rename.

The actual Nix profile is the full path ending in system-manager. Its parent
directory is not the profile. Selecting an older Nix profile generation does not
activate it and does not refresh the separate system-manager-current root.
System Manager's deactivation removes managed configuration but does not
unregister the profile, delete generation history, or remove the extra root.
Upstream 1.1.0 explicitly says automatic rollback on failure is not implemented.

These facts mean a fleet switch wrapper must treat profile selection, extra-root
synchronization, and activation as separate checked state transitions.

## Disposable test matrix

The test ran only inside the Ubuntu 24.04 systemd-nspawn build sandbox and
proved:

- a forced regular-file collision at system-manager-current causes
  register-profile to fail after the profile has already been created;
- that partial result is detected and reset only inside the disposable
  container;
- registering generation one creates the profile, generation history, and extra
  root without activating any file or service;
- explicitly activating generation one stays within the existing
  five-path/three-service canary boundary;
- registering generation two advances the profile and extra root but leaves the
  live generation-one state unchanged;
- explicit activation is required to make generation two live;
- selecting generation one with nix-env changes only the profile: generation
  two remains live and the extra root still points to generation two;
- re-registering generation one synchronizes the extra root before explicit
  rollback activation;
- deactivation removes the canary surface and leaves the exact empty version-0
  state while registration history and the extra root remain; and
- protected account/Nix hashes, the unmanaged tmpfiles sentinel, boot linkage,
  PATH hooks, users, wrappers, and all forbidden paths remain untouched.

## Execution gate

The separately authorized helper was:

    sudo ./scripts/test-root-registration.sh

It used the active root-profile Nix with process-local auto-allocate-uids and
cgroups, the local store, and `NIX_USER_CONF_FILES=/dev/null`. It verified the
live host root-manager state immediately before and after the disposable build
and required the state class to be identical.

The invocation realized test-only store paths and completed the exact
root-assisted container builder. Repeating it is not an ordinary audit action:
a changed derivation requires new review and separate authorization. This pass
permits design of a live-registration transaction and rollback; it does not
authorize live registration.

## Stop conditions

Stop and do not register the host if:

- the baseline output or original activation-test derivation changes;
- the new lifecycle derivation changes after a pass;
- the partial-failure behavior differs from the tested rollback assumptions;
- the live host is not the exact retained attempt-3 state;
- either upstream registration path already exists unexpectedly;
- the pilot root is missing or points elsewhere;
- registration would add boot linkage or broader root ownership; or
- rollback cannot restore profile, extra-root, and live activation state as
  three separately verified steps.
