#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 /path/to/join-control-plane.sh"
  exit 1
fi

JOIN_FILE="${1:-/root/kubeadm-join/join-control-plane.sh}"
if [[ ! -f "${JOIN_FILE}" ]]; then
  echo "Missing control-plane join file: ${JOIN_FILE}"
  echo "Copy /root/kubeadm-join/join-control-plane.sh from the first master."
  exit 1
fi

log() {
  echo "[30-join-cp] $*"
}

log "Join this node as an additional control-plane node"
bash "${JOIN_FILE}" --cri-socket unix:///run/containerd/containerd.sock

log "Install kubeconfig for root"
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  mkdir -p "${USER_HOME}/.kube"
  cp -f /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
  chown -R "${SUDO_USER}:${SUDO_USER}" "${USER_HOME}/.kube"
fi

log "Done"
kubectl get nodes -o wide || true
