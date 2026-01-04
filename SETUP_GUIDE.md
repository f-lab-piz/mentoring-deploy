# k3s + ArgoCD 설치 및 설정 가이드

이 가이드는 k3s 클러스터에 ArgoCD를 설치하고 GitOps 기반 배포 자동화를 구축하는 과정을 안내합니다.

## 목차

1. [k3s 설치](#1-k3s-설치)
2. [ArgoCD 설치](#2-argocd-설치)
3. [ArgoCD 초기 설정](#3-argocd-초기-설정)
4. [mentoring-deploy 레포 설정](#4-mentoring-deploy-레포-설정)
5. [ArgoCD Application 등록](#5-argocd-application-등록)
6. [GitHub Actions 설정](#6-github-actions-설정)
7. [배포 확인](#7-배포-확인)

---

## 1. k3s 설치

### 1.1 k3s 설치 (단일 노드)

```bash
# k3s 설치
curl -sfL https://get.k3s.io | sh -

# 설치 확인
sudo systemctl status k3s

# 버전 확인
sudo k3s --version
```

### 1.2 kubectl 설정

```bash
# kubeconfig 파일 권한 설정
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# 환경 변수 설정 (현재 세션)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 영구 설정 (bashrc/zshrc에 추가)
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc

# kubectl 작동 확인
kubectl get nodes
kubectl get pods -A
```

### 1.3 k3s 주요 특징

- **경량화**: 일반 Kubernetes 대비 절반 이하의 메모리 사용
- **올인원 바이너리**: 단일 바이너리로 설치 완료
- **내장 구성 요소**:
  - Traefik Ingress Controller (기본)
  - Local Path Provisioner (스토리지)
  - CoreDNS
  - Metrics Server

### 1.4 선택사항: Traefik 비활성화 (nginx-ingress 사용 시)

```bash
# k3s 재설치 (Traefik 비활성화)
curl -sfL https://get.k3s.io | sh -s - --disable traefik

# nginx-ingress-controller 설치
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

---

## 2. ArgoCD 설치

### 2.1 ArgoCD 설치

```bash
# ArgoCD namespace 생성
kubectl create namespace argocd

# ArgoCD 설치
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 설치 확인 (모든 Pod가 Running 상태가 될 때까지 대기)
kubectl get pods -n argocd -w
```

### 2.2 ArgoCD CLI 설치 (선택사항)

**Linux:**
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

**macOS:**
```bash
brew install argocd
```

**설치 확인:**
```bash
argocd version --client
```

---

## 3. ArgoCD 초기 설정

### 3.1 ArgoCD 서버 접속

**포트 포워딩으로 접속:**
```bash
# 포트 포워딩 (백그라운드)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# 브라우저에서 https://localhost:8080 접속
```

**또는 Ingress 설정 (프로덕션 환경):**
```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-tls
```

### 3.2 초기 비밀번호 확인

```bash
# admin 계정의 초기 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# 비밀번호 복사 후 로그인
# Username: admin
# Password: [위에서 확인한 비밀번호]
```

### 3.3 비밀번호 변경 (권장)

```bash
# ArgoCD CLI로 로그인
argocd login localhost:8080

# 비밀번호 변경
argocd account update-password

# 초기 비밀번호 Secret 삭제 (보안)
kubectl -n argocd delete secret argocd-initial-admin-secret
```

---

## 4. mentoring-deploy 레포 설정

### 4.1 GitHub username 변경

다음 파일들에서 `YOUR_GITHUB_USERNAME`을 실제 GitHub username으로 변경:

```bash
# ArgoCD Application 파일
argocd/backend-dev.yaml
argocd/backend-prod.yaml
argocd/frontend-dev.yaml
argocd/frontend-prod.yaml

# Helm values 파일
helm/backend/values.yaml
helm/backend/values-dev.yaml
helm/backend/values-prod.yaml
helm/frontend/values.yaml
helm/frontend/values-dev.yaml
helm/frontend/values-prod.yaml
```

**예시 (argocd/backend-dev.yaml):**
```yaml
spec:
  source:
    repoURL: https://github.com/your-username/mentoring-deploy  # 변경
```

**예시 (helm/backend/values.yaml):**
```yaml
image:
  repository: ghcr.io/your-username/mentoring-backend  # 변경
```

### 4.2 도메인 설정

Ingress 도메인을 실제 사용할 도메인으로 변경:

```yaml
# helm/backend/values-dev.yaml
ingress:
  hosts:
    - host: api-dev.mentoring.example.com  # 변경

# helm/frontend/values-dev.yaml
ingress:
  hosts:
    - host: dev.mentoring.example.com  # 변경
```

로컬 테스트 시 `/etc/hosts`에 추가:
```bash
sudo vi /etc/hosts

# 추가
127.0.0.1 api-dev.mentoring.local
127.0.0.1 dev.mentoring.local
```

### 4.3 변경사항 커밋 및 푸시

```bash
git add .
git commit -m "Update repository settings with actual username and domain"
git push origin main
```

---

## 5. ArgoCD Application 등록

### 5.1 개발 환경 배포

```bash
# Backend 개발 환경
kubectl apply -f argocd/backend-dev.yaml

# Frontend 개발 환경
kubectl apply -f argocd/frontend-dev.yaml

# Application 등록 확인
kubectl get applications -n argocd
```

### 5.2 프로덕션 환경 배포 (필요시)

```bash
# Backend 프로덕션 환경
kubectl apply -f argocd/backend-prod.yaml

# Frontend 프로덕션 환경
kubectl apply -f argocd/frontend-prod.yaml
```

### 5.3 ArgoCD UI에서 확인

1. `https://localhost:8080` 접속
2. admin 계정으로 로그인
3. Applications 메뉴에서 등록된 앱 확인
4. 각 Application 클릭하여 배포 상태 확인

### 5.4 수동 동기화 (최초 배포)

```bash
# CLI로 동기화
argocd app sync mentoring-backend-dev
argocd app sync mentoring-frontend-dev

# 또는 UI에서 "SYNC" 버튼 클릭
```

---

## 6. GitHub Actions 설정

### 6.1 PAT (Personal Access Token) 생성

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" 클릭
3. 권한 선택: `repo` (전체)
4. 토큰 생성 및 복사

### 6.2 Repository Secret 등록

애플리케이션 레포지토리(mentoring)에서:

1. Settings → Secrets and variables → Actions
2. "New repository secret" 클릭
3. Name: `DEPLOY_REPO_TOKEN`
4. Value: [생성한 PAT 붙여넣기]
5. "Add secret" 클릭

### 6.3 GitHub Actions 워크플로우 추가

```bash
# mentoring 레포의 .github/workflows/ 디렉토리에
# example-update-from-app-repo.yaml 복사

cp mentoring-deploy/.github/workflows/example-update-from-app-repo.yaml \
   mentoring/.github/workflows/deploy.yaml
```

### 6.4 워크플로우 동작 확인

```bash
# mentoring 레포에서 변경사항 푸시
cd mentoring
git add .
git commit -m "Test deployment workflow"
git push origin develop  # 또는 main

# GitHub Actions 탭에서 워크플로우 실행 확인
```

---

## 7. 배포 확인

### 7.1 Pod 상태 확인

```bash
# 개발 환경 Pod 확인
kubectl get pods -n mentoring-dev

# 프로덕션 환경 Pod 확인
kubectl get pods -n mentoring-prod

# Pod 로그 확인
kubectl logs -f deployment/mentoring-backend-dev -n mentoring-dev
```

### 7.2 Service 및 Ingress 확인

```bash
# Service 확인
kubectl get svc -n mentoring-dev

# Ingress 확인
kubectl get ingress -n mentoring-dev

# Ingress 상세 정보
kubectl describe ingress mentoring-backend-dev -n mentoring-dev
```

### 7.3 애플리케이션 접속 테스트

```bash
# 로컬 테스트 (포트 포워딩)
kubectl port-forward svc/mentoring-backend-dev -n mentoring-dev 3000:3000
curl http://localhost:3000/health

# Ingress를 통한 접속
curl http://api-dev.mentoring.local/health
```

---

## 트러블슈팅

### ArgoCD Application이 OutOfSync 상태일 때

```bash
# 수동 동기화
argocd app sync mentoring-backend-dev

# 강제 동기화 (리소스 삭제 후 재생성)
argocd app sync mentoring-backend-dev --force
```

### Pod가 ImagePullBackOff 상태일 때

```bash
# Pod 상세 정보 확인
kubectl describe pod <pod-name> -n mentoring-dev

# GitHub Container Registry 인증 확인
# Secret 생성 (필요시)
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-pat> \
  -n mentoring-dev
```

### Ingress가 작동하지 않을 때

```bash
# Ingress Controller 확인
kubectl get pods -n ingress-nginx

# Ingress 이벤트 확인
kubectl describe ingress mentoring-backend-dev -n mentoring-dev

# Ingress Controller 로그 확인
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### Helm Chart 문법 검증

```bash
# Chart 린팅
helm lint helm/backend

# 템플릿 렌더링 확인 (실제 적용 전 검증)
helm template test helm/backend \
  -f helm/backend/values.yaml \
  -f helm/backend/values-dev.yaml
```

---

## GitOps 워크플로우 요약

```
┌─────────────────────┐
│  mentoring 레포      │
│  (코드 변경 & Push)  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  GitHub Actions     │
│  1. 이미지 빌드      │
│  2. GHCR 푸시       │
│  3. Tag 업데이트    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  mentoring-deploy   │
│  (values.yaml 업데이트)│
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  ArgoCD             │
│  (3분마다 폴링)      │
│  (변경 감지)        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  k3s Cluster        │
│  (자동 배포)        │
└─────────────────────┘
```

---

## 참고 자료

- [k3s 공식 문서](https://docs.k3s.io/)
- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [Helm 공식 문서](https://helm.sh/docs/)
- [GitOps 원칙](https://opengitops.dev/)
- [GitHub Actions 문서](https://docs.github.com/en/actions)

---

## 다음 단계

1. 모니터링 설정 (Prometheus + Grafana)
2. 로깅 설정 (Loki + Promtail)
3. 보안 강화 (Network Policies, RBAC)
4. 백업 및 복구 전략 수립
5. 멀티 환경 관리 (Staging, QA 등)
