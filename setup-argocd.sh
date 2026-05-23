#!/bin/bash
# ================================================================
# ArgoCD Setup Script — fluid-ai-devops
# - Installs ArgoCD
# - Creates new user: sameer  (password you set below)
# - Registers GitHub repo
# - Applies app-dev, app-staging, app-prod
# ================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ARGOCD] $1${NC}"; }
info() { echo -e "${CYAN}[INFO]   $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN]   $1${NC}"; }
err()  { echo -e "${RED}[ERROR]  $1${NC}"; }

# ── CONFIG ────────────────────────────────────────────────────────
NEW_USER="sameer"
NEW_PASSWORD="Sameer@1234"        # ← change this after first login
GITHUB_REPO="https://github.com/Sameerkatre/fluid-ai-devops.git"
ARGOCD_NS="argocd"
# ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ArgoCD Setup — fluid-ai-devops              ║${NC}"
echo -e "${GREEN}║      New user: sameer                            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 1 — Install ArgoCD"
# ════════════════════════════════════════════════════════════════
kubectl create namespace $ARGOCD_NS --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n $ARGOCD_NS \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for argocd-server to be ready (~2 min)..."
kubectl wait --for=condition=available --timeout=180s \
  deployment/argocd-server -n $ARGOCD_NS
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 2 — Get existing admin password"
# ════════════════════════════════════════════════════════════════
ADMIN_PASSWORD=$(kubectl -n $ARGOCD_NS get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -z "$ADMIN_PASSWORD" ]; then
  warn "Initial admin secret not found — admin password was already changed."
  echo -n "Enter your current admin password: "
  read -s ADMIN_PASSWORD
  echo ""
fi

info "Admin password retrieved."
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 3 — Install ArgoCD CLI"
# ════════════════════════════════════════════════════════════════
if ! command -v argocd &>/dev/null; then
  info "Installing ArgoCD CLI..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install argocd
  else
    curl -sSL -o /usr/local/bin/argocd \
      https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
  fi
  info "ArgoCD CLI installed."
else
  info "ArgoCD CLI already installed: $(argocd version --client --short 2>/dev/null)"
fi
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 4 — Port-forward ArgoCD and login as admin"
# ════════════════════════════════════════════════════════════════
info "Starting port-forward on localhost:8080..."
kubectl port-forward svc/argocd-server -n $ARGOCD_NS 8080:443 &>/dev/null &
PF_PID=$!
sleep 4

argocd login localhost:8080 \
  --username admin \
  --password "$ADMIN_PASSWORD" \
  --insecure
info "Logged in as admin."
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 5 — Create new user: $NEW_USER"
# ════════════════════════════════════════════════════════════════

# Add sameer to argocd-cm configmap
kubectl patch configmap argocd-cm \
  -n $ARGOCD_NS \
  --type merge \
  -p "{\"data\":{\"accounts.${NEW_USER}\":\"apiKey, login\",\"admin.enabled\":\"true\"}}"

info "User '$NEW_USER' added to argocd-cm. Waiting for server to reload..."
sleep 6

# Set sameer's password via ArgoCD CLI
argocd account update-password \
  --account "$NEW_USER" \
  --new-password "$NEW_PASSWORD" \
  --current-password "$ADMIN_PASSWORD"

info "Password set for '$NEW_USER'."
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 6 — Apply RBAC: give $NEW_USER admin role"
# ════════════════════════════════════════════════════════════════
kubectl apply -f argocd/argocd-rbac-cm.yaml
info "RBAC applied — $NEW_USER has role:admin."
sleep 3
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 7 — Verify login as $NEW_USER"
# ════════════════════════════════════════════════════════════════
argocd login localhost:8080 \
  --username "$NEW_USER" \
  --password "$NEW_PASSWORD" \
  --insecure
info "Login as '$NEW_USER' successful."
argocd account get-user-info
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 8 — Register GitHub repo (public repo, no token needed)"
# ════════════════════════════════════════════════════════════════
argocd repo add "$GITHUB_REPO" \
  --insecure-skip-server-verification 2>/dev/null \
  && info "GitHub repo registered." \
  || warn "Repo may already be registered — continuing."
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 9 — Create fluid-demo namespace"
# ════════════════════════════════════════════════════════════════
kubectl create namespace fluid-demo --dry-run=client -o yaml | kubectl apply -f -
info "Namespace fluid-demo ready."
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 10 — Apply ArgoCD Application manifests"
# ════════════════════════════════════════════════════════════════
kubectl apply -f argocd/app-dev.yaml
info "fluid-demo-dev registered."

kubectl apply -f argocd/app-prod.yaml
info "fluid-demo-prod registered."
echo ""

# ════════════════════════════════════════════════════════════════
log "STEP 11 — Trigger first sync for dev"
# ════════════════════════════════════════════════════════════════
sleep 5
argocd app sync fluid-demo-dev --insecure 2>/dev/null \
  && info "fluid-demo-dev sync triggered." \
  || warn "Sync will happen automatically — check UI."
echo ""

# Kill port-forward
kill $PF_PID 2>/dev/null || true

# ════════════════════════════════════════════════════════════════
log "STEP 12 — Final status"
# ════════════════════════════════════════════════════════════════
kubectl port-forward svc/argocd-server -n $ARGOCD_NS 8080:443 &>/dev/null &
PF_PID=$!
sleep 3
argocd app list --insecure 2>/dev/null || true
kill $PF_PID 2>/dev/null || true

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Setup Complete!                          ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  UI:       https://localhost:8080                         ║${NC}"
echo -e "${GREEN}║  Username: ${NEW_USER}                                          ║${NC}"
echo -e "${GREEN}║  Password: ${NEW_PASSWORD}                                  ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║  To open UI run:                                          ║${NC}"
echo -e "${GREEN}║  kubectl port-forward svc/argocd-server -n argocd 8080:443║${NC}"
echo -e "${GREEN}║  Then open: https://localhost:8080                        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠  Change your password after first login:${NC}"
echo "   argocd account update-password --account $NEW_USER"
echo ""
