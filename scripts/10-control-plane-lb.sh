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

: "${CONTROL_PLANE_VIP:?CONTROL_PLANE_VIP is required}"
: "${KEEPALIVED_INTERFACE:?KEEPALIVED_INTERFACE is required}"
: "${KEEPALIVED_AUTH_PASS:?KEEPALIVED_AUTH_PASS is required}"
: "${KEEPALIVED_STATE:?KEEPALIVED_STATE is required: MASTER or BACKUP}"
: "${KEEPALIVED_PRIORITY:?KEEPALIVED_PRIORITY is required}"
: "${CP1_IP:?CP1_IP is required}"
: "${CP2_IP:?CP2_IP is required}"
: "${CP3_IP:?CP3_IP is required}"

log() {
  echo "[10-lb] $*"
}

log "Install HAProxy and Keepalived"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy keepalived

log "Allow non-local bind for VIP failover"
cat >/etc/sysctl.d/98-k8s-vip.conf <<'EOF'
net.ipv4.ip_nonlocal_bind = 1
EOF
sysctl --system >/dev/null

log "Configure HAProxy for Kubernetes API"
cat >/etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 10s
    timeout client 1m
    timeout server 1m

frontend kubernetes_api
    bind ${CONTROL_PLANE_VIP}:6443
    default_backend kubernetes_api_backends

backend kubernetes_api_backends
    balance roundrobin
    option tcp-check
    server ${CP1_NAME:-master1} ${CP1_IP}:6443 check fall 3 rise 2
    server ${CP2_NAME:-master2} ${CP2_IP}:6443 check fall 3 rise 2
    server ${CP3_NAME:-master3} ${CP3_IP}:6443 check fall 3 rise 2
EOF

log "Configure Keepalived"
cat >/etc/keepalived/keepalived.conf <<EOF
vrrp_script chk_haproxy {
    script "pidof haproxy"
    interval 2
    weight 2
}

vrrp_instance K8S_API_VIP {
    state ${KEEPALIVED_STATE}
    interface ${KEEPALIVED_INTERFACE}
    virtual_router_id 51
    priority ${KEEPALIVED_PRIORITY}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass ${KEEPALIVED_AUTH_PASS}
    }
    virtual_ipaddress {
        ${CONTROL_PLANE_VIP}/24
    }
    track_script {
        chk_haproxy
    }
}
EOF

log "Enable and restart services"
systemctl enable --now haproxy keepalived
systemctl restart haproxy keepalived
systemctl --no-pager --full status haproxy | sed -n '1,12p'
systemctl --no-pager --full status keepalived | sed -n '1,12p'

log "Done. VIP should answer on the MASTER priority node after kubeadm init starts the API server."
