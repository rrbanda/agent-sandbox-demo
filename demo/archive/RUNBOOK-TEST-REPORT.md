# RUNBOOK Blind Demo Test -- Results

**Date:** 2026-04-12
**Tester:** Automated (following RUNBOOK.md instructions literally, step by step)
**Source:** [demo/RUNBOOK.md](RUNBOOK.md)

---

## Phase 0: Clean Slate

| Step | Result | Notes |
|---|---|---|
| `bash demo/99-cleanup.sh` | **PASS** | Both namespaces cleaned |
| `kubectl delete namespace agent-demo agent-demo-ready` | **PASS** | Namespaces deleted |
| Verify controller running | **PASS** | 1/1 ready, v0.2.1 in agent-sandbox-system |

---

## Phase 1: Pre-Demo Checklist

| Step | Result | Notes |
|---|---|---|
| `bash demo/00-setup.sh` | **PASS** | All 9 steps completed successfully |
| [1/9] Login | **PASS** | Logged in as admin |
| [2/9] Controller check | **PASS** | v0.2.1 found |
| [3/9] Namespace creation | **PASS** | agent-demo created |
| [4/9] CRDs | **PASS** | All 4 CRDs verified |
| [5/9] Kata | **PASS** | kata-remote RuntimeClass, 5 nodes |
| [6/9] Images | **PASS** | Images not found, built automatically (~6s, cached) |
| [7/9] Platform resources (agent-demo) | **PASS** | SandboxTemplate, WarmPool, NetworkPolicy, sandbox-router deployed |
| [8/9] Python SDK | **PASS** | Both k8s-agent-sandbox and google-adk installed |
| [9/9] Pre-stage agent-demo-ready | **PASS** | Warm pool 2/2 ready (~75s for Kata cold start) |
| Warm pool verification command | **PASS** | `kubectl get sandboxwarmpool -n agent-demo-ready -o jsonpath='{.items[0].status.readyReplicas}'` printed `2` |
| agent-demo warm pool | **PASS** | Also 2/2 ready |

Total setup time: ~195s (3m 15s).

---

## Phase 2: Act 1 -- The Threat

| Step | Result | Notes |
|---|---|---|
| `kubectl apply -f demo/01-bare-pod.yaml` | **PASS** | `pod/bare-agent created` -- matches RUNBOOK |
| `kubectl wait ...` | **PASS** | `pod/bare-agent condition met` -- matches RUNBOOK |
| `python3 demo/01-attack-script.py` | **PASS** | All 3 attacks produced expected output |

**Output vs RUNBOOK EXPECT:**

| Attack | RUNBOOK EXPECT | Actual | Match? |
|---|---|---|---|
| Metadata (169.254.169.254) | `REACHED: connection refused (network NOT blocked by policy)` | Same | Yes |
| Result line | `REACHABLE (network NOT blocked -- no NetworkPolicy)` | Same | Yes |
| Internal gateway | `Internal gateway (10.0.0.1:443): timeout (but NOT blocked by policy)` | Same | Yes |
| K8s API | `K8s API (ClusterIP) (172.30.0.1:443): CONNECTED` | Same | Yes |
| SA token | `Found 4 files:` + token preview | Same (full file content shown) | Yes |
| Summary | `All attacks succeeded or reached their targets.` | Same | Yes |

**Gap found (FIXED):** RUNBOOK EXPECT block was missing the second SUMMARY line: `This is what happens when agents run in standard pods.` Added to RUNBOOK.

---

## Phase 3: Act 2 -- Console URLs

| # | URL Target | Result | What Was Visible |
|---|---|---|---|
| 1 | Sandboxed Containers Operator CSV | **PASS** | "OpenShift sandboxed containers Operator 1.12.0" with "Succeeded" status |
| 2 | agent-sandbox-controller deployment | **PASS** | Deployment details page, 1 Pod, namespace `agent-sandbox-system`, label `app=agent-sandbox-controller` |
| 3 | SandboxTemplate (agent-demo) | **PASS** | `restricted-profile` listed |
| 4 | SandboxWarmPool (agent-demo) | **PASS** | `restricted-pool` listed |
| 5 | NetworkPolicies (agent-demo) | **PASS** | `sandbox-restricted-egress` listed |
| 6 | Sandboxes (agent-demo) | **PASS** | "No Sandboxes found" |
| 7 | Sandboxes (agent-demo-ready) | **PASS** | "No Sandboxes found" |

All 7 URLs loaded correctly. Content matches RUNBOOK's `AUDIENCE SEES` descriptions.

---

## Phase 4: Act 3 -- SDK Demo Script

```
SANDBOX_NAMESPACE=agent-demo-ready python3 demo/03-agent-demo.py
```

| Step | Result | Actual Output |
|---|---|---|
| Step 1: Sandbox creation | **PASS** | Claimed in 0.3s (from warm pool) |
| Step 2: Fibonacci execution | **PASS** | `[0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181]` |
| Step 3: Metadata probe | **PASS** | `ISOLATED -- Kata VM metadata only (not host credentials)` |
| Step 3: Internal net probe | **PASS** | `BLOCKED -- timed out (NetworkPolicy)` |
| Step 3: SA token probe | **PASS** | `NOT FOUND (automountServiceAccountToken=false)` |
| Step 3: Capabilities probe | **PASS** | `0000000000000000 (ALL dropped)` |
| Step 4: Destruction | **PASS** | `Terminated in 0.0s` |
| Punchline output | **PASS** | All lines match RUNBOOK |

All 4 steps and all 4 security probes match RUNBOOK EXPECT blocks exactly. Total script runtime: ~7s.

---

## Phase 5: Act 3b -- ADK Web UI

