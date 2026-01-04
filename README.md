# mentoring-deploy

Mentoring Project의 Kubernetes 배포 설정을 관리하는 GitOps 레포지토리입니다.

## 개요

이 레포지토리는 ArgoCD를 통한 GitOps 워크플로우를 구현합니다:
1. `mentoring` 레포에서 코드 변경 및 이미지 빌드
2. GitHub Actions가 이 레포의 이미지 태그 자동 업데이트
3. ArgoCD가 변경사항을 감지하고 Kubernetes에 자동 배포

## 디렉토리 구조

```
mentoring-deploy/
├── helm/                    # Helm Charts
│   ├── backend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml     # 기본 설정
│   │   ├── values-dev.yaml # 개발 환경 오버라이드
│   │   ├── values-prod.yaml # 프로덕션 환경 오버라이드
│   │   └── templates/
│   └── frontend/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-dev.yaml
│       ├── values-prod.yaml
│       └── templates/
├── argocd/                  # ArgoCD Application 정의
│   ├── backend-dev.yaml
│   ├── backend-prod.yaml
│   ├── frontend-dev.yaml
│   └── frontend-prod.yaml
└── scripts/                 # 유틸리티 스크립트
    └── update-image-tag.sh
```

## 사전 요구사항

### 1. Kubernetes 클러스터 설정

```bash
# nginx-ingress-controller 설치
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# cert-manager 설치 (HTTPS용)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### 2. ArgoCD 설치

```bash
# ArgoCD 설치
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD CLI 설치 (선택사항)
brew install argocd  # macOS
# or
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# ArgoCD 접속
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 초기 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 3. GitHub Personal Access Token 생성

mentoring 레포의 GitHub Actions가 이 레포를 업데이트할 수 있도록 PAT를 생성합니다:

1. GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token (classic)
3. 권한 선택:
   - `repo` (전체)
4. 생성된 토큰을 mentoring 레포의 Secrets에 `DEPLOY_REPO_TOKEN`으로 저장

## 설정 방법

### 1. 레포지토리 URL 업데이트

다음 파일들에서 `YOUR_GITHUB_USERNAME`을 실제 GitHub username으로 변경:

```bash
# Helm values 파일
helm/backend/values.yaml
helm/frontend/values.yaml

# ArgoCD Application 파일
argocd/*.yaml
```

### 2. 도메인 설정

Ingress 설정에서 도메인을 변경:

```bash
# 개발 환경
helm/backend/values-dev.yaml: api-dev.mentoring.example.com
helm/frontend/values-dev.yaml: dev.mentoring.example.com

# 프로덕션 환경
helm/backend/values-prod.yaml: api.mentoring.example.com
helm/frontend/values-prod.yaml: mentoring.example.com
```

### 3. 환경 변수 설정

프로덕션 환경의 민감한 정보는 Kubernetes Secret으로 관리:

```bash
# 프로덕션 Secret 생성
kubectl create secret generic backend-secrets \
  --from-literal=database-url="postgresql://user:pass@host:5432/db" \
  --from-literal=redis-url="redis://host:6379" \
  -n mentoring-prod
```

## 배포 방법

### ArgoCD Application 등록

```bash
# 모든 Application 등록
kubectl apply -f argocd/

# 또는 개별 등록
kubectl apply -f argocd/backend-dev.yaml
kubectl apply -f argocd/frontend-dev.yaml
```

### ArgoCD UI에서 확인

1. `http://localhost:8080`에 접속
2. admin / [초기 비밀번호]로 로그인
3. Applications 메뉴에서 배포 상태 확인

## mentoring 레포 설정

mentoring 레포에 다음 워크플로우를 추가:

```bash
# mentoring/.github/workflows/deploy.yaml 생성
cp .github/workflows/example-update-from-app-repo.yaml \
   ../mentoring/.github/workflows/deploy.yaml
```

워크플로우가 수행하는 작업:
1. 코드 변경 감지 (main → prod, develop → dev)
2. Docker 이미지 빌드 및 GHCR에 푸시
3. 이 레포의 Helm values 파일 이미지 태그 업데이트
4. ArgoCD가 변경 감지 및 자동 배포

## 수동 배포

### 이미지 태그 수동 업데이트

```bash
# 스크립트 사용
./scripts/update-image-tag.sh backend dev abc123

# 또는 직접 수정
yq eval ".image.tag = \"abc123\"" -i helm/backend/values-dev.yaml

# 변경사항 커밋
git add helm/backend/values-dev.yaml
git commit -m "Update backend dev image to abc123"
git push
```

### Helm으로 직접 배포

```bash
# 개발 환경
helm upgrade --install mentoring-backend helm/backend \
  -f helm/backend/values.yaml \
  -f helm/backend/values-dev.yaml \
  -n mentoring-dev \
  --create-namespace

# 프로덕션 환경
helm upgrade --install mentoring-backend helm/backend \
  -f helm/backend/values.yaml \
  -f helm/backend/values-prod.yaml \
  -n mentoring-prod \
  --create-namespace
```

## 트러블슈팅

### ArgoCD가 변경사항을 감지하지 못할 때

```bash
# ArgoCD Application 수동 새로고침
argocd app get mentoring-backend-dev
argocd app sync mentoring-backend-dev
```

### Helm Chart 문법 검증

```bash
# Chart 린팅
helm lint helm/backend

# 템플릿 렌더링 확인
helm template test helm/backend \
  -f helm/backend/values.yaml \
  -f helm/backend/values-dev.yaml
```

### 배포 상태 확인

```bash
# Pod 상태
kubectl get pods -n mentoring-dev
kubectl get pods -n mentoring-prod

# 로그 확인
kubectl logs -f deployment/mentoring-backend-dev -n mentoring-dev

# Ingress 확인
kubectl get ingress -n mentoring-dev
```

## GitOps 워크플로우

```
┌─────────────────┐
│  mentoring 레포  │
│  (코드 변경)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ GitHub Actions  │
│ 1. 테스트       │
│ 2. 이미지 빌드  │
│ 3. GHCR 푸시    │
└────────┬────────┘
         │
         ▼
┌──────────────────┐
│ mentoring-deploy │
│ (이미지 태그 업데이트) │
└────────┬─────────┘
         │
         ▼
┌─────────────────┐
│     ArgoCD      │
│ (변경 감지)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Kubernetes    │
│   (자동 배포)    │
└─────────────────┘
```

## 참고 자료

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [GitOps Principles](https://opengitops.dev/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)