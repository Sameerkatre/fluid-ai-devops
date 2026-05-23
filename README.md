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

## Part 1 — Push to Bitbucket

### Step 1.1 — Clone / initialize the repo

```bash
# Navigate to wherever you store projects
cd ~/projects

# If you're starting fresh (no git history yet):
git clone https://bitbucket.org/sameerfencer/fluid-ai-devops.git
cd fluid-ai-devops

# Copy these project files into the cloned folder:
cp -r /path/to/downloaded/fluid-ai-devops/* .
```

> **Or** if you downloaded this ZIP and want to push it as a new repo:
>
> ```bash
> cd fluid-ai-devops   # the folder you extracted
> git init
> git remote add origin https://bitbucket.org/sameerfencer/fluid-ai-devops.git
> ```

### Step 1.2 — Replace YOUR_DOCKERHUB_USERNAME everywhere

Your Docker Hub username needs to go into the manifests. Run this from the repo root:

```bash
# Replace the placeholder with your actual Docker Hub username
# Example: sameerfencer  →  replace every occurrence

DOCKERHUB_USERNAME="YOUR_ACTUAL_USERNAME"   # ← change this

grep -rl "YOUR_DOCKERHUB_USERNAME" . | xargs sed -i "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USERNAME}|g"

# Verify
grep -r "YOUR_DOCKERHUB_USERNAME" .   # should return nothing
```

### Step 1.3 — Commit and push

```bash
git add .
git commit -m "feat: initial Fluid AI DevOps challenge setup"
git push -u origin main
```

---

## Part 2 — Set Up Bitbucket Pipeline Variables

Bitbucket Pipelines need your Docker Hub credentials to push images.

1. Go to: **Bitbucket → Repository → Repository Settings → Pipelines → Repository Variables**

2. Add these variables (mark both as **Secured**):

| Variable | Value | Secured |
|----------|-------|---------|
| `DOCKERHUB_USERNAME` | your Docker Hub username | No |
| `DOCKERHUB_TOKEN` | your Docker Hub access token | **Yes** |

> **How to get a Docker Hub token:**  
> Docker Hub → Account Settings → Security → New Access Token  
> Give it "Read, Write" permissions and copy the token.

3. Enable Pipelines: **Repository Settings → Pipelines → Enable Pipelines**

---

## Part 3 — Local Kubernetes Setup (Minikube)

### Step 3.1 — Set your username and run setup

```bash
# From the repo root
export DOCKERHUB_USERNAME="your_dockerhub_username"
chmod +x setup.sh
./setup.sh
```

This script:
1. Starts Minikube with 2 CPUs and 4GB RAM
2. Builds the Docker image directly inside Minikube (no push needed locally)
3. Deploys Redis and waits for it to be ready
4. Deploys the backend with readiness + liveness probes
5. Prints your service URL

### Step 3.2 — Verify everything works

```bash
MINIKUBE_IP=$(minikube ip)
BASE="http://${MINIKUBE_IP}:30080"

curl $BASE/           # → {"service": "fluid-ai-demo", "status": "ok"}
curl $BASE/health     # → {"status": "alive"}
curl $BASE/ready      # → {"status": "ready", "redis": "connected"}
curl $BASE/count      # → {"visits": 1, "message": "Counter incremented"}
curl $BASE/info       # → shows redis host, version, pod name
```

### Step 3.3 — Watch Kubernetes resources

```bash
# All pods (run in a separate terminal to watch live)
kubectl get pods -w

# Describe a pod (why is it pending/failing?)
kubectl describe pod <pod-name>

# Stream logs
kubectl logs -f deployment/backend

# Check that traffic endpoints are registered
kubectl get endpoints backend-service
```

---

## Part 4 — Install ArgoCD (GitOps layer)

