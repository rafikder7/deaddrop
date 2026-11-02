FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8

# Runtime for Rumor Mill #3: sshd, git (dangling-blob recovery), gnupg
# (symmetric dead drop), sudo (the archive helper), plus the audit tools the
# verifier needs (getcap/getfacl/lsattr).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        openssh-server \
        openssl \
        git \
        gnupg \
        sudo \
        acl \
        attr \
        libcap2-bin \
        libpam-modules \
        libpam-modules-bin \
        coreutils \
        bash \
        grep \
        sed \
        findutils \
        tar \
        procps \
        util-linux \
        passwd \
        login \
        tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

RUN ln -sf /usr/share/zoneinfo/UTC /etc/localtime \
 && printf 'UTC\n' > /etc/timezone \
 && mkdir -p /run/sshd /var/run/faillock /var/mail /srv/archive /srv/backups \
            /etc/rumor-mill \
 && chmod 700 /var/run/faillock /etc/rumor-mill /srv/backups \
 && chmod 755 /var/mail \
 && chmod 750 /srv/archive

COPY sshd_config  /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
COPY verify.sh     /verify.sh
# Private-repo standalone build: the flag is baked root-only (0600). CI builds
# inject FLAG instead and never use this file.
COPY flag.secret   /etc/rumor-mill/flag

RUN chmod 700 /entrypoint.sh /verify.sh \
 && chmod 600 /etc/rumor-mill/flag \
 && chown root:root /etc/rumor-mill/flag \
 && rm -rf /etc/update-motd.d/* /etc/legal \
 && ssh-keygen -A

EXPOSE 2222

ENTRYPOINT ["/entrypoint.sh"]
