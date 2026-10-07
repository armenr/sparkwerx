ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE}
ENV container=docker
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo curl ca-certificates python3 git xz-utils procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && useradd --create-home --uid 1000 --shell /bin/bash deadspark \
    && echo 'deadspark ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/test-user \
    && chmod 0440 /etc/sudoers.d/test-user \
    && systemctl set-default multi-user.target
COPY init.sh /test-init
COPY lifecycle.py /test-lifecycle.py
STOPSIGNAL SIGRTMIN+3
CMD ["bash", "/test-init"]
