# git-ssh-server

A small, self-hosted Git server for a home lab, reached only over SSH. No web interface, database or accounts to manage: one container, plain Git, and public keys in two files.

- **Two kinds of key.** Keys in `keys/git` can clone, fetch and push. Keys in `keys/git-ro` can clone and fetch only.
- **Nothing but Git.** Every sign-in runs a small allowlist script, so no key can open a shell, run commands, forward ports or reach paths outside the repos.
- **Read-only twice over.** The read-only account is refused pushes by the script, and can't write repo files anyway, because it only has group read access.
- **Least privilege.** Read-only system files, all Linux capabilities dropped except the five sshd needs, no Docker socket, and only the repos folder mounted.
- **Your keys stay yours.** The server holds public keys only, so private keys can stay in a password manager such as 1Password.

## How it works

```
your machine ── SSH, port 2222 ──▶ container: git-ssh
  git push / pull                    sshd checks the public key
  (key from your agent)              ├─ account git     → git-access write → clone, fetch, push
                                     └─ account git-ro  → git-access read  → clone, fetch
                                                │
                                                ▼
                                     /srv/git  (the only mounted data folder)
```

| | `git` account | `git-ro` account |
|---|---|---|
| Clone, fetch, pull | Yes | Yes |
| Push | Yes | No |
| Shell, other commands, forwarding | No | No |
| Password sign-in | No | No |

## Set up

1. Copy the settings and choose where to publish:
   ```
   cp env.example .env
   ```
   `BIND_IP` is the address the port opens on. Use a LAN address rather than `0.0.0.0`, so the server isn't reachable from networks you didn't mean to include. For more than one address, copy `compose.override.example.yaml` to `compose.override.yaml`.
2. Add public keys to `keys/git` and `keys/git-ro`, one per line. See [keys/README.md](keys/README.md).
3. Start it:
   ```
   docker compose up -d --build
   ```
   On first start, the server makes its own host key in `HOSTKEYS_DIR` and prints its fingerprint. That key identifies the server to clients, and nobody signs in with it. Keep it, or clients will warn that the server changed.
4. Create a repo:
   ```
   docker exec -u git git-ssh new-repo my-project
   ```

## Use

```
git clone ssh://git@<server>:2222/my-project.git        # read and write
git clone ssh://git-ro@<server>:2222/my-project.git     # read-only
git remote set-url origin ssh://git@<server>:2222/my-project.git
```

Repos can sit in subfolders, such as `ssh://git@<server>:2222/home/notes.git`.

## Test

```
./test/run.sh
```

This builds the image and starts a throwaway server and client in Docker volumes. It then checks 28 things, including that the read-only key can't push, that no key gets a shell, a password sign-in or a path outside the repos, and that repos and the host key survive a restart. The test makes its own throwaway keys inside the client container and deletes everything afterwards.

## Unraid

- Use Compose Manager, or `docker compose` over SSH, with the project in `appdata`.
- Set `GIT_UID=99`, `GIT_GID=100` and `RO_UID=1001` if the repos folder should match Unraid's share owner.
- Publish on the LAN address, and on the Tailscale address if you use it, rather than on every interface.
- Include `REPOS_DIR` and `HOSTKEYS_DIR` in your backups, and keep one copy off the server.

## Update

Rebuild to pick up Alpine and OpenSSH fixes:
```
docker compose build --pull && docker compose up -d
```
Change `ALPINE_VERSION` in the `Dockerfile` when a new Alpine release comes out.

## Limits

- Every key in a file can reach every repo. For access per repo or per person, use something like Gitolite or Soft Serve.
- There are no pull requests, issues or web pages, only Git.
- Hooks inside the repos run as the `git` account, so only server admins should add them.

## Licence

Apache License 2.0. See [LICENSE](LICENSE).
