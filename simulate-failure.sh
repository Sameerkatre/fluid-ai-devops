#!/bin/bash
# =============================================================
# Fluid AI — Intentional Failure Simulation & Debug Script
# Failure: Bad REDIS_HOST env var → readiness probe fails
# =============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Step 1: Confirm everything is healthy BEFORE failure ===${NC}"
kubectl get pods
kubectl get svc
echo ""

# Get the service URL
MINIKUBE_IP=$(minikube ip)
SERVICE_URL="http://${MINIKUBE_IP}:30080"
echo "Service URL: $SERVICE_URL"
echo ""

echo -e "${GREEN}Testing /ready before failure:${NC}"
curl -s "$SERVICE_URL/ready" | python3 -m json.tool
echo ""

echo -e "${RED}=== Step 2: Inject failure — wrong REDIS_HOST ===${NC}"
kubectl set env deployment/backend REDIS_HOST=wrong-redis-host
echo "Bad env var injected. Watching pods..."
echo ""

sleep 5

echo -e "${YELLOW}=== Step 3: Observe failure symptoms ===${NC}"
echo "--- Pod status ---"
kubectl get pods
echo ""

echo "--- Describe deployment (look at Events + env) ---"
kubectl describe deployment backend | tail -30
echo ""

echo "--- Readiness probe is now failing: ---"
curl -s "$SERVICE_URL/ready" | python3 -m json.tool || echo "Service returning error"
echo ""

echo "--- Logs from backend pod (connection refused to wrong host) ---"
POD=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD" --tail=20
echo ""

echo -e "${YELLOW}=== Step 4: Debug reasoning ===${NC}"
cat << 'EOF'
Symptoms:
  - /ready returns 503 {"status": "not ready", "redis": "unreachable"}
  - Pods are Running but 0/1 READY (readiness probe failing)
  - Traffic is NOT sent to these pods (Kubernetes removes them from Service endpoints)

Debug steps taken:
  1. kubectl get pods          → pods Running but not Ready
  2. kubectl describe pod      → readiness probe failing on /ready
  3. curl /ready               → confirms Redis unreachable
  4. kubectl logs <pod>        → "Connection refused to wrong-redis-host:6379"
  5. kubectl get svc           → redis-service exists and is ClusterIP
  6. kubectl exec ping test    → redis-service resolves fine
  7. kubectl describe deploy   → REDIS_HOST=wrong-redis-host ← ROOT CAUSE

Root cause: REDIS_HOST env var points to non-existent hostname.
The readiness probe hits /ready which calls redis.ping() → fails → pod marked not ready.
Liveness probe hits /health which just returns 200 → pod NOT restarted (correct behaviour).
EOF
echo ""

echo -e "${GREEN}=== Step 5: Fix — restore correct REDIS_HOST ===${NC}"
kubectl set env deployment/backend REDIS_HOST=redis-service
echo "Watching rollout..."
kubectl rollout status deployment/backend --timeout=60s
echo ""

echo -e "${GREEN}=== Step 6: Verify recovery ===${NC}"
kubectl get pods
echo ""

sleep 5
echo "Testing /ready after fix:"
curl -s "$SERVICE_URL/ready" | python3 -m json.tool
echo ""

echo "Testing /count to confirm Redis is actually working:"
curl -s "$SERVICE_URL/count" | python3 -m json.tool
echo ""

echo -e "${GREEN}=== All done! Failure simulated, debugged, and fixed. ===${NC}"
