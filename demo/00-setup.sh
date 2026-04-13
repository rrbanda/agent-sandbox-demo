#!/usr/bin/env bash
set -euo pipefail

DEMO_NS="${DEMO_NS:-agent-demo}"
CONTROLLER_VERSION="${CONTROLLER_VERSION:-v0.2.1}"
OCP_API="${OCP_API:-https://api.ocp.v7hjl.sandbox2288.opentlc.com:6443}"
OCP_USER="${OCP_USER:-admin}"
OCP_PASS="${OCP_PASS:-admin123}"

echo "============================================"
echo " Agent Sandbox + Kata Demo Setup"
echo "============================================"
echo ""

# --- 1. Login to OpenShift ---
echo "[1/8] Logging in to OpenShift..."
if ! oc whoami &>/dev/null; then
  oc login "$OCP_API" -u "$OCP_USER" -p "$OCP_PASS" --insecure-skip-tls-verify=true
fi
echo "  Logged in as: $(oc whoami)"
echo ""

# --- 2. Check agent-sandbox controller ---
echo "[2/8] Checking agent-sandbox controller..."
CURRENT_IMAGE=$(oc get deployment agent-sandbox-controller -n agent-sandbox-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "not-installed")

if [[ "$CURRENT_IMAGE" == "not-installed" ]]; then
  echo "  Installing agent-sandbox $CONTROLLER_VERSION..."
  kubectl apply -f "https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${CONTROLLER_VERSION}/manifest.yaml"
  kubectl apply -f "https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${CONTROLLER_VERSION}/extensions.yaml"
  kubectl rollout status deployment/agent-sandbox-controller -n agent-sandbox-system --timeout=120s
else
  echo "  Controller found: $CURRENT_IMAGE"
fi
echo ""

# --- 3. Create demo namespace ---
echo "[3/8] Creating namespace '$DEMO_NS'..."
if oc get namespace "$DEMO_NS" &>/dev/null; then
  echo "  Namespace already exists"
else
  oc new-project "$DEMO_NS" --display-name="Agent Sandbox Demo" 2>/dev/null \
    || oc create namespace "$DEMO_NS"
fi
oc project "$DEMO_NS"
echo ""

# --- 4. Verify CRDs ---
echo "[4/8] Verifying agent-sandbox CRDs..."
for CRD in sandboxes.agents.x-k8s.io \
            sandboxtemplates.extensions.agents.x-k8s.io \
            sandboxclaims.extensions.agents.x-k8s.io \
            sandboxwarmpools.extensions.agents.x-k8s.io; do
  if kubectl get crd "$CRD" &>/dev/null; then
    echo "  ✓ $CRD"
  else
    echo "  ✗ $CRD -- MISSING"
    exit 1
  fi
done
echo ""

# --- 5. Verify Kata ---
echo "[5/8] Verifying Kata Containers..."
if kubectl get runtimeclass kata-remote &>/dev/null; then
  echo "  ✓ kata-remote RuntimeClass available"
else
  echo "  ✗ kata-remote not found. Kata Containers must be installed."
  echo "    On OpenShift: install the Sandboxed Containers operator"
  exit 1
fi
KATA_NODES=$(kubectl get nodes -l node-role.kubernetes.io/kata-oc= --no-headers 2>/dev/null | wc -l)
echo "  ✓ $KATA_NODES nodes with Kata support"
echo ""

# --- 6. Build container images ---
echo "[6/8] Checking container images..."
IMAGES_MISSING=false
if ! oc get istag python-runtime:latest -n "$DEMO_NS" &>/dev/null; then
  IMAGES_MISSING=true
fi
if ! oc get istag sandbox-router:latest -n "$DEMO_NS" &>/dev/null; then
  IMAGES_MISSING=true
fi
if [[ "$IMAGES_MISSING" == "true" ]]; then
  echo "  Images not found -- building now..."
  bash "$(dirname "$0")/build-images.sh"
else
  echo "  ✓ python-runtime image exists"
  echo "  ✓ sandbox-router image exists"
fi
echo ""

# --- 7. Set up primary demo namespace (platform resources for Act 2 console walkthrough) ---
echo "[7/8] Setting up '$DEMO_NS' namespace (platform resources for console walkthrough)..."
bash "$(dirname "$0")/setup-namespace.sh" "$DEMO_NS"
echo ""

# --- 8. Check Python SDK ---
echo "[8/8] Checking Python dependencies..."
python3 -c "import k8s_agent_sandbox" &>/dev/null \
  && echo "  ✓ k8s-agent-sandbox SDK installed" \
  || echo "  ✗ SDK missing -- run: pip install k8s-agent-sandbox"
python3 -c "import google.adk" &>/dev/null \
  && echo "  ✓ google-adk installed" \
  || echo "  ✗ ADK missing -- run: pip install google-adk"
echo ""


echo "============================================"
echo " Setup complete"
echo "============================================"
echo ""
echo "LLM endpoint (no API key needed):"
echo "  gpt-oss-120b via on-cluster vLLM"
echo "  https://gpt-oss-120b-gpt-oss-120b.apps.ocp.v7hjl.sandbox2288.opentlc.com/v1"
echo ""
echo "OpenShift Console:"
echo "  https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com"
echo ""
echo "Next steps (run in separate terminals before demo):"
echo ""
echo "  Terminal 1 -- port-forward to sandbox-router:"
echo "    kubectl port-forward svc/sandbox-router-svc -n $DEMO_NS 8090:8080"
echo ""
echo "  Terminal 2 -- start ADK web server:"
echo "    cd demo && adk web"
echo ""
echo "  Then open http://127.0.0.1:8000 and follow demo/RUNBOOK.md"
echo ""
echo "  Cleanup: bash demo/99-cleanup.sh"
