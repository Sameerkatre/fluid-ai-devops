#!/bin/bash
# ============================================================
# Fluid AI DevOps Challenge — Local Setup Script
# Works on Mac (Docker Desktop) and Linux
#
# Run: chmod +x setup.sh && ./setup.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── CONFIG ───────────────────────────────────────────────────
# Set your Docker Hub username here OR export it before running:
#   export DOCKERHUB_USERNAME=sameerfencer
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-YOUR_DOCKERHUB_USERNAME}"
IMAGE_NAME="fluid-demo"
IMAGE_TAG="local"
# ─────────────────────────────────────────────────────────────

log()  { echo -e "${GREEN}[SETUP] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN]  $1${NC}"; }
fail() { echo -e "${RED}[FAIL]  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}[INFO]  $1${NC}"; }

# ── Pre-flight checks ────────────────────────────────────────
log "=== Pre-flight: Checking required tools ==="
for cmd in docker minikube kubectl; do
  if command -v "$cmd" &>/dev/null; then
    info "  ✓ $cmd found: $(${cmd} version --short 2>/dev/null || ${cmd} --version | head -1)"
  else
    fail "$cmd is not installed. See README.md for install links."
  fi
done
echo ""

if [[ "$DOCKERHUB_USERNAME" == "YOUR_DOCKERHUB_USERNAME" ]]; then
  fail "Set your Docker Hub username: export DOCKERHUB_USERNAME=yourusername"
fi

# ── Step 1: Start Minikube ───────────────────────────────────
log "=== Step 1: Starting Minikube ==="
if minikube status | grep -q "Running"; then
  info "  Minikube already running — skipping start"
else
  minikube start --cpus=2 --memory=4096 --driver=docker
fi
echo ""

# ── Step 2: Build Docker image inside Minikube ───────────────
log "=== Step 2: Building Docker image inside Minikube ==="
info "  Pointing Docker CLI at Minikube's daemon (no push to Hub needed locally)"
eval "$(minikube docker-env)"
docker build -t "${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}" ./app
info "  Image built: ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# ── Step 3: Patch the image reference in k8s manifests ───────
log "=== Step 3: Patching k8s/backend.yaml with your image ==="
# Replace placeholder with your real username and 'local' tag
sed "s|YOUR_DOCKERHUB_USERNAME/fluid-demo:latest|${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}|g" \
  k8s/backend.yaml > /tmp/backend-patched.yaml
info "  Patched image: ${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
# Use imagePullPolicy: Never for local (image is already in Minikube's daemon)
sed -i 's|imagePullPolicy: Always|imagePullPolicy: Never|g' /tmp/backend-patched.yaml
echo ""

# ── Step 4: Deploy Redis ─────────────────────────────────────
log "=== Step 4: Deploying Redis ==="
kubectl apply -f k8s/redis.yaml
info "  Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=redis --timeout=60s
echo ""

# ── Step 5: Deploy Backend ───────────────────────────────────
log "=== Step 5: Deploying Backend ==="
kubectl apply -f /tmp/backend-patched.yaml
info "  Waiting for rollout to complete..."
kubectl rollout status deployment/backend --timeout=90s
echo ""

# ── Step 6: Status check ─────────────────────────────────────
log "=== Step 6: Deployment Status ==="
kubectl get pods -o wide
echo ""
kubectl get svc
echo ""

# ── Step 7: Service URL ──────────────────────────────────────
log "=== Step 7: Your app is running! ==="
MINIKUBE_IP=$(minikube ip)
BASE="http://${MINIKUBE_IP}:30080"
echo ""
echo -e "${CYAN}  Service URL: ${BASE}${NC}"
echo ""
echo -e "${YELLOW}  Quick smoke tests:${NC}"
echo "    curl ${BASE}/"
echo "    curl ${BASE}/health"
echo "    curl ${BASE}/ready"
echo "    curl ${BASE}/count"
echo "    curl ${BASE}/info"
echo ""
echo -e "${GREEN}=== Setup complete! ===${NC}"
echo ""
echo -e "${YELLOW}  To run the failure simulation:${NC}"
echo "    chmod +x simulate-failure.sh && ./simulate-failure.sh"
