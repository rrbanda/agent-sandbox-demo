# Agent Sandbox Demo -- Presenter Runbook

**This document is your single reference during the live demo. Do not show it to the audience.**

**Duration:** ~20 minutes
**Audience:** Agent experts + executive
**Format:** Tell-Show-Tell (slide, console walkthrough, ADK web UI, slides)
**Environment:** OpenShift 4.20, agent-sandbox v0.2.1, Kata Containers, gpt-oss-120b on-cluster LLM
**Console:** https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com

---

## Pre-Demo Checklist

Run at least 5 minutes before the audience arrives:

```bash
cd /path/to/agent-sandbox-demo
bash demo/00-setup.sh
```

This sets up everything: login, controller, CRDs, Kata, images, platform resources, and waits for warm pool readiness (2/2 ready). The audience never sees this.

After setup completes, start these in separate terminals:

**Terminal 1** -- port-forward to the sandbox-router:

```bash
kubectl port-forward svc/sandbox-router-svc -n agent-demo 8090:8080
```

**Terminal 2** -- ADK web server:

```bash
cd demo && adk web
```

Open these before you begin:

1. **Slides** -- in presenter mode, opening slide showing
2. **Browser tab 1** -- OpenShift Console, logged in
3. **Browser tab 2** -- `http://127.0.0.1:8000` (ADK web UI, already running)

---
---

# TELL -- Opening (4 min, slides)

---

## Slides 1-2: Title + Agenda

