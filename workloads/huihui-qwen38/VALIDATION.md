# First live API validation, 2026-09-25

The exact image/model pins and settings in [README](README.md) started on
spark-9667 through native NVIDIA CDI. BF16 weights loaded in approximately
353 seconds and occupied 51.1 GiB according to vLLM. Startup and compilation
completed; the container's health check passed. The API advertises the original
Hugging Face model identifier and a 131,072-token maximum.

The committed `probe.py --thinking` passed:

- unauthenticated model discovery rejected with 401;
- authenticated discovery advertised the expected model;
- ten auto-choice tool calls, five JSON and five streaming, including escaped
  URLs and query strings; all had the expected function, call ID, arguments,
  and finish reason;
- a synthetic tool-result round trip;
- a no-tool arithmetic response; and
- thinking-enabled tool extraction.

The ten short tool requests took approximately 6.9–8.4 seconds each. This is
a small integration sample, not a throughput or agent reliability benchmark.
No actual remote web fetch was performed.

Authenticated discovery worked from the owner's computer over both LAN and
Tailscale; both rejected unauthenticated requests. Docker's actual publication
matched the private configuration: localhost, LAN IPv4, and Tailscale IPv4 on
port 8000, without wildcard or IPv6 publication. Credentials and tailnet
inventory were excluded from output and Git.

GDM, native Tailscale, OpenSSH, and Docker remained active. A post-probe memory
sample showed roughly 30 GiB available of 121 GiB total, with 32 MiB swap used;
that sample included the disposable workstation validation container.

Limits: full-length context, image/video input, concurrent requests, model
restart/cold-boot behavior, and RedFang integration are not validated here.
Automatic restart remains disabled. The OS, driver and network services were
not reconfigured to launch this workload.
