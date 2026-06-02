#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 /path/to/join-worker.sh"
  exit 1
fi

JOIN_FILE="${1:-/root/kubeadm-join/join-worker.sh}"
if [[ ! -f "${JOIN_FILE}" ]]; then
  echo "Missing worker join file: ${JOIN_FILE}"
  echo "Copy /root/kubeadm-join/join-worker.sh from the first master."
  exit 1
fi

log() {
  echo "[40-join-worker] $*"
}

log "Join this node as a worker"
bash "${JOIN_FILE}" --cri-socket unix:///run/containerd/containerd.sock

log "Done"
systemctl --no-pager --full status kubelet | sed -n '1,15p' || true
