# Ubuntu 24.04 + Kubernetes 1.36 HA 설치 가이드

이 문서는 Ubuntu Server 24.04 LTS 6대로 Kubernetes HA 클러스터를 구성하는 절차입니다.

- Master/control-plane: 3대
- Worker: 3대
- Kubernetes: v1.36.x, 기본값 v1.36.1
- Container runtime: containerd
- Bootstrap: kubeadm
- API HA: HAProxy + Keepalived VIP
- CNI: Calico

## 1. 예시 IP 구성

| Role | Hostname | IP |
|---|---|---|
| VIP | k8s-api.local | 192.168.0.200 |
| Master 1 | master1 | 192.168.0.11 |
| Master 2 | master2 | 192.168.0.12 |
| Master 3 | master3 | 192.168.0.13 |
| Worker 1 | worker1 | 192.168.0.21 |
| Worker 2 | worker2 | 192.168.0.22 |
| Worker 3 | worker3 | 192.168.0.23 |

환경에 맞게 `examples/cluster.env.example` 값을 수정해서 사용합니다.

## 2. 사전 조건

모든 노드는 다음 조건을 만족해야 합니다.

- Ubuntu Server 24.04 LTS
- root 또는 sudo 권한
- 각 노드 간 6443, 2379-2380, 10250, 10257, 10259 통신 가능
- Worker에서 NodePort 사용 시 30000-32767 통신 가능
- 모든 노드 hostname 고유
- swap 비활성화
- VIP는 같은 L2 네트워크에서 사용하지 않는 IP

Hostname 설정 예시:

```bash
sudo hostnamectl set-hostname master1
```

