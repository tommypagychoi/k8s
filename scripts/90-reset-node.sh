#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

CONFIRM="${CONFIRM:-false}"
if [[ "${CONFIRM}" != "true" ]]; then
  echo "This removes Kubernetes state from this node."
  echo "Run with CONFIRM=true sudo -E bash $0"
  exit 1
fi

log() {
  echo "[90-reset] $*"
}

log "kubeadm reset"
kubeadm reset -f || true

log "Stop kubelet and clean Kubernetes directories"
systemctl stop kubelet || true
rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /etc/kubernetes /root/.kube

log "Clean iptables rules created by Kubernetes/CNI"
iptables -F || true
iptables -t nat -F || true
iptables -t mangle -F || true
iptables -X || true

log "Restart containerd"
systemctl restart containerd

log "Done. Reboot is recommended."
