#!/usr/bin/env bash
set -euo pipefail

KEY_DIR=".local/keys"
CASC_DIR=".local/casc"
KEY_PATH="${KEY_DIR}/jenkins_agent_key"
CASC_TEMPLATE="jenkins/controller/casc/jenkins.yaml.template"
CASC_OUTPUT="${CASC_DIR}/jenkins.yaml"

mkdir -p "${KEY_DIR}" "${CASC_DIR}"

if [ ! -f "${KEY_PATH}" ]; then
  ssh-keygen -t rsa -b 4096 -m PEM -N "" -C "jenkins-local-demo" -f "${KEY_PATH}"
fi

chmod 600 "${KEY_PATH}"

awk '
  /__PRIVATE_KEY__/ {
    while ((getline line < key) > 0) {
      print "                    " line
    }
    close(key)
    next
  }
  { print }
' key="${KEY_PATH}" "${CASC_TEMPLATE}" > "${CASC_OUTPUT}"

printf '%s\n' "$(cat "${KEY_PATH}.pub")" > ".local/agent_pubkey.env"
printf "JENKINS_AGENT_SSH_PUBKEY='%s'\n" "$(cat "${KEY_PATH}.pub")" > ".env"
echo "Rendered ${CASC_OUTPUT}"

export JENKINS_AGENT_SSH_PUBKEY
JENKINS_AGENT_SSH_PUBKEY="$(cat .local/agent_pubkey.env)"

export DOCKER_GID
DOCKER_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 0)"

if docker compose version >/dev/null 2>&1; then
  docker compose rm -sf jenkins-agent jenkins-controller >/dev/null 2>&1 || true
  docker compose up -d --build
else
  docker-compose rm -sf jenkins-agent jenkins-controller demo-app >/dev/null 2>&1 || true
  docker-compose up -d --build
fi

echo ""
echo "Jenkins UI: http://localhost:8080"
echo "Username: admin"
echo "Password: admin123"
echo ""
echo "Demo app: http://localhost:8081"
echo "Local registry: localhost:5000"