```bash
chmod +x setup-argocd.sh

# Set Bitbucket credentials so ArgoCD can pull your repo:
export BB_USERNAME="sameerfencer"
export BB_APP_PASSWORD="your_bitbucket_app_password"
# (Bitbucket App Password: Bitbucket Settings → App Passwords → Create)

./setup-argocd.sh
```

### Access the ArgoCD UI

```bash
# In a separate terminal — keep this running while using ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open **https://localhost:8080** in your browser.  
Login: `admin` / (password printed by setup-argocd.sh)

You'll see three apps registered:
- `fluid-demo-dev` — auto-syncs on every push to main
- `fluid-demo-staging` — auto-syncs when staging manifest changes
- `fluid-demo-prod` — **manual sync only** (production safety)

### Manually trigger a sync

```bash
argocd app sync fluid-demo-dev
argocd app get fluid-demo-dev   # check sync status
```

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

> **Why `[skip ci]` in the commit message?**  
> Without it, the pipeline bot's git push would trigger another pipeline run — infinite loop.  
> Bitbucket Pipelines skips runs when `[skip ci]` is in the commit message.

---

## Part 6 — Reliability Feature: Readiness + Liveness Probes

### Why these were chosen
Probes are the foundation of everything. HPA, rolling updates, and service routing all depend on probes being correct. Without them, Kubernetes can't tell a healthy pod from a broken one.

### What each probe does

| Probe | Endpoint | Checks | On failure |
|-------|----------|--------|------------|
| **Liveness** | `/health` | Is the process alive? | Restart the container |
| **Readiness** | `/ready` | Can it reach Redis? | Remove from Service endpoints (no restarts) |

### The key insight
A pod can be **Running but not Ready**. This is exactly what the failure simulation demonstrates — Redis is unreachable, so `/ready` returns 503, pods go `0/1 READY`, but they're not restarted (liveness still passes). Traffic simply stops flowing to them. This is correct, graceful behaviour.

### Tradeoff
- `initialDelaySeconds` adds startup latency before the first probe check
- Too aggressive → unnecessary restarts during slow boot
- Too lenient → bad pods serve traffic too long

---

## Part 7 — Failure Simulation (Live Demo Script)

```bash
chmod +x simulate-failure.sh
./simulate-failure.sh
```

This script does everything live — shows healthy state, injects a bad `REDIS_HOST` env var, demonstrates pods going not-ready, debugs root cause step by step, and fixes it. Perfect for the video walkthrough.

Manual version of the same steps:

```bash
# 1. Confirm healthy
kubectl get pods
curl http://$(minikube ip):30080/ready

# 2. Inject bad env var (simulate misconfiguration)
kubectl set env deployment/backend REDIS_HOST=wrong-redis-host

# 3. Watch pods become not-ready
kubectl get pods -w   # 0/1 READY

# 4. Debug
kubectl describe pod <pod-name>     # Events: readiness probe failed
kubectl logs <pod-name> --tail=20   # Connection refused to wrong-redis-host
kubectl get endpoints backend-service   # No endpoints registered!

# 5. Fix
kubectl set env deployment/backend REDIS_HOST=redis-service
kubectl rollout status deployment/backend

# 6. Verify recovery
curl http://$(minikube ip):30080/ready   # → {"status": "ready"}
```

---

## Useful Debug Commands

```bash
# Real-time pod watch
kubectl get pods -w

# Why is a pod stuck?
kubectl describe pod <pod-name>

# Stream live logs
kubectl logs -f deployment/backend

# Stream logs from all pods with the 'backend' label
kubectl logs -f -l app=backend

# Are pods actually receiving traffic?
kubectl get endpoints backend-service

# Shell into a running pod
kubectl exec -it <pod-name> -- /bin/sh

# Rollback to the previous deployment revision
kubectl rollout undo deployment/backend

# View rollout history
kubectl rollout history deployment/backend

# Check resource usage
kubectl top pods

# Check ArgoCD app status
argocd app get fluid-demo-dev
argocd app list
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