`/etc/hosts` 예시:

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'
192.168.0.200 k8s-api.local
192.168.0.11 master1
192.168.0.12 master2
192.168.0.13 master3
192.168.0.21 worker1
192.168.0.22 worker2
192.168.0.23 worker3
EOF
```

## 3. 파일 준비

```bash
git clone https://github.com/tommypagychoi/k8s.git
cd k8s
cp examples/cluster.env.example cluster.env
vi cluster.env
chmod +x scripts/*.sh
```

`cluster.env`에서 최소 수정해야 할 값:

```bash
CONTROL_PLANE_VIP="192.168.0.200"
CONTROL_PLANE_ENDPOINT="192.168.0.200:6443"
KEEPALIVED_INTERFACE="eth0"
CP1_IP="192.168.0.11"
CP2_IP="192.168.0.12"
CP3_IP="192.168.0.13"
```

## 4. 모든 노드 공통 설치

Master 3대와 Worker 3대 모두에서 실행합니다.

```bash
sudo bash scripts/00-common-ubuntu2404.sh
sudo reboot
```

정확히 v1.36.1 패치를 고정 설치하려면 다음처럼 실행합니다.

```bash
sudo KUBERNETES_MINOR=1.36 KUBERNETES_VERSION=1.36.1 INSTALL_EXACT_PATCH=true bash scripts/00-common-ubuntu2404.sh
```

재부팅 후 확인:

```bash
kubeadm version
systemctl status containerd --no-pager
systemctl status kubelet --no-pager
```

## 5. Master 3대 API LB/VIP 구성

Master 1은 VIP 우선 소유자로 둡니다.

Master 1:

```bash
sudo cp examples/cluster.env.example cluster.env
sudo vi cluster.env
sudo sed -i 's/KEEPALIVED_STATE="BACKUP"/KEEPALIVED_STATE="MASTER"/' cluster.env
sudo sed -i 's/KEEPALIVED_PRIORITY="100"/KEEPALIVED_PRIORITY="150"/' cluster.env
sudo bash scripts/10-control-plane-lb.sh cluster.env
```

Master 2:

```bash
sudo cp examples/cluster.env.example cluster.env
sudo vi cluster.env
sudo sed -i 's/KEEPALIVED_PRIORITY="100"/KEEPALIVED_PRIORITY="120"/' cluster.env
sudo bash scripts/10-control-plane-lb.sh cluster.env
```

Master 3:

```bash
sudo cp examples/cluster.env.example cluster.env
sudo vi cluster.env
sudo sed -i 's/KEEPALIVED_PRIORITY="100"/KEEPALIVED_PRIORITY="110"/' cluster.env
sudo bash scripts/10-control-plane-lb.sh cluster.env
```

VIP 확인:

```bash
ip addr show
systemctl status haproxy --no-pager
systemctl status keepalived --no-pager
```

## 6. 첫 번째 Master 초기화

Master 1에서 실행합니다.

```bash
sudo bash scripts/20-init-first-control-plane.sh cluster.env
```

완료 후 join 명령 파일이 생성됩니다.

```bash
sudo ls -l /root/kubeadm-join/
sudo cat /root/kubeadm-join/join-control-plane.sh
sudo cat /root/kubeadm-join/join-worker.sh
```

클러스터 상태 확인:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## 7. 나머지 Master 2대 Join

Master 1에서 join 파일을 복사합니다.

```bash
scp /root/kubeadm-join/join-control-plane.sh root@master2:/root/kubeadm-join/join-control-plane.sh
scp /root/kubeadm-join/join-control-plane.sh root@master3:/root/kubeadm-join/join-control-plane.sh
```

Master 2와 Master 3에서 각각 실행합니다.

```bash
sudo bash scripts/30-join-control-plane.sh /root/kubeadm-join/join-control-plane.sh
```

확인:

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
```

## 8. Worker 3대 Join

Master 1에서 join 파일을 복사합니다.

```bash
scp /root/kubeadm-join/join-worker.sh root@worker1:/root/kubeadm-join/join-worker.sh
scp /root/kubeadm-join/join-worker.sh root@worker2:/root/kubeadm-join/join-worker.sh
scp /root/kubeadm-join/join-worker.sh root@worker3:/root/kubeadm-join/join-worker.sh
```

Worker 1, Worker 2, Worker 3에서 각각 실행합니다.

```bash
sudo bash scripts/40-join-worker.sh /root/kubeadm-join/join-worker.sh
```

## 9. 최종 확인

Master에서 실행합니다.

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get componentstatuses 2>/dev/null || true
kubectl -n kube-system get endpoints kube-controller-manager kube-scheduler
```

정상 예시:

```text
master1   Ready   control-plane
master2   Ready   control-plane
master3   Ready   control-plane
worker1   Ready   <none>
worker2   Ready   <none>
worker3   Ready   <none>
```

## 10. 장애 테스트

VIP 이동 확인:

```bash
ip addr show | grep 192.168.0.200
sudo systemctl stop keepalived
```

다른 Master에서 VIP가 올라오는지 확인합니다.

API 확인:

```bash
kubectl --server https://192.168.0.200:6443 get nodes
```

## 11. 토큰 만료 시 Join 명령 재생성

Master 1에서 실행합니다.

```bash
sudo kubeadm token create --print-join-command
sudo kubeadm init phase upload-certs --upload-certs
```

Control-plane join 형식:

```bash
kubeadm join 192.168.0.200:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane --certificate-key <CERT_KEY>
```

Worker join 형식:

```bash
kubeadm join 192.168.0.200:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

## 12. 재설치 또는 초기화

해당 노드에서만 실행합니다.

```bash
sudo CONFIRM=true bash scripts/90-reset-node.sh
sudo reboot
```

## 13. 참고 운영 명령어

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl describe node <node-name>
kubectl -n kube-system logs -l k8s-app=calico-node --tail=100
journalctl -u kubelet -n 100 --no-pager
crictl ps
crictl images
```

## 14. 참고 사항

- Kubernetes v1.36.x 패키지는 `https://pkgs.k8s.io/core:/stable:/v1.36/deb/` 저장소를 사용합니다.
- `apt-mark hold kubelet kubeadm kubectl`로 예기치 않은 자동 업그레이드를 막습니다.
- Calico Pod CIDR 기본값은 `192.168.0.0/16`입니다. 환경에서 물리 네트워크와 겹치면 반드시 다른 CIDR로 변경하세요.
- 운영 환경에서는 VIP IP, 방화벽, 시간 동기화, 백업, etcd snapshot 정책을 별도로 관리하세요.