(Your deck's opening slides. Follow whatever is on screen.)

---

## Slide 3: Isolation Profiles + Secure Baseline

**SAY:**

> "Every profile has the full secure baseline -- Authentication, Authorization, Encryption, Budget Proxy, AuthBridge, Egress Proxy, Human Oversight, Audit Trail. The difference is which additional sandboxing layer controls are enabled."

> "Profiles combine the secure baseline with composable controls from different sandboxing layers to match the isolation level required by the use case. Every profile upholds all three security pillars."

> "Today we're demonstrating the Restricted profile -- the maximum isolation level -- using Kata Containers for hardware virtualization."

---

## Slides 4-5

(Follow your deck.)

---

## Slide 6: agent-sandbox Architecture

**SAY:**

> **Core: Sandbox CRD**
> "The Sandbox CRD is the core of agent-sandbox. It provides a declarative API for managing a single, stateful pod with a stable identity and persistent storage. This is useful for workloads that don't fit into the stateless, replicated model of Deployments or the numbered, stable model of StatefulSets."

> "Key features: stable hostname and network identity, persistent storage that survives restarts, and lifecycle management -- creation, scheduled deletion, pausing and resuming."

> **Extensions**
> "The extensions module provides additional CRDs that build on the core Sandbox API:"
> "**SandboxTemplate** -- reusable templates for creating Sandboxes, making it easier to manage large numbers of similar Sandboxes."
> "**SandboxClaim** -- lets users create Sandboxes from a template, abstracting away the underlying configuration."
> "**SandboxWarmPool** -- manages a pool of pre-warmed Sandbox pods that can be quickly allocated, reducing startup time."

> "agent-sandbox follows the Kubernetes controller pattern. Users create a Sandbox custom resource, and the controller manages the underlying runtime resources."

> "Let me show you what this looks like on a live cluster."

---

## Slide 7

(Follow your deck.)

**DO:** Switch to OpenShift Console.

---
---

# SHOW -- Live Demo (12 min)

---

## Part 1: Platform Walkthrough (7 min) [OpenShift Console]

**SAY (opening):**

> "Everything you're about to see was set up once by the platform team. Developers who use the sandbox never see any of this."

### Step 1: Sandboxed Containers Operator (1 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion
```

**AUDIENCE SEES:** Installed Operators list. Scroll to find "OpenShift sandboxed containers Operator 1.12.0" with "Succeeded" status.

**SAY:**

> **CONCEPT -- Kata Containers on OpenShift:**
> "The foundation. OpenShift Sandboxed Containers is Kata Containers packaged as an operator. It installs a RuntimeClass called `kata-remote` on worker nodes. When a pod uses this RuntimeClass, the kubelet creates a lightweight VM instead of a regular container. Each pod gets its own Linux kernel -- the strongest isolation boundary short of confidential computing."

**SAY (transition):** "That gives us the VM runtime. Next, the controller."

### Step 2: agent-sandbox Controller (1 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-sandbox-system/deployments/agent-sandbox-controller
```

**AUDIENCE SEES:** Deployment details page. 1 Pod, name `agent-sandbox-controller`, namespace `agent-sandbox-system`.

**SAY:**

> **CONCEPT -- what agent-sandbox IS:**
> "The agent-sandbox controller from kubernetes-sigs. One pod, watching four CRDs. It manages sandbox lifecycle: creation, warm pool adoption, expiration, and cleanup. Notice it runs in its own namespace, separate from the demo -- separation of concerns."

**SAY (transition):** "Now let me show you what the platform team configures."

### Step 3: SandboxTemplate (2 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate
```

**AUDIENCE SEES:** SandboxTemplates list with one entry: `python-sandbox-template`.

**DO:** Click into `python-sandbox-template`, then click the **YAML** tab.

**SAY:**

> **CONCEPT -- the template IS the security policy:**
> "This is the platform team's main artifact. One YAML, four isolation layers."

Scroll through the YAML, pointing out:

> **1. `runtimeClassName: kata-remote`**
> "Every sandbox runs inside its own Kata microVM. The agent's code never shares a kernel with the host."

> **2. `automountServiceAccountToken: false`** (Slide 8 deep dive -- expand if audience is technical)
> "This is critical. Every pod in Kubernetes gets a service account. By default, Kubernetes mounts a JWT token at `/var/run/secrets/kubernetes.io/serviceaccount/token`. That token lets the process authenticate to the Kubernetes API server."

> "The token is a signed JWT containing the namespace, service account name, and cluster identity. Any process that reads it can call the K8s API as that service account."

> "What can an attacker do? Depends on RBAC. With the default SA: list pods, services, endpoints. Read ConfigMaps -- which often contain connection strings. In misconfigured clusters: read Secrets, create pods, escalate. Even with minimal RBAC, the token reveals the namespace name, cluster CA, and proves the pod is a valid cluster member -- useful for reconnaissance."

> "With `automountServiceAccountToken: false`, the kubelet does not mount the token, CA cert, or namespace file. The directory `/var/run/secrets/kubernetes.io/serviceaccount/` simply doesn't exist. Zero Kubernetes credentials."

> "Why this matters for agents specifically: an AI agent executes LLM-generated code. That code could do `open('/var/run/secrets/.../token').read()` and call the K8s API. With this flag set, that fails immediately -- no file to read."

> "Notice it's set at `podTemplate.spec` level, not container level. This is a pod-level field -- it ensures no container in the pod, including sidecars, gets the token. One line, total credential removal."

> **3. `securityContext` block**
> "`runAsNonRoot`, `drop ALL capabilities`, `no privilege escalation`. Even inside the VM, the process runs as non-root with zero Linux capabilities."

> **4. `networkPolicy` section**
> "Default-deny egress. Only DNS (port 53) and HTTPS (port 443) to public internet. All RFC1918 addresses and the metadata server are blocked."

> "One YAML. Four layers. The developer just references this by name: `python-sandbox-template`."

**SAY (transition):** "The template defines the policy. The warm pool makes it fast."

### Step 4: SandboxWarmPool (1 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool
```

**AUDIENCE SEES:** SandboxWarmPools list with one entry: `python-sandbox-pool`, Ready: 2.

**SAY:**

> **CONCEPT -- why warm pools exist:**
> "Kata VMs take 15-30 seconds to cold-start. For a user chatting with an AI agent, that's unacceptable."

> "Ready: 2 means two Kata VMs are running right now, pre-loaded with the Python runtime, waiting for someone to claim one. When the agent calls `create_sandbox`, the controller adopts an already-running VM. Sub-second."

> "After a sandbox is destroyed, the pool replenishes automatically."

**SAY (transition):** "Next, the network policy."

### Step 5: NetworkPolicy (30 sec)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/networkpolicies
```

**AUDIENCE SEES:** NetworkPolicies list with one entry: `sandbox-restricted-egress`, Pod selector: `app=sandboxed-agent`.

**SAY:**

> **CONCEPT -- how network isolation works:**
> "Pod selector `app=sandboxed-agent` -- every pod from our template gets this label automatically."

> "Egress: default-deny. Exceptions only for DNS and HTTPS to non-RFC1918 addresses. The pod can reach pypi.org but cannot reach 10.x.x.x, 172.16.x.x, 169.254.x.x -- no internal services, no metadata server, no Kubernetes API."

**SAY (transition):** "Last thing on the platform side."

### Step 6: Sandboxes View (30 sec)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/agents.x-k8s.io~v1alpha1~Sandbox
```

**AUDIENCE SEES:** "No Sandboxes found"

**SAY:**

> **CONCEPT -- Sandbox CR lifecycle:**
> "No Sandbox instances. The warm pool pods are running, but a Sandbox CR only exists when a developer claims one. It's ephemeral -- created on claim, destroyed when done."

> "I'm going to leave this view open. Watch it -- you'll see a Sandbox CR appear in real time when the agent executes code."

**DO:** Keep this console view visible (side-by-side or on a second screen).

**SAY (transition):**

> "That's the platform side -- operator, controller, template, warm pool, network policy. Set up once. Now let me show you the developer experience through an AI agent."

---

## Part 2: ADK Agent Demo (5 min) [Browser + Console visible]

**SAY:**

> "This is the upstream example from the agent-sandbox project -- 'Using Agent Sandbox as a Tool in ADK.' Google's Agent Development Kit. The LLM generates code, the sandbox executes it."

> "The LLM is gpt-oss-120b running on this same cluster via vLLM. No external API key."

**DO:** Switch to browser tab 2 (`http://127.0.0.1:8000`).

**AUDIENCE SEES:** Google ADK Dev UI. `coding_agent` selected in sidebar. Chat interface with "Type a Message..." input.

### Prompt 1: Normal execution

**DO:** Type in the chat:

> Run Python code to calculate and print the first 20 Fibonacci numbers. Execute it in the sandbox.

(Use this exact phrasing -- "Run" and "Execute it in the sandbox" -- to reliably trigger the `execute_python` tool.)

Wait ~15-30 seconds for the LLM + sandbox round-trip.

**EXPECT:** The agent generates Python code, calls `execute_python`, and returns: `[0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181]`

**AUDIENCE SEES IN CONSOLE:** A Sandbox CR appears in the `agent-demo` Sandboxes view, then disappears after execution.

**SAY:**

> **CONCEPT -- what happened behind the scenes:**
> "The LLM generated Python code. The ADK agent called `execute_python`. That function created a sandbox from the warm pool -- you saw the Sandbox CR appear in the console just now -- uploaded the code, ran it inside the Kata VM, and returned stdout. Then the sandbox was terminated and the CR disappeared. The warm pool is already replenishing."

Point at the console: "The Sandbox CR is gone. Ephemeral, per-execution."

> **CONCEPT -- separation of concerns:**
> "The developer wrote 7 lines of Python wrapping the sandbox SDK. Zero security configuration. Everything -- Kata VM, NetworkPolicy, credential removal, container hardening -- came from the SandboxTemplate the platform team defined."

### Prompt 2: Security test (optional, time permitting)

**DO:** Type in the chat:

> Write Python code to access http://169.254.169.254/latest/meta-data/ using urllib.

**EXPECT:** The agent either refuses (LLM safety filter) or generates code that the sandbox blocks via NetworkPolicy.

**SAY:**

> **CONCEPT -- defence in depth:**
> "The LLM may refuse to generate this code -- that's the model's safety filter. If it does generate and execute it, the sandbox blocks it at the network layer via NetworkPolicy. Two layers: model safety AND infrastructure isolation."

**SAY (transition):** "Let me close with what this maps to in our strategy."

**DO:** Switch to closing slides.

---
---

# TELL -- Closing (4 min, slides)

---

## Slide 9: What You Just Saw

**SLIDE:**

| What | How |
|---|---|
| SA token removed | `automountServiceAccountToken=false` |
| Metadata + RFC1918 blocked | NetworkPolicy (L3/L4 default-deny egress) |
| Non-root, zero capabilities | SecurityContext in SandboxTemplate |
| Kata microVM per pod | `runtimeClassName: kata-remote` |
| Sub-second provisioning | SandboxWarmPool (2 pre-warmed VMs) |
| 7 lines of Python, 0 security config | Python SDK + SandboxTemplate by name |

**SAY:**

> "Each row is something you saw. The template gave you the top four. The warm pool gave you fast provisioning. The SDK gave you the developer experience. The ADK web UI showed it working inside a real agent framework."

Walk through each row briefly.

---

## Slide 10: AgentOps -- From Experiment to Production

**SAY:**

> "Now, let's zoom in to AgentOps."

> "AgentOps is how we bridge the gap between experimental AI and production agents. It's a unified approach for managing the full lifecycle, security, and performance of AI agents and their tools."

> "Roughly three pillars."

> **Pillar 1 -- Observe, Trace, Evaluate:**
> "We use MLflow 3.6+ to log and visualize full execution traces, including tool calls. Everything is OpenTelemetry compatible, so it plugs into existing observability stacks. For evaluation, we combine Eval-hub and MLflow for dataset curation and scoring -- so you're not just watching agents run, you're measuring whether they're actually working."

> **Pillar 2 -- Enforce Identity and Access Control:**
> "Agents are autonomous actors, so they need their own identity. Upcoming: SPIFFE and SPIRE for trusted workload identity, OAuth2 token exchange for secure delegation, Kagenti for agentic auth and access control. The MCP Gateway governs agent-to-tool access -- making sure agents can only reach the tools they're authorized to use."

> **Pillar 3 -- Develop and Deploy Reliably:**
> "This covers agent and AI asset management, agent lifecycle management through Kagenti -- which connects agents with identity and policies -- and agent safety using guardrails and red teaming tools like Nemo and Garak."

> "The bottom line: we are providing enterprises the operational rigor to reliably move agents from experimentation to production -- without locking them into any single framework."

> "What you saw today -- the sandbox, the template, the warm pool, the SDK -- that's the isolation layer. AgentOps wraps the rest around it: observability, identity, lifecycle."

---

## Slide 11: Three Things You Saw

**SLIDE:**

```
1. THE PROBLEM
   Without isolation, agents can steal credentials,
   probe internal networks, and read K8s tokens.

2. THE PLATFORM FIX
   One SandboxTemplate. Kata + NetworkPolicy + hardening + no credentials.
   Set up once.

3. THE DEVELOPER EXPERIENCE
   7 lines of Python. 0 lines of security config.
   Same sandbox behind a chat UI.


"The strategy says agent-sandbox and Kata are 'under evaluation.'
 What you just saw is the evaluation."
```

**SAY:**

> "**The problem:** Without isolation, any agent can reach the metadata server, probe internal services, and read the Kubernetes service account token. That's the default for every standard pod."

> "**The platform fix:** One SandboxTemplate YAML -- four isolation layers stacked: Kata microVM, NetworkPolicy, container hardening, credential removal. Set up once. Warm pools solved Kata's cold-start."

> "**The developer experience:** Seven lines of Python. Zero security config. The developer referenced a template by name and got hardware-virtualized, network-isolated, credential-free execution -- inside a chat UI."

> "agent-sandbox is the pod lifecycle foundation -- the missing Kubernetes primitive for isolated, singleton agent workloads. Everything you saw, including the LLM, runs on this cluster. No external API keys."

Deliver the final line with weight:

> "The strategy says agent-sandbox and Kata are 'under evaluation.' What you just saw is the evaluation."

Pause. Open for Q&A.

---
---

# Q&A Preparation

**Q: Why not just use Deployments or Jobs?**
> "Deployments manage replica sets -- they want N identical pods. Agent sandboxes are singleton, stateful, per-session workloads with expiration. Sandbox is to agents what StatefulSet is to databases."

**Q: What about gVisor?**
> "gVisor doesn't support SELinux. The strategy explicitly rules it out for OpenShift/RHEL. Kata gives us kernel-level isolation via real hardware virtualization."

**Q: What's the Kata performance overhead?**
> "Cold start is 15-30 seconds vs 2-5 seconds for a standard container. That's why warm pools exist -- claim adoption is sub-second. Memory overhead is ~30-50MB per VM for the guest kernel."

**Q: How mature is agent-sandbox?**
> "v0.2.1, alpha API, under kubernetes-sigs (SIG Apps). The CRD design follows Kubernetes patterns. It's serious upstream work."

**Q: Could a full IDE agent like Goose use the same sandbox?**
> "Yes. The sandbox is agent-agnostic infrastructure. A full IDE agent would keep the sandbox alive for the session, read/write files, run commands, iterate. Same Kata VM, same NetworkPolicy, same credential removal."

**Q: Does the sandbox persist between agent turns?**
> "Configurable. In this demo, each call creates and destroys a sandbox. For stateful sessions, you keep one sandbox alive and reuse it."

**Q: What about multi-tenancy?**
> "Templates and claims are namespace-scoped. Namespace isolation plus NetworkPolicy plus Kata VM boundary per pod. For full confidential computing, the next step is CoCo with TEE attestation."

**Q: How does this compare to E2B, Modal, Daytona?**
> "Those are sandboxes as a service. agent-sandbox is an open-source K8s operator -- you run it on your own cluster, your own compliance boundary. For enterprises that can't send agent workloads to a third-party cloud, this is the path."

**Q: What can't it do?**
> "NetworkPolicy is L3/L4, not L7 -- it blocks IPs, not domain names. No filesystem scoping (Landlock would add that). No per-tool-call audit trail yet. agent-sandbox is the lifecycle foundation; the strategy's composable controls layer on top."

---
---

# Appendix

## Screen Layout

| Phase | Primary Screen | Secondary Screen |
|---|---|---|
| TELL -- Opening (Slides 1-7) | Slides | -- |
| Console walkthrough (Steps 1-6) | OpenShift Console | -- |
| ADK demo (Prompts 1-2) | ADK browser tab | Console Sandboxes view |
| TELL -- Closing (Slides 9-11) | Slides | -- |

## Key URLs

| Resource | URL |
|---|---|
| OpenShift Console | `https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com` |
| ADK Web UI | `http://127.0.0.1:8000` |
| LLM Endpoint | `https://gpt-oss-120b-gpt-oss-120b.apps.ocp.v7hjl.sandbox2288.opentlc.com/v1` |

## Console URL Cheat Sheet

Copy-paste in order:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-sandbox-system/deployments/agent-sandbox-controller
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/networkpolicies
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/agents.x-k8s.io~v1alpha1~Sandbox
```

## Command Cheat Sheet

```bash
# Setup (run before audience arrives)
bash demo/00-setup.sh

# Port-forward to sandbox-router (leave running in terminal 1)
kubectl port-forward svc/sandbox-router-svc -n agent-demo 8090:8080

# Pre-start ADK server (leave running in terminal 2)
cd demo && adk web

# Cleanup (after demo)
bash demo/99-cleanup.sh
```

## Cleanup

After the demo:

```bash
bash demo/99-cleanup.sh
```

To also delete the namespace entirely:

```bash
kubectl delete namespace agent-demo
```
