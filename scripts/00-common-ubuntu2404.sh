#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

KUBERNETES_MINOR="${KUBERNETES_MINOR:-1.36}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.36.1}"
INSTALL_EXACT_PATCH="${INSTALL_EXACT_PATCH:-false}"

log() {
  echo "[00-common] $*"
}

log "Disable swap"
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab

log "Load kernel modules"
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

log "Apply Kubernetes sysctl settings"
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

log "Install base packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gpg \
  jq \
  chrony \
  bash-completion \
  socat \
  conntrack \
  ipset \
  ipvsadm \
  containerd

log "Configure containerd with systemd cgroups"
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd

log "Install Kubernetes apt repository v${KUBERNETES_MINOR}"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/ /
EOF
chmod 0644 /etc/apt/sources.list.d/kubernetes.list

log "Install kubelet kubeadm kubectl"
apt-get update
if [[ "${INSTALL_EXACT_PATCH}" == "true" ]]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "kubelet=${KUBERNETES_VERSION}-1.1" \
    "kubeadm=${KUBERNETES_VERSION}-1.1" \
    "kubectl=${KUBERNETES_VERSION}-1.1"
else
  DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
fi
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

log "Configure crictl"
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

log "Install kubectl completion"
kubectl completion bash >/etc/bash_completion.d/kubectl || true
if ! grep -q "alias k=kubectl" /root/.bashrc; then
  echo "alias k=kubectl" >>/root/.bashrc
  echo "complete -o default -F __start_kubectl k" >>/root/.bashrc
fi

log "Done. Reboot is recommended before kubeadm init/join."
kubeadm version
