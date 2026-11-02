#!/usr/bin/env bash
###############################################################################
# entrypoint.sh — Rumor Mill #3 — Dead Drop
# Creates users, mail spool, the encrypted dead drop, the dotfiles repo, the
# archive helper, and hardening at CONTAINER START.
# The plaintext flag never appears in this script or in any world-readable file.
###############################################################################
set -euo pipefail

# --------------------------------------------------------------------------
# CI injects FLAG. Stage it root-only, then re-exec with a clean environment
# so the secret never remains in PID 1's /proc/1/environ.
# --------------------------------------------------------------------------
if [ -n "${FLAG:-}" ]; then
    umask 077
    printf '%s\n' "$FLAG" > /run/rumor-flag
    chmod 600 /run/rumor-flag
    unset FLAG
    exec env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        HOME=/root \
        SSH_PORT="${SSH_PORT:-2222}" \
        /entrypoint.sh
fi

SSH_PORT="${SSH_PORT:-2222}"

# Credentials used by the intended chain.
N0D4_PW='M4ilb0x_1962_v3'
BOUL_PW='d34d_dr0p_4cc3ss'
DROP_PW='g1t_k33ps_wh4t_y0u_thr0w_4w4y'
DECOY_FLAG='ingehack{th1s_1s_4_f4k3_fl4g}'

###############################################################################
# 0. RESOLVE THE REAL FLAG (staged CI value or root-only baked file)
###############################################################################
flag_content=""
if [ -r /run/rumor-flag ]; then
    flag_content="$(cat /run/rumor-flag)"
    rm -f /run/rumor-flag
elif [ -r /etc/rumor-mill/flag ]; then
    flag_content="$(cat /etc/rumor-mill/flag)"
fi
if [ -z "$flag_content" ]; then
    echo "FATAL: no flag supplied (set FLAG or bake /etc/rumor-mill/flag)" >&2
    exit 1
fi

# Persist a root-only copy for the verifier. Never world-readable.
mkdir -p /etc/rumor-mill
printf '%s\n' "$flag_content" > /etc/rumor-mill/flag
chown root:root /etc/rumor-mill/flag
chmod 600 /etc/rumor-mill/flag

###############################################################################
# 1. CREATE USERS (empty GECOS, own group, bash shell)
###############################################################################
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    if ! id "$u" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -c '' "$u"
    fi
    usermod -c '' "$u"
    chown "$u:$u" "/home/$u"
    chmod 700 "/home/$u"
done

###############################################################################
# 2. SET PASSWORDS
###############################################################################
printf '%s\n' \
    'y4ss1n3:Welcome123' \
    "n0d4:${N0D4_PW}" \
    "boul3h14:${BOUL_PW}" | chpasswd

# gh3nj4's password is generated at container start so it never lands in an
# image layer. Stored only in a root-only file.
if [ ! -s /root/gh3nj4_password.txt ]; then
    umask 077
    { head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32; printf '\n'; } \
        > /root/gh3nj4_password.txt
fi
chown root:root /root/gh3nj4_password.txt
chmod 600 /root/gh3nj4_password.txt
GH3NJ4_PW="$(cat /root/gh3nj4_password.txt)"
printf '%s\n' "gh3nj4:${GH3NJ4_PW}" | chpasswd

###############################################################################
# 3. REMOVE USERS FROM DANGEROUS GROUPS
###############################################################################
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    for g in sudo wheel adm disk shadow docker lxd; do
        gpasswd -d "$u" "$g" >/dev/null 2>&1 || true
    done
done

###############################################################################
# 4. y4ss1n3's mailbox: the rumor thread that leaks n0d4's password halves
###############################################################################
mkdir -p /var/mail
chown root:root /var/mail
chmod 755 /var/mail

cat > /var/mail/y4ss1n3 << 'MAIL_EOF'
From n0d4@rumor-mill.local Mon Nov  2 10:02:11 2026
Date: Mon, 2 Nov 2026 10:02:11 +0000
From: n0d4 <n0d4@rumor-mill.local>
To: y4ss1n3 <y4ss1n3@rumor-mill.local>
Subject: rotating the handover (again)

Rotated it again after the last leak.

First half, before the underscore:  M4ilb0x

Rest comes in the follow-up. Do not reply to this address — every thread I
start gets answered by someone who is not me.

-- n0d4

From gh3nj4@rumor-mill.local Mon Nov  2 10:04:52 2026
Date: Mon, 2 Nov 2026 10:04:52 +0000
From: gh3nj4 <gh3nj4@rumor-mill.local>
To: y4ss1n3 <y4ss1n3@rumor-mill.local>
Subject: Re: rotating the handover (again)

