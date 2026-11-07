# Keys

Put public keys here, one per line. Only these two files are read:

- `git`: keys that can clone, fetch and push
- `git-ro`: keys that can clone and fetch only

Everything in this folder except this README is gitignored. Only public keys (`ssh-ed25519 AAAA... comment`) belong here, never private keys.

Changes take effect at the next sign-in, with no restart. To remove a key, delete its line.
