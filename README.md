# Rumor Mill #3 — Dead Drop

A hard Linux CTF challenge (Rumor series, #3) — 400–800 points.

Three non-root accounts, a mailbox with a lying third party, a git repo whose
history was rewritten, a symmetric-encrypted dead drop, and a root archive
helper that trusts its own working directory.

## Layout

```
rumor-mill-3/
├── Dockerfile
├── entrypoint.sh           # users, mail, drop, repo, sudo helper, hardening
├── verify.sh               # 90-check suite (run as root)
├── sshd_config
├── flag.secret             # standalone root-only flag (0600 in image)
├── challenge.yml           # CTF metadata (hard, 400–800)
├── solutions/
│   ├── solve.md
│   └── verify_solution.sh  # host-side automated solver
├── .env.example
├── .gitignore
├── README.md
└── LICENSE
```

## Quick start

```bash
docker build -t rumor-mill-3:v3.0.0 .

docker run -d --name rumor-mill-3 \
  --hostname challenge-rumor-mill-3 \
  -p "${HOST_PORT:-2226}:${SSH_PORT:-2222}" \
  -e SSH_PORT="${SSH_PORT:-2222}" \
  rumor-mill-3:v3.0.0
```

Host port **2226** keeps this clear of Rumor Mill #1 (2222/2223) and #2
(2224/2225). The ingehack-mini build uses **2227**.

## Connect

```bash
ssh -p 2226 y4ss1n3@localhost
# password: Welcome123
```

## Verify

```bash
docker exec rumor-mill-3 /verify.sh
CONTAINER=rumor-mill-3 solutions/verify_solution.sh
```

## Intended path

`y4ss1n3` → `n0d4` → `boul3h14` → root.

1. `/var/mail/y4ss1n3` holds two password halves and one lie.
2. `n0d4`'s dotfiles repo has the drop passphrase in a **dangling git object**
   (`git fsck --lost-found`) after a history rewrite.
3. `gpg --batch --pinentry-mode loopback --passphrase ... --decrypt dead-drop.gpg`
   yields `boul3h14`'s password (the pinentry dialog is unusable over this
   sshd, so the note gives the exact command).
4. `sudo -l` exposes one helper. `tar czf ... *` in a player-writable
   directory is vulnerable to **GNU tar wildcard injection**
   (`--checkpoint-action=exec`), giving root.
5. `/root/dead-drop/flag.txt` (`0600`) holds the flag.

`gh3nj4` holds only a decoy flag and a decoy password claim.

## Security notes

- The plaintext flag is **not** in any file copied into the image. Standalone
  builds keep it in root-only `/etc/rumor-mill/flag` (0600); CI builds inject
  it as `FLAG` and the entrypoint stages it root-only, then re-execs with a
  clean environment so it never appears in `/proc/1/environ`.
- `gh3nj4`'s password is generated at container start.
- `pam_faillock` is configured on `su`, `sshd`, and `login` (5 failures, 15 min).
- Exactly one sudo rule exists (`boul3h14` → `/usr/local/bin/rumor-archive`),
  and the verifier asserts there is no second root path.
- `pam_motd` is omitted so a login cannot write a `0644` cache file into a home.

## Deviations / notes

1. **`tar` version matters.** The intended privesc relies on
   `--checkpoint-action=exec`, present since tar 1.30. Ubuntu 22.04 ships
   1.34 and the verifier runs the exploit so a base-image bump cannot silently
   break the challenge.
2. **`gpg` writes a keybox, not a keyring.** Symmetric encryption still
   creates `~/.gnupg`; it is `0700` with `0600` files, so the `0600` invariant
   holds.
3. **`/home` is `0711`, each home `0700`**, and every file under `/home` is
   `0600`, matching the series convention.
