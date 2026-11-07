# A small Git server reached only over SSH. Two accounts:
#   git     can clone, fetch and push
#   git-ro  can clone and fetch only (enforced by the access script and by file permissions)
ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache openssh-server git

# IDs match the owner of the repos folder on the host. Unraid shares often use 99:100 (nobody:users).
ARG GIT_UID=1000
ARG GIT_GID=1000
ARG RO_UID=1001

# Both accounts share the git group: git owns the repos, git-ro may only read them.
# Alpine creates locked accounts ("!"), which sshd refuses, so the password is set to "*": no password can match it.
RUN addgroup -g "${GIT_GID}" git \
 && adduser -D -u "${GIT_UID}" -G git -h /srv/git -s /bin/sh git \
 && adduser -D -u "${RO_UID}" -G git -h /home/git-ro -s /bin/sh git-ro \
 && sed -i -E 's/^(git|git-ro):!:/\1:*:/' /etc/shadow

COPY rootfs/ /
# COPY keeps the build folder's modes. A checkout made with umask 002 (as on Unraid) leaves /etc
# group-writable, and sshd then refuses every key. Strip group and world write from what was copied.
RUN find /etc /usr/local ! -type l \( -perm -020 -o -perm -002 \) -exec chmod go-w {} + \
 && chmod 0755 /usr/local/bin/git-access /usr/local/bin/new-repo /usr/local/bin/entrypoint \
 && chmod 0644 /etc/ssh/sshd_config /etc/gitconfig

EXPOSE 2222
VOLUME ["/srv/git", "/etc/ssh/hostkeys"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]
