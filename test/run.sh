#!/bin/sh
# Builds the image and checks what each key can and can't do, against a throwaway server.
# The test keys are made inside a throwaway client container and deleted with it; none touch this machine.
#   ./test/run.sh
set -eu
cd "$(dirname "$0")/.."

C="docker compose -p git-ssh-test -f compose.yaml -f test/compose.test.yaml"
cleanup() { $C down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
cleanup

$C up -d --build --quiet-pull >/dev/null
$C exec -T client sh -c '
  apk add -q --no-cache git openssh-client >/dev/null
  ssh-keygen -q -t ed25519 -N "" -C test-write -f /keys/rw
  ssh-keygen -q -t ed25519 -N "" -C test-read -f /keys/ro
  ssh-keygen -q -t ed25519 -N "" -C test-unknown -f /keys/unknown
  cp /keys/rw.pub /auth/git; cp /keys/ro.pub /auth/git-ro; chmod 644 /auth/git /auth/git-ro'
$C exec -T -u git git-ssh new-repo demo >/dev/null
fp_before=$($C exec -T git-ssh ssh-keygen -lf /etc/ssh/hostkeys/ssh_host_ed25519_key.pub | cut -d' ' -f2)

client_ok=0
$C exec -T client sh -s <<'EOF' || client_ok=1
set -u
pass=0; fail=0
H=git-ssh-test
ssh_as() { key=$1; shift; ssh -i "/keys/$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/kh -o ConnectTimeout=5 -p 2222 "$@"; }
gitk() { key=$1; shift; GIT_SSH_COMMAND="ssh -i /keys/$key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/kh -o ConnectTimeout=5" git "$@"; }
ok()   { if "$@" >/tmp/out 2>&1; then pass=$((pass+1)); echo "PASS  $T"; else fail=$((fail+1)); echo "FAIL  $T"; sed 's/^/      /' /tmp/out | head -5; fi; }
deny() { if "$@" >/tmp/out 2>&1; then fail=$((fail+1)); echo "FAIL  $T (was allowed)"; else pass=$((pass+1)); echo "PASS  $T"; fi; cp /tmp/out /tmp/denied; }
git config --global user.name test; git config --global user.email test@example.invalid; git config --global init.defaultBranch main
cd /tmp

T="write key: clone";                 ok gitk rw clone -q ssh://git@$H:2222/demo.git w
T="write key: push";                  ok sh -c 'cd w && echo hi > f && git add f && git commit -qm one && GIT_SSH_COMMAND="ssh -i /keys/rw -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=/tmp/kh -p 2222" git push -q origin main'
T="write key: clone with short path"; ok gitk rw clone -q ssh://git@$H:2222/~/demo w2
T="read key: clone sees the push";    ok sh -c 'GIT_SSH_COMMAND="ssh -i /keys/ro -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=/tmp/kh" git clone -q ssh://git-ro@'$H':2222/demo.git r && test -f r/f'
T="read key: fetch";                  ok sh -c 'cd r && GIT_SSH_COMMAND="ssh -i /keys/ro -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=/tmp/kh -p 2222" git fetch -q'
T="read key: push refused";           deny sh -c 'cd r && echo x > g && git add g && git commit -qm two && GIT_SSH_COMMAND="ssh -i /keys/ro -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=/tmp/kh -p 2222" git push -q origin main'
T="read key: refusal says read-only"; ok grep -q "this key is read-only" /tmp/denied
T="read key: raw receive-pack refused"; deny ssh_as ro git-ro@$H "git-receive-pack '/demo.git'"
T="read key on write account refused"; deny ssh_as ro git@$H "git-upload-pack '/demo.git'"
T="unknown key refused";              deny ssh_as unknown git-ro@$H "git-upload-pack '/demo.git'"
T="root sign-in refused";             deny ssh_as rw root@$H "git-upload-pack '/demo.git'"
T="write key: shell refused";         deny ssh_as rw git@$H
T="write key: tty shell refused";     deny ssh_as rw -tt git@$H
T="write key: other command refused"; deny ssh_as rw git@$H "id"
T="write key: sh -c refused";         deny ssh_as rw git@$H "sh -c id"
T="path outside repos refused";       deny ssh_as rw git@$H "git-upload-pack '/etc/passwd'"
T="path with .. refused";             deny ssh_as rw git@$H "git-upload-pack '/../../etc'"
T="missing repo refused";             deny ssh_as rw git@$H "git-upload-pack '/nope.git'"
T="quote injection refused";          deny ssh_as rw git@$H "git-upload-pack 'demo.git'; id'"
T="port forwarding refused";          deny ssh_as rw -o ExitOnForwardFailure=yes -W 127.0.0.1:2222 git@$H
T="password sign-in refused";         deny ssh -o BatchMode=yes -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive -o UserKnownHostsFile=/tmp/kh -p 2222 git@$H true
echo "client: $pass passed, $fail failed"
[ "$fail" = 0 ]
EOF

srv_pass=0; srv_fail=0
check() { if [ "$1" = "$2" ]; then srv_pass=$((srv_pass+1)); echo "PASS  $3"; else srv_fail=$((srv_fail+1)); echo "FAIL  $3"; fi; }
check "$($C exec -T -u git-ro git-ssh sh -c 'touch /srv/git/demo.git/x 2>/dev/null && echo yes || echo no')" no "read account can't write repo files"
check "$($C exec -T -u git-ro git-ssh sh -c 'ls /srv/git/demo.git >/dev/null 2>&1 && echo yes || echo no')" yes "read account can read repo files"
check "$($C exec -T git-ssh sh -c 'touch /etc/x 2>/dev/null && echo yes || echo no')" no "system files are read-only"
check "$($C exec -T git-ssh sh -c 'ls /var/run/docker.sock >/dev/null 2>&1 && echo yes || echo no')" no "no Docker socket inside"
$C restart git-ssh >/dev/null
sleep 2
fp_after=$($C exec -T git-ssh ssh-keygen -lf /etc/ssh/hostkeys/ssh_host_ed25519_key.pub | cut -d' ' -f2)
check "$fp_after" "$fp_before" "host key kept after restart"
check "$($C exec -T client sh -c 'GIT_SSH_COMMAND="ssh -i /keys/rw -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=/tmp/kh" git ls-remote ssh://git@git-ssh-test:2222/demo.git >/dev/null 2>&1 && echo yes || echo no')" yes "repos and keys work after restart"
echo "server: $srv_pass passed, $srv_fail failed"

if [ "$client_ok" = 0 ] && [ "$srv_fail" = 0 ]; then echo "ALL PASSED"; else echo "SOME FAILED"; exit 1; fi
