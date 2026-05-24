#!/usr/bin/env bash
set -euo pipefail

PROFILE="${PROFILE:-cilium-lab}"
NODES="${NODES:-3}"
K8S_VERSION="${K8S_VERSION:-v1.34.0}"
NAMESPACE="${NAMESPACE:-devops-demo}"
RELEASE_NAME="${RELEASE_NAME:-devops-demo-app}"
CHART_PATH="${CHART_PATH:-helm/devops-demo-app}"
IMAGE="${IMAGE:-devops-demo-app:minikube}"

usage() {
  cat <<EOF
Usage: $0 <start|deploy|rollback> [revision]

Commands:
  start       Start Minikube with 1 control-plane, 2 workers, and Cilium CNI.
  deploy      Build app image, load it into Minikube, and deploy with Helm.
  rollback    Roll back Helm release. Optionally pass a revision.

Environment:
  PROFILE=${PROFILE}
  NODES=${NODES}
  K8S_VERSION=${K8S_VERSION}
  NAMESPACE=${NAMESPACE}
  RELEASE_NAME=${RELEASE_NAME}
  IMAGE=${IMAGE}
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required."
    exit 1
  fi
}

start_cluster() {
  require_command minikube
  require_command kubectl

  minikube start \
    -p "${PROFILE}" \
    --nodes="${NODES}" \
    --driver=docker \
    --container-runtime=containerd \
    --kubernetes-version="${K8S_VERSION}" \
    --network-plugin=cni \
    --cni=cilium

  kubectl config use-context "${PROFILE}"
  kubectl -n kube-system rollout status ds/cilium --timeout=180s
  kubectl -n kube-system rollout status ds/cilium-envoy --timeout=180s
  kubectl get nodes -o wide

  echo ""
  echo "Minikube profile ${PROFILE} is ready with ${NODES} nodes and Cilium CNI."
}

deploy_app() {
  require_command docker
  require_command minikube
  require_command kubectl
  require_command helm

  local image_repository="${IMAGE%:*}"
  local image_tag="${IMAGE##*:}"

  if [ "${image_repository}" = "${image_tag}" ]; then
    image_repository="${IMAGE}"
    image_tag="latest"
  fi

  docker build -t "${IMAGE}" ./app
  minikube -p "${PROFILE}" image load "${IMAGE}"

  kubectl config use-context "${PROFILE}"
  helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set image.repository="${image_repository}" \
    --set image.tag="${image_tag}" \
    --set config.data.PORT="8080"

  kubectl rollout status "deployment/${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=180s
  kubectl exec "deployment/${RELEASE_NAME}" -n "${NAMESPACE}" -- wget -qO- http://localhost:8080/

  echo ""
  echo "Helm deployment completed."
  echo "Release: helm status ${RELEASE_NAME} -n ${NAMESPACE}"
  echo "Service: kubectl get svc -n ${NAMESPACE}"
  echo "URL: minikube -p ${PROFILE} service ${RELEASE_NAME} -n ${NAMESPACE} --url"
}

rollback_app() {
  require_command helm
  require_command kubectl

  local revision="${1:-}"

  if [ -z "${revision}" ]; then
    helm rollback "${RELEASE_NAME}" -n "${NAMESPACE}"
  else
    helm rollback "${RELEASE_NAME}" "${revision}" -n "${NAMESPACE}"
  fi

  kubectl rollout status "deployment/${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=120s
  helm history "${RELEASE_NAME}" -n "${NAMESPACE}"
}

case "${1:-}" in
  start)
    start_cluster
    ;;
  deploy)
    deploy_app
    ;;
  rollback)
    rollback_app "${2:-}"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
