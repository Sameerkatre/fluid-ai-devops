# Fluid AI — DevOps Challenge: Kubernetes + Bitbucket CI/CD + ArgoCD GitOps

## Architecture

```
Developer pushes to main
         │
         ▼
┌──────────────────────────────────────┐
│         Bitbucket Pipelines          │
│                                      │
│  1. Lint + Smoke test                │
│  2. docker build & push to Hub       │
│     (tagged with git SHA)            │
│  3. Update gitops/envs/dev/          │
│     backend.yaml image tag           │
│  4. git commit + push [skip ci]      │
└──────────────────────────────────────┘
         │
         │  (git push to same repo)
         ▼
┌──────────────────────────────────────┐
│            ArgoCD                    │
│  Watches gitops/envs/<env>/          │
│  Detects image tag changed           │
│  Applies kubectl automatically       │
│  Self-heals if manual changes made   │
└──────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────┐
│               Minikube Cluster (local)            │
│                                                   │
│  namespace: dev                                   │
│  ┌────────────────────────────────────────────┐  │
│  │  backend Deployment (1 replica)            │  │
│  │  ┌──────────────────────────────────┐      │  │
│  │  │ pod: flask + gunicorn :5000      │──────┼──┼──► NodePort :30080
│  │  │ liveness  → /health (process OK)│      │  │
│  │  │ readiness → /ready  (Redis ping) │      │  │
│  │  └──────────────────────────────────┘      │  │
│  │           │                                │  │
│  │           ▼                                │  │
│  │  redis Deployment (1 replica)              │  │
│  │  ┌──────────────────────────────────┐      │  │
│  │  │ redis:7-alpine :6379             │      │  │
│  │  └──────────────────────────────────┘      │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

## Repository Structure

```
fluid-ai-devops/
│
├── app/                         # Application code
│   ├── app.py                   # Flask app (5 endpoints)
│   ├── requirements.txt         # Python deps
│   └── Dockerfile               # Multi-stage, non-root user
│
├── k8s/                         # Base Kubernetes manifests
│   ├── backend.yaml             # Backend Deployment + Service
│   └── redis.yaml               # Redis Deployment + Service
│
├── gitops/                      # ArgoCD watches these folders
│   └── envs/
│       ├── dev/                 # Dev environment manifests
│       │   ├── backend.yaml     # ← pipeline updates image tag here
│       │   └── redis.yaml
│       ├── staging/             # Staging environment manifests
│       │   ├── backend.yaml
│       │   └── redis.yaml
│       └── prod/                # Production environment manifests
│           ├── backend.yaml
│           └── redis.yaml
│
├── argocd/                      # ArgoCD Application definitions
│   ├── app-dev.yaml             # Registers dev app in ArgoCD
│   ├── app-staging.yaml         # Registers staging app
│   └── app-prod.yaml            # Registers prod app (manual sync)
│
├── bitbucket-pipelines.yml      # CI/CD pipeline definition
├── setup.sh                     # One-command local setup
├── setup-argocd.sh              # ArgoCD local install
└── simulate-failure.sh          # Live failure demo script
```

---

## Prerequisites — Install These First

| Tool | Install |
|------|---------|
| Docker Desktop | https://docs.docker.com/desktop/ |
| Minikube | `brew install minikube` (Mac) or https://minikube.sigs.k8s.io/docs/start/ |
| kubectl | `brew install kubectl` or https://kubernetes.io/docs/tasks/tools/ |
| ArgoCD CLI | `brew install argocd` or see setup-argocd.sh |
| Git | Already installed |



---

## Part 5 — How the Full CI/CD Flow Works

```
You: git push origin main
          │
          └─► Bitbucket Pipelines starts automatically
                │
                ├── Step 1: Test
                │     pip install → flake8 lint → import smoke test
                │
                ├── Step 2: Build & Push
                │     docker build ./app
                │     docker push sameerfencer/fluid-demo:a1b2c3d  (SHA tag)
                │     docker push sameerfencer/fluid-demo:latest
                │
                └── Step 3: Update GitOps manifest
                      sed replaces image tag in gitops/envs/dev/backend.yaml
                      git commit "ci: update dev image to a1b2c3d [skip ci]"
                      git push → triggers ArgoCD
                                    │
                                    └─► ArgoCD detects file changed
                                          kubectl apply gitops/envs/dev/
                                          Rolling update begins
                                          New pods come up → probes pass → old pods terminate
```
---

## Tradeoffs (Honest Assessment)

| What was simplified | What you'd do in production |
|-|-|
| NodePort (direct port) | Ingress with nginx-ingress + TLS via cert-manager |
| Single Redis replica | Redis Sentinel or Redis Cluster for HA |
| No persistent volume for Redis | PVC with StorageClass (data survives pod restarts) |
| Secrets in env vars | External Secrets Operator or HashiCorp Vault |
| No HPA | HorizontalPodAutoscaler on CPU/RPS metrics |
| No network policies | Restrict pod-to-pod traffic with NetworkPolicy |
| Bitbucket bot pushes to same repo | Separate GitOps repo (app code vs infra) |
| Minikube | EKS/GKE with proper node groups and IAM |

---

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /` | Service info |
| `GET /health` | Liveness probe — just checks process is alive |
| `GET /ready` | Readiness probe — pings Redis |
| `GET /count` | Increments visit counter in Redis |
| `GET /info` | Shows env vars and pod name |
