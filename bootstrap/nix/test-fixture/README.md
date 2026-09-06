# Installer test fixture

`hosts.json` is input to the disposable Nix installation/adoption test, not the
live fleet declaration. It preserves the fixture used by the passing installer
lifecycle so selecting desktop applications cannot invalidate that evidence.

Configure real hosts in [fleet/hosts.json](../../../fleet/hosts.json). When
changing the declaration schema or bootstrap behavior, update this fixture as
needed and rerun the installer lifecycle. Do not rewrite observed test hashes
just to make a changed test appear previously validated.
