#!/bin/bash
# ============================================================
# ArgoCD Local Setup Script
# Run AFTER setup.sh — installs ArgoCD in your Minikube cluster
# and registers the Bitbucket repo + app definitions.
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ARGOCD] $1${NC}"; }
info() { echo -e "${CYAN}[INFO]   $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN]   $1${NC}"; }

# ── CONFIG: Bitbucket credentials ─────────────────────────
# Export these before running:
#   export BB_USERNAME=sameerfencer
#   export BB_APP_PASSWORD=your_bitbucket_app_password
BB_USERNAME="${BB_USERNAME:-}"
BB_APP_PASSWORD="${BB_APP_PASSWORD:-}"
REPO_URL="https://bitbucket.org/sameerfencer/fluid-ai-devops"
# ──────────────────────────────────────────────────────────

# ── Step 1: Install ArgoCD ────────────────────────────────
log "=== Step 1: Installing ArgoCD ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for ArgoCD to be ready (this takes ~2 minutes)..."
kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd
echo ""

# ── Step 2: Get the initial admin password ────────────────
log "=== Step 2: ArgoCD Initial Password ==="
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo ""
info "  ArgoCD admin password: ${ARGOCD_PASSWORD}"
info "  Save this — you'll use it to log in."
echo ""

# ── Step 3: Port-forward ArgoCD UI ───────────────────────
log "=== Step 3: Port-Forwarding ArgoCD UI ==="
info "  Run this in a separate terminal to access the ArgoCD UI:"
echo ""
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
info "  Then open: https://localhost:8080"
info "  Login: admin / ${ARGOCD_PASSWORD}"
echo ""

# ── Step 4: Install ArgoCD CLI ───────────────────────────
log "=== Step 4: ArgoCD CLI Login ==="
if ! command -v argocd &>/dev/null; then
  warn "  argocd CLI not found. Install it:"
  echo ""
  echo "    # Mac:"
  echo "    brew install argocd"
  echo ""
  echo "    # Linux:"
  echo "    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
  echo "    chmod +x /usr/local/bin/argocd"
  echo ""
  echo "  After installing, run:"
  echo "    argocd login localhost:8080 --username admin --password '${ARGOCD_PASSWORD}' --insecure"
else
  info "  argocd CLI found. Logging in..."
  # Port-forward in background for login
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &>/dev/null &
  PF_PID=$!
  sleep 3
  argocd login localhost:8080 \
    --username admin \
    --password "${ARGOCD_PASSWORD}" \
    --insecure
  kill $PF_PID 2>/dev/null || true
fi
echo ""

# ── Step 5: Register Bitbucket repo (if credentials set) ─
if [[ -n "$BB_USERNAME" && -n "$BB_APP_PASSWORD" ]]; then
  log "=== Step 5: Registering Bitbucket Repo with ArgoCD ==="
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &>/dev/null &
  PF_PID=$!
  sleep 3
  argocd repo add "${REPO_URL}" \
    --username "${BB_USERNAME}" \
    --password "${BB_APP_PASSWORD}" \
    --insecure
  kill $PF_PID 2>/dev/null || true
  info "  Repo registered: ${REPO_URL}"
else
  warn "  Skipping repo registration (BB_USERNAME / BB_APP_PASSWORD not set)."
  warn "  After setting them, run:"
  echo ""
  echo "    argocd login localhost:8080 --username admin --password '${ARGOCD_PASSWORD}' --insecure"
  echo "    argocd repo add ${REPO_URL} --username \$BB_USERNAME --password \$BB_APP_PASSWORD --insecure"
fi
echo ""

# ── Step 6: Apply ArgoCD App Definitions ─────────────────
log "=== Step 6: Registering ArgoCD Applications ==="
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-staging.yaml
kubectl apply -f argocd/app-prod.yaml
info "  Three apps registered: fluid-demo-dev, fluid-demo-staging, fluid-demo-prod"
echo ""

log "=== ArgoCD Setup Complete! ==="
echo ""
echo -e "${YELLOW}  Next steps:${NC}"
echo "  1. Open ArgoCD UI:        kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Login:                 https://localhost:8080  (admin / ${ARGOCD_PASSWORD})"
echo "  3. Watch dev auto-sync:   argocd app get fluid-demo-dev"
echo "  4. Trigger sync manually: argocd app sync fluid-demo-dev"
echo ""
