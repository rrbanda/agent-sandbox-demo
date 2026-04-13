#!/usr/bin/env bash
set -euo pipefail

##
## Builds the python-runtime and sandbox-router container images from the
## upstream agent-sandbox repo and pushes them to the OpenShift internal registry.
##
## Prerequisites: podman, oc (logged in), git
##
## Usage:
##   bash demo/build-images.sh
##

DEMO_NS="${DEMO_NS:-agent-demo}"
OCP_REGISTRY="default-route-openshift-image-registry.apps.ocp.v7hjl.sandbox2288.opentlc.com"
UPSTREAM_REPO="https://github.com/kubernetes-sigs/agent-sandbox.git"
UPSTREAM_REF="${UPSTREAM_REF:-main}"
BUILD_DIR="${BUILD_DIR:-/tmp/agent-sandbox-build}"
PLATFORM="${PLATFORM:-linux/amd64}"

RUNTIME_IMAGE="${OCP_REGISTRY}/${DEMO_NS}/python-runtime:latest"
ROUTER_IMAGE="${OCP_REGISTRY}/${DEMO_NS}/sandbox-router:latest"

echo "============================================"
echo " Building Agent Sandbox Images"
echo "============================================"
echo ""
echo "  Registry:  $OCP_REGISTRY"
echo "  Namespace: $DEMO_NS"
echo "  Platform:  $PLATFORM"
echo ""

# --- 1. Clone upstream (sparse checkout for speed) ---
echo "[1/5] Cloning upstream repo (sparse)..."
if [ -d "$BUILD_DIR" ]; then
  echo "  Build dir exists, pulling latest..."
  cd "$BUILD_DIR" && git pull --ff-only 2>/dev/null || true
else
  git clone --depth 1 --filter=blob:none --sparse "$UPSTREAM_REPO" "$BUILD_DIR"
  cd "$BUILD_DIR"
  git sparse-checkout set \
    examples/python-runtime-sandbox \
    clients/python/agentic-sandbox-client/sandbox-router
fi
cd "$BUILD_DIR"
echo ""

# --- 2. Login to OpenShift registry ---
echo "[2/5] Logging in to OpenShift registry..."
OCP_TOKEN=$(oc whoami -t)
podman login "$OCP_REGISTRY" \
  -u "$(oc whoami)" \
  -p "$OCP_TOKEN" \
  --tls-verify=false
echo ""

# --- 3. Build python-runtime ---
echo "[3/5] Building python-runtime image..."
podman build \
  --platform "$PLATFORM" \
  -t "$RUNTIME_IMAGE" \
  -f examples/python-runtime-sandbox/Dockerfile \
  examples/python-runtime-sandbox/
echo ""

# --- 4. Build sandbox-router ---
echo "[4/5] Building sandbox-router image..."
podman build \
  --platform "$PLATFORM" \
  -t "$ROUTER_IMAGE" \
  -f clients/python/agentic-sandbox-client/sandbox-router/Dockerfile \
  clients/python/agentic-sandbox-client/sandbox-router/
echo ""

# --- 5. Push images ---
echo "[5/5] Pushing images to OpenShift registry..."
podman push "$RUNTIME_IMAGE" --tls-verify=false
podman push "$ROUTER_IMAGE" --tls-verify=false
echo ""

echo "============================================"
echo " Images built and pushed successfully"
echo "============================================"
echo ""
echo "  python-runtime: $RUNTIME_IMAGE"
echo "  sandbox-router: $ROUTER_IMAGE"
echo ""
echo "Internal references (for YAML manifests):"
echo "  python-runtime: image-registry.openshift-image-registry.svc:5000/${DEMO_NS}/python-runtime:latest"
echo "  sandbox-router: image-registry.openshift-image-registry.svc:5000/${DEMO_NS}/sandbox-router:latest"
