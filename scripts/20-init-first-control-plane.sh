#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 /path/to/cluster.env"
  exit 1
fi

ENV_FILE="${1:-./cluster.env}"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${CONTROL_PLANE_ENDPOINT:?CONTROL_PLANE_ENDPOINT is required, for example 192.168.0.200:6443}"
: "${POD_CIDR:?POD_CIDR is required}"
: "${SERVICE_CIDR:?SERVICE_CIDR is required}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.36.1}"
CLUSTER_NAME="${CLUSTER_NAME:-kubernetes}"
OUTPUT_DIR="${OUTPUT_DIR:-/root/kubeadm-join}"

log() {
  echo "[20-init] $*"
}

mkdir -p "${OUTPUT_DIR}"

log "Create kubeadm init config"
cat >"${OUTPUT_DIR}/kubeadm-init.yaml" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $(hostname -I | awk '{print $1}')
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: ${CLUSTER_NAME}
kubernetesVersion: v${KUBERNETES_VERSION}
controlPlaneEndpoint: ${CONTROL_PLANE_ENDPOINT}
networking:
  podSubnet: ${POD_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
apiServer:
  certSANs:
    - ${CONTROL_PLANE_ENDPOINT%:*}
    - ${CONTROL_PLANE_DNS:-k8s-api.local}
controllerManager: {}
scheduler: {}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

log "Initialize first control-plane node"
kubeadm init --config "${OUTPUT_DIR}/kubeadm-init.yaml" --upload-certs | tee "${OUTPUT_DIR}/kubeadm-init.log"

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

log "Install Calico CNI"
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/calico.yaml

log "Generate fresh join commands"
kubeadm token create --print-join-command >"${OUTPUT_DIR}/join-worker.sh"
CERT_KEY="$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1)"
JOIN_BASE="$(cat "${OUTPUT_DIR}/join-worker.sh")"
printf '%s --control-plane --certificate-key %s\n' "${JOIN_BASE}" "${CERT_KEY}" >"${OUTPUT_DIR}/join-control-plane.sh"
chmod 600 "${OUTPUT_DIR}/join-worker.sh" "${OUTPUT_DIR}/join-control-plane.sh"

log "Join commands created:"
echo "  ${OUTPUT_DIR}/join-control-plane.sh"
echo "  ${OUTPUT_DIR}/join-worker.sh"
log "Copy the right file to the remaining nodes and run scripts/30 or scripts/40."
