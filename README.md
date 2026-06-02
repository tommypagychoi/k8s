# Kubernetes HA Cluster on Ubuntu 24.04

Ubuntu 24.04 LTS 서버 6대로 Kubernetes HA 클러스터를 설치하는 가이드와 스크립트입니다.

- OS: Ubuntu Server 24.04 LTS
- Kubernetes: v1.36.x, 현재 기본값 v1.36.1
- Runtime: containerd
- Bootstrap: kubeadm
- Control plane: 3대
- Worker: 3대
- API HA: HAProxy + Keepalived VIP
- CNI: Calico

## 문서

- [Ubuntu 24.04 + Kubernetes 1.36 HA 3 Master / 3 Worker 설치 가이드](docs/ubuntu-2404-kubeadm-ha-3m3w.md)

## 파일 구조

```text
examples/cluster.env.example      # 클러스터 환경 변수 예시
scripts/00-common-ubuntu2404.sh   # 모든 노드 공통 설치
scripts/10-control-plane-lb.sh    # 마스터 3대 API LB/VIP 구성
scripts/20-init-first-control-plane.sh
scripts/30-join-control-plane.sh
scripts/40-join-worker.sh
scripts/90-reset-node.sh
```

## 빠른 순서

1. 모든 노드에 Ubuntu 24.04 설치
2. 모든 노드에서 `00-common-ubuntu2404.sh` 실행
3. 마스터 3대에서 `10-control-plane-lb.sh` 실행
4. 첫 번째 마스터에서 `20-init-first-control-plane.sh` 실행
5. 나머지 마스터에서 `30-join-control-plane.sh` 실행
6. 워커 3대에서 `40-join-worker.sh` 실행
7. `kubectl get nodes -o wide`로 확인

자세한 명령어와 변수 설명은 `docs/ubuntu-2404-kubeadm-ha-3m3w.md`를 확인하세요.
