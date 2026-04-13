#!/usr/bin/env bash
set -euo pipefail

DEMO_NS="${DEMO_NS:-agent-demo}"
READY_NS="${READY_NS:-agent-demo-ready}"

echo "============================================"
echo " Agent Sandbox Demo Cleanup"
echo "============================================"
echo ""

cleanup_namespace() {
  local NS="$1"
  echo "--- Cleaning namespace: $NS ---"
  if ! oc get namespace "$NS" &>/dev/null; then
    echo "  Namespace does not exist, skipping"
    return
  fi
  kubectl delete sandboxclaim --all -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete sandboxwarmpool --all -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete sandboxtemplate --all -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete pod bare-agent -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete deployment sandbox-router -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete service sandbox-router-svc -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete networkpolicy sandbox-restricted-egress -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl delete sandbox --all -n "$NS" --ignore-not-found 2>/dev/null || true
  kubectl wait --for=delete pod --all -n "$NS" --timeout=120s 2>/dev/null || true
  echo "  Done"
  echo ""
}

cleanup_namespace "$DEMO_NS"
cleanup_namespace "$READY_NS"

echo "Demo resources cleaned up."
echo ""
echo "To also delete the namespaces:"
echo "  kubectl delete namespace $DEMO_NS $READY_NS"