Ignore that. The real one is n0p3_n0p3_n0p3, he told me himself.
Two halves is just him being paranoid again.

-- g

From n0d4@rumor-mill.local Mon Nov  2 10:07:33 2026
Date: Mon, 2 Nov 2026 10:07:33 +0000
From: n0d4 <n0d4@rumor-mill.local>
To: y4ss1n3 <y4ss1n3@rumor-mill.local>
Subject: Re: rotating the handover (again)

Second half:  _1962_v3

Mailbox is getting noisy. Someone keeps answering my threads with nonsense.
Do not trust a word of it.

-- n0d4
MAIL_EOF

chown y4ss1n3:y4ss1n3 /var/mail/y4ss1n3
chmod 600 /var/mail/y4ss1n3

###############################################################################
# 5. n0d4's home: the encrypted dead drop + a repo that remembers too much
###############################################################################
cat > /home/n0d4/note.txt << 'N0D4_NOTE'
The drop is passphrase-protected. I put the passphrase in the dotfiles repo
and then rewrote history so it is not in `git log` any more.

Git keeps what you throw away.

Decrypt with (the pinentry dialog does not work over this sshd, so pass the
passphrase directly):

    gpg --batch --pinentry-mode loopback --passphrase '<passphrase>' \
        --decrypt dead-drop.gpg
N0D4_NOTE

chown n0d4:n0d4 /home/n0d4/note.txt
chmod 600 /home/n0d4/note.txt

# Build the plaintext drop as root, encrypt it as n0d4, then remove the
# plaintext. The drop names boul3h14's password and the archive helper.
DROP_PLAIN='/tmp/.drop-plain'
umask 077
cat > "$DROP_PLAIN" << DROP_EOF
boul3h14 / ${BOUL_PW}

He keeps /srv/archive tidy with a root helper. It trusts whatever it finds
in the directory, and it does not ask him for a password.
DROP_EOF
chmod 600 "$DROP_PLAIN"
chown n0d4:n0d4 "$DROP_PLAIN"

install -d -o n0d4 -g n0d4 -m 700 /home/n0d4/.gnupg
runuser -u n0d4 -- env GNUPGHOME=/home/n0d4/.gnupg \
    gpg --batch --yes --quiet --no-permission-warning \
        --pinentry-mode loopback --passphrase "$DROP_PW" \
        --symmetric --cipher-algo AES256 \
        -o /home/n0d4/dead-drop.gpg "$DROP_PLAIN" >/dev/null 2>&1
rm -f "$DROP_PLAIN"

chown n0d4:n0d4 /home/n0d4/dead-drop.gpg
chmod 600 /home/n0d4/dead-drop.gpg

# A small dotfiles repo. The passphrase is committed, then amended out of
# history — the commit and blob survive as dangling objects.
REPO=/home/n0d4/.local/share/rumor-dotfiles
install -d -o n0d4 -g n0d4 -m 700 /home/n0d4/.local
install -d -o n0d4 -g n0d4 -m 700 /home/n0d4/.local/share
rm -rf "$REPO"
runuser -u n0d4 -- git init -q -b main "$REPO"
runuser -u n0d4 -- git -C "$REPO" config user.name 'n0d4'
runuser -u n0d4 -- git -C "$REPO" config user.email 'n0d4@rumor-mill.local'

cat > "$REPO/bashrc" << 'BASHRC_EOF'
set -o vi
export EDITOR=vim
alias ll='ls -la'
BASHRC_EOF
chown n0d4:n0d4 "$REPO/bashrc"
runuser -u n0d4 -- git -C "$REPO" add -A
runuser -u n0d4 -- git -C "$REPO" commit -qm 'dotfiles: vim bindings'

cat > "$REPO/env.local" << DROPENV_EOF
# local only, do not commit
DROP_PASSPHRASE=${DROP_PW}
DROPENV_EOF
chown n0d4:n0d4 "$REPO/env.local"
runuser -u n0d4 -- git -C "$REPO" add -A
runuser -u n0d4 -- git -C "$REPO" commit -qm 'dotfiles: local env'

# Rewrite it away. The commit and its blob stay dangling until gc prunes them.
runuser -u n0d4 -- git -C "$REPO" reset -q --hard HEAD~1

###############################################################################
# 6. boul3h14's home + the root archive helper (the privesc)
###############################################################################
cat > /home/boul3h14/README << 'BOUL_EOF'
I keep /srv/archive clean with the root helper. It is the only thing I am
allowed to run as root:

    sudo -l
    sudo /usr/local/bin/rumor-archive

The directory is mine to fill. The helper trusts it.

