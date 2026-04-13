#!/usr/bin/env bash
set -euo pipefail

##
## Sets up a namespace with all agent-sandbox platform resources.
##
## Reusable for both the primary demo namespace and the pre-staged
## "ready" namespace. Handles: namespace creation, image pull secret,
## SCC, sandbox-router, template, warm pool, and network policy.
##
## Usage:
##   bash demo/setup-namespace.sh <namespace>
##   bash demo/setup-namespace.sh agent-demo-ready
##

NS="${1:?Usage: setup-namespace.sh <namespace>}"
SRC_NS="${SRC_NS:-agent-demo}"
OCP_REGISTRY="default-route-openshift-image-registry.apps.ocp.v7hjl.sandbox2288.opentlc.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " Setting up namespace: $NS"
echo "============================================"
echo ""

# --- 1. Create namespace ---
echo "[1/7] Creating namespace '$NS'..."
if oc get namespace "$NS" &>/dev/null; then
  echo "  Namespace already exists"
else
  oc new-project "$NS" --display-name="Agent Sandbox Demo" 2>/dev/null \
    || oc create namespace "$NS"
fi
echo ""

# --- 2. Image pull secret for OpenShift registry ---
echo "[2/7] Configuring image pull secret..."
if kubectl get secret ocp-registry-pull -n "$NS" &>/dev/null; then
  echo "  Secret already exists"
else
  OCP_TOKEN=$(oc whoami -t)
  kubectl create secret docker-registry ocp-registry-pull \
    -n "$NS" \
    --docker-server="$OCP_REGISTRY" \
    --docker-username="$(oc whoami)" \
    --docker-password="$OCP_TOKEN"
  echo "  Created ocp-registry-pull secret"
fi
kubectl patch sa default -n "$NS" \
  --type=json \
  -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name":"ocp-registry-pull"}}]' 2>/dev/null || true
echo ""

# --- 3. Grant anyuid SCC ---
echo "[3/7] Granting anyuid SCC to default SA..."
oc adm policy add-scc-to-user anyuid -z default -n "$NS" 2>/dev/null || true
echo "  Done"
echo ""

# --- 3b. Grant cross-namespace image pull (images live in SRC_NS) ---
if [[ "$NS" != "$SRC_NS" ]]; then
  echo "[3b/7] Granting image-puller access to $SRC_NS images..."
  oc policy add-role-to-user system:image-puller \
    "system:serviceaccount:${NS}:default" -n "$SRC_NS" 2>/dev/null || true
  echo "  Done"
  echo ""
fi

# --- 4. Deploy sandbox-router ---
echo "[4/7] Deploying sandbox-router..."
if kubectl get deployment sandbox-router -n "$NS" &>/dev/null; then
  echo "  Already deployed"
else
  # Only replace metadata.namespace; keep image refs pointing at source namespace
  sed "s/^  namespace: ${SRC_NS}/  namespace: ${NS}/g" \
    "$SCRIPT_DIR/sandbox-router.yaml" | kubectl apply -f -
  kubectl rollout status deployment/sandbox-router -n "$NS" --timeout=60s
fi
echo ""

# --- 5. Apply SandboxTemplate ---
echo "[5/7] Applying SandboxTemplate..."
# Replace metadata.namespace and namespaceSelector; keep image refs pointing at source namespace
sed "s/^  namespace: ${SRC_NS}/  namespace: ${NS}/g; s|kubernetes.io/metadata.name: ${SRC_NS}|kubernetes.io/metadata.name: ${NS}|g" \
  "$SCRIPT_DIR/02-restricted-profile-template.yaml" | kubectl apply -f -
echo ""

# --- 6. Apply NetworkPolicy ---
echo "[6/7] Applying NetworkPolicy..."
sed "s/^  namespace: ${SRC_NS}/  namespace: ${NS}/g; s|kubernetes.io/metadata.name: ${SRC_NS}|kubernetes.io/metadata.name: ${NS}|g" \
  "$SCRIPT_DIR/02-networkpolicy.yaml" | kubectl apply -f -
echo ""

# --- 7. Apply SandboxWarmPool and wait ---
echo "[7/7] Applying SandboxWarmPool..."
sed "s/^  namespace: ${SRC_NS}/  namespace: ${NS}/g" \
  "$SCRIPT_DIR/02-warmpool.yaml" | kubectl apply -f -

echo "  Waiting for warm pool pods to be ready (this takes 30-60s for Kata)..."
for i in $(seq 1 30); do
  READY=$(kubectl get sandboxwarmpool -n "$NS" -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get sandboxwarmpool -n "$NS" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "2")
  if [[ "$READY" -ge "$DESIRED" ]] 2>/dev/null; then
    echo "  ✓ Warm pool ready: $READY/$DESIRED"
    break
  fi
  echo "  Waiting... ($READY/$DESIRED ready)"
  sleep 5
done
echo ""

echo "============================================"
echo " Namespace '$NS' is ready"
echo "============================================"
echo ""
echo "  SandboxTemplate: restricted-profile"
echo "  SandboxWarmPool: $(kubectl get sandboxwarmpool -n "$NS" -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo '?') ready"
echo "  NetworkPolicy:   sandbox-restricted-egress"
echo "  Sandbox Router:  $(kubectl get deployment sandbox-router -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '?') replica(s)"
echo ""
echo "  Run the demo against this namespace:"
echo "    SANDBOX_NAMESPACE=$NS python3 demo/03-agent-demo.py"
echo "    cd demo && SANDBOX_NAMESPACE=$NS adk web"