| Step | Result | Notes |
|---|---|---|
| `cd demo && SANDBOX_NAMESPACE=agent-demo-ready adk web` | **PASS** | Server started on http://127.0.0.1:8000 |
| Terminal EXPECT output | **PASS** | `Started server process`, `Application startup complete`, `Uvicorn running on http://127.0.0.1:8000` |
| Page loads | **PASS** | ADK Dev UI visible |
| `coding_agent` visible | **PASS** | Selected in sidebar dropdown |

### Fibonacci prompt testing

| Prompt | Result | Notes |
|---|---|---|
| "Write a Python script that calculates the first 20 Fibonacci numbers and prints them." | **FAIL** | LLM thought: "Just give code. No need to execute." -- generated code text without calling `execute_python`. Sandbox was NOT invoked. |
| "Run Python code to calculate and print the first 20 Fibonacci numbers. Execute it in the sandbox." | **PASS** | LLM thought: "Use the execute_python tool." -- called `execute_python`, sandbox created, output: `[0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181]` |

**Gap found (FIXED):** The RUNBOOK's original Fibonacci prompt ("Write a Python script...") is unreliable with gpt-oss-120b. The LLM sometimes outputs code without executing it in the sandbox, defeating the demo's purpose. Changed RUNBOOK prompt to: "Run Python code to calculate and print the first 20 Fibonacci numbers. Execute it in the sandbox." with a note explaining why this phrasing is needed.

---

## Phase 6: Cleanup

| Step | Result | Notes |
|---|---|---|
| `bash demo/99-cleanup.sh` | **PASS** | Both namespaces cleaned (~38s) |
| agent-demo resources deleted | **PASS** | WarmPool, Template, bare-agent, sandbox-router, NetworkPolicy |
| agent-demo-ready resources deleted | **PASS** | WarmPool, Template, sandbox-router, NetworkPolicy |

---

## Phase 7: Appendix Consistency Check

### Command Cheat Sheet vs Inline Commands

| Cheat Sheet Command | Inline Location | Match? |
|---|---|---|
| `bash demo/00-setup.sh` | Pre-Demo Checklist | Yes |
| `kubectl apply -f demo/01-bare-pod.yaml` | Act 1, Step 1 | Yes |
| `kubectl wait --for=condition=Ready pod/bare-agent -n agent-demo --timeout=60s` | Act 1, Step 1 | Yes |
| `python3 demo/01-attack-script.py` | Act 1, Step 2 | Yes |
| `SANDBOX_NAMESPACE=agent-demo-ready python3 demo/03-agent-demo.py` | Act 3 | Yes |
| `cd demo && SANDBOX_NAMESPACE=agent-demo-ready adk web` | Act 3b | Yes |
| `bash demo/99-cleanup.sh` | Cleanup | Yes |

### Console URL Cheat Sheet vs Inline URLs

| # | Cheat Sheet URL | Inline Location | Match? |
|---|---|---|---|
| 1 | `.../openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion` | Act 2, Step 1 | Yes |
| 2 | `.../agent-sandbox-system/deployments/agent-sandbox-controller` | Act 2, Step 2 | Yes |
| 3 | `.../agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate` | Act 2, Step 3 | Yes |
| 4 | `.../agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool` | Act 2, Step 4 | Yes |
| 5 | `.../agent-demo/networkpolicies` | Act 2, Step 5 | Yes |
| 6 | `.../agent-demo/agents.x-k8s.io~v1alpha1~Sandbox` | Act 2, Step 6 | Yes |
| 7 | `.../agent-demo-ready/agents.x-k8s.io~v1alpha1~Sandbox` | Act 2 transition | Yes |

**Result:** No mismatches. All appendix entries match their inline counterparts exactly.

---

## Summary

| Phase | Pass/Fail | Gaps Found |
|---|---|---|
| Phase 0: Clean Slate | **PASS** | -- |
| Phase 1: Pre-Demo Checklist | **PASS** | -- |
| Phase 2: Act 1 (attacks) | **PASS** | 1 minor (missing SUMMARY line in EXPECT) |
| Phase 3: Act 2 (console URLs) | **PASS** | -- |
| Phase 4: Act 3 (SDK script) | **PASS** | -- |
| Phase 5: Act 3b (ADK web UI) | **PASS** (after fix) | 1 significant (Fibonacci prompt wording) |
| Phase 6: Cleanup | **PASS** | -- |
| Phase 7: Appendix consistency | **PASS** | -- |

### All Fixes Applied

| File | Fix |
|---|---|
| `demo/RUNBOOK.md` | Added missing SUMMARY line `This is what happens when agents run in standard pods.` to Act 1 EXPECT block |
| `demo/RUNBOOK.md` | Changed Fibonacci prompt from "Write a Python script..." to "Run Python code to calculate and print... Execute it in the sandbox." with explanatory note about LLM tool-calling reliability |

### Remaining Notes (Not Bugs)

- **LLM non-determinism:** The gpt-oss-120b model sometimes refuses to use the `execute_python` tool when the prompt says "Write a script." The fix (prompt rewording) is reliable but the presenter should be aware that LLM responses are inherently non-deterministic. If the tool is not called on the first try, the presenter can rephrase or send a follow-up message like "Now execute it in the sandbox."
- **Console load times:** Each console URL takes ~3-5s to load. Pre-loading tabs is recommended.
- **Kata cold start:** Warm pool takes ~75s to cold-start. Run `00-setup.sh` at least 2 minutes before the demo.
- **Timing variance:** Warm pool claim times vary between 0.3-0.5s (RUNBOOK says "0.4s"). This is normal and does not affect the narrative.