Nothing else here. The drop is not in this home.
BOUL_EOF
chown boul3h14:boul3h14 /home/boul3h14/README
chmod 600 /home/boul3h14/README

mkdir -p /srv/archive /srv/backups
chown boul3h14:boul3h14 /srv/archive
chmod 750 /srv/archive
chown root:root /srv/backups
chmod 700 /srv/backups
rm -rf /srv/archive/* /srv/backups/*

cat > /usr/local/bin/rumor-archive << 'ARCHIVE_EOF'
#!/bin/sh
# Rumor Mill #3 — archive helper (runs as root via sudo).
set -e
cd /srv/archive
exec /bin/tar czf "/srv/backups/rumor-$(date +%s).tgz" *
ARCHIVE_EOF
chown root:root /usr/local/bin/rumor-archive
chmod 755 /usr/local/bin/rumor-archive

cat > /etc/sudoers.d/30-rumor-archive << 'SUDO_EOF'
# Rumor Mill #3 — the archive helper is the only root command boul3h14 may run.
boul3h14 ALL=(root) NOPASSWD: /usr/local/bin/rumor-archive
SUDO_EOF
chown root:root /etc/sudoers.d/30-rumor-archive
chmod 440 /etc/sudoers.d/30-rumor-archive
if ! visudo -cf /etc/sudoers >/dev/null 2>&1; then
    echo "FATAL: sudoers became invalid" >&2
    exit 1
fi

###############################################################################
# 7. root's dead drop: the real flag
###############################################################################
install -d -o root -g root -m 700 /root/dead-drop
printf '%s\n' "$flag_content" > /root/dead-drop/flag.txt
chown root:root /root/dead-drop/flag.txt
chmod 600 /root/dead-drop/flag.txt

###############################################################################
# 8. gh3nj4's home: decoy flag
###############################################################################
printf '%s' "$DECOY_FLAG" > /home/gh3nj4/flag.txt
chown gh3nj4:gh3nj4 /home/gh3nj4/flag.txt
chmod 600 /home/gh3nj4/flag.txt

###############################################################################
# 9. VERIFY THE CHAIN (as its real users, no root shortcuts)
###############################################################################
DECRYPTED="$(runuser -u n0d4 -- env GNUPGHOME=/home/n0d4/.gnupg \
    gpg --batch --quiet --no-permission-warning \
        --pinentry-mode loopback --passphrase "$DROP_PW" \
        --decrypt /home/n0d4/dead-drop.gpg 2>/dev/null || true)"
case "$DECRYPTED" in
    *"$BOUL_PW"*) : ;;
    *) echo "FATAL: dead drop does not decrypt to boul3h14's password" >&2; exit 1 ;;
esac

DANGLING="$(runuser -u n0d4 -- git -C "$REPO" fsck --lost-found 2>/dev/null \
    | grep -c 'dangling' || true)"
if [ "${DANGLING:-0}" -lt 1 ]; then
    echo "FATAL: dotfiles repo has no dangling objects" >&2
    exit 1
fi

SUDO_RULES="$(runuser -u boul3h14 -- sudo -n -l 2>/dev/null || true)"
case "$SUDO_RULES" in
    *"/usr/local/bin/rumor-archive"*) : ;;
    *) echo "FATAL: boul3h14 cannot run the archive helper" >&2; exit 1 ;;
esac

echo "[entrypoint] chain verified OK"

###############################################################################
# 10. HARDENING
###############################################################################

# H1: home directories
chmod 711 /home
chown root:root /home
chmod 700 /home/y4ss1n3 /home/n0d4 /home/boul3h14 /home/gh3nj4

# H2: every file under /home is 0600
find /home -type f -exec chmod 600 {} +

# H4: no sudoers drop-ins for challenge users (the archive rule is the only one)
find /etc/sudoers.d -maxdepth 1 -type f ! -name '30-rumor-archive' \
    -exec grep -lE 'y4ss1n3|n0d4|boul3h14|gh3nj4' {} \; 2>/dev/null \
    | while read -r f; do rm -f "$f"; done || true

# H5: pam_faillock (preauth + authfail + authsucc; account lockout)
mkdir -p /var/run/faillock
chown root:root /var/run/faillock
chmod 700 /var/run/faillock
cat > /etc/security/faillock.conf << 'FAILLOCK_EOF'
dir = /var/run/faillock
deny = 5
unlock_time = 900
fail_interval = 900
FAILLOCK_EOF

cat > /etc/pam.d/su << 'SU_PAM_EOF'
# Rumor Mill #3 — su with faillock
auth       sufficient   pam_rootok.so
auth       required     pam_faillock.so preauth
auth       [success=1 default=ignore] pam_unix.so nullok
auth       [default=die] pam_faillock.so authfail
auth       sufficient   pam_faillock.so authsucc
account    required     pam_faillock.so
account    required     pam_unix.so
session    required     pam_unix.so
password   required     pam_unix.so
SU_PAM_EOF

cat > /etc/pam.d/sshd << 'SSHD_PAM_EOF'
# Rumor Mill #3 — sshd with faillock (pam_motd omitted: it writes a 0644
# ~/.cache/motd.legal-displayed into a home on every login).
auth       required     pam_faillock.so preauth
auth       [success=1 default=ignore] pam_unix.so nullok
auth       [default=die] pam_faillock.so authfail
auth       sufficient   pam_faillock.so authsucc
account    required     pam_faillock.so
account    required     pam_unix.so
session    required     pam_unix.so
session    required     pam_loginuid.so
session    optional     pam_keyinit.so force revoke
password   required     pam_unix.so
SSHD_PAM_EOF

cat > /etc/pam.d/login << 'LOGIN_PAM_EOF'
# Rumor Mill #3 — console login with faillock
auth       required     pam_faillock.so preauth
auth       required     pam_securetty.so
auth       [success=1 default=ignore] pam_unix.so nullok
auth       [default=die] pam_faillock.so authfail
auth       sufficient   pam_faillock.so authsucc
account    required     pam_faillock.so
account    required     pam_unix.so
session    required     pam_unix.so
session    required     pam_loginuid.so
session    optional     pam_lastlog.so
password   required     pam_unix.so
LOGIN_PAM_EOF

chown root:root /etc/pam.d/su /etc/pam.d/sshd /etc/pam.d/login
chmod 644 /etc/pam.d/su /etc/pam.d/sshd /etc/pam.d/login

# H12: GECOS already cleared; re-assert
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    usermod -c '' "$u"
done

# H13: /etc/shadow
chmod 640 /etc/shadow
chown root:shadow /etc/shadow

# H14: sshd_config (port is templated)
sed -i "s/^Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
ssh-keygen -A >/dev/null 2>&1 || true
mkdir -p /run/sshd
chmod 755 /run/sshd

# H15: banners
printf 'Authorized access only.\n' > /etc/issue
printf 'Authorized access only.\n' > /etc/issue.net
printf 'Authorized access only.\n' > /etc/motd
rm -rf /etc/update-motd.d/* /etc/legal

# H17/H18: best-effort process and kernel hardening
mount -o remount,hidepid=2 /proc 2>/dev/null || true
for sc in \
    "kernel.yama.ptrace_scope=3" \
    "kernel.kptr_restrict=2" \
    "kernel.dmesg_restrict=1" \
    "kernel.kexec_load_disabled=1" \
    "kernel.unprivileged_bpf_disabled=1"; do
    sysctl -w "$sc" >/dev/null 2>&1 || true
done

# H19: no core dumps for challenge users
if ! grep -q '^# Rumor Mill #3 core limits' /etc/security/limits.conf 2>/dev/null; then
    {
        printf '%s\n' '# Rumor Mill #3 core limits'
        for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
            printf '%s hard core 0\n%s soft core 0\n' "$u" "$u"
        done
    } >> /etc/security/limits.conf
fi

# H20: no SSH keys
find /home -name authorized_keys -delete 2>/dev/null || true
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    rm -rf "/home/$u/.ssh" 2>/dev/null || true
done

# H21: UTC
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
printf 'UTC\n' > /etc/timezone

# Login-time umask so anything a player creates is private.
if grep -qE '^UMASK' /etc/login.defs; then
    sed -i 's/^UMASK.*/UMASK 077/' /etc/login.defs
else
    printf 'UMASK 077\n' >> /etc/login.defs
fi

# H9: no cron/at jobs
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    crontab -r -u "$u" >/dev/null 2>&1 || true
done

# H10: clean scratch space
rm -rf /tmp/* /var/tmp/* /dev/shm/* 2>/dev/null || true

# Final sweep: home modes must hold even after any file creation above.
chmod 711 /home
chmod 700 /home/y4ss1n3 /home/n0d4 /home/boul3h14 /home/gh3nj4
find /home -type f -exec chmod 600 {} +

###############################################################################
# 11. DROP SECRETS FROM THIS PROCESS
###############################################################################
unset GH3NJ4_PW DECRYPTED DROP_PW N0D4_PW BOUL_PW DECOY_FLAG flag_content \
      SUDO_RULES DANGLING

###############################################################################
# 12. START SSHD
###############################################################################
echo "[entrypoint] starting sshd on port ${SSH_PORT}"
exec /usr/sbin/sshd -D -e
