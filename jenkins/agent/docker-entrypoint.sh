#!/usr/bin/env sh
set -e

if [ -S /var/run/docker.sock ]; then
  docker_gid="$(stat -c '%g' /var/run/docker.sock)"
  getent group "${docker_gid}" >/dev/null || groupadd -g "${docker_gid}" docker-host
  usermod -aG "$(getent group "${docker_gid}" | cut -d: -f1)" jenkins
fi

exec setup-sshd
