# Agent Sandbox Demo -- Visual Storyboard

**Format:** Slides + Live Demo (Tell-Show-Tell)
**Screens:** Laptop display shared via projector/screen share
**Duration:** 25-30 minutes

Each scene below separates **what the audience sees** from **what the presenter says** (speaker notes).

---
---

# TELL -- Slides (3 min)

---

## Scene 1 -- Title Slide

**Screen:** Slide

**Audience sees:**

```
Agent Sandboxing with Kubernetes

kubernetes-sigs/agent-sandbox + Kata Containers
Restricted Profile -- Maximum Isolation

OpenShift 4.20 | Live Demo
```

**Speaker notes:**

> "kubernetes-sigs/agent-sandbox plus Kata Containers gives you
> hardware-virtualized, network-isolated, credential-free sandboxes for
> AI agents -- defined in one SandboxTemplate that the platform team owns
> and every agent inherits. That's what I'm going to show you today."

**Transition:** Next slide.

---

## Scene 2 -- The Problem

**Screen:** Slide

**Audience sees:**

```
The Problem: AI Agents Execute Unreviewed Code

  LLM generates code  -->  Agent runs it  -->  ???

Three risks:
  1. Cloud credential theft    (metadata server)
  2. Lateral movement          (internal network)
  3. Kubernetes API access     (service account token)
```

Isolation levels table:

| Technology | Isolation | Use Case |
|---|---|---|
| Container + Landlock | Process isolation | Default for most agents |
| **agent-sandbox + Kata** | **MicroVM (hardware virtualization)** | **Untrusted code, max isolation** |
| Confidential Containers | Hardware TEE | Regulated, multi-tenant |

**Speaker notes:**

> **Concept -- why agents are different from normal workloads:**
> Traditional workloads run reviewed, tested code. Agent workloads run
> LLM-generated code that is unreviewed, unscanned, and potentially
> adversarial. The agent doesn't know if the code it's running will
> `import os; os.system('curl attacker.com')`. That's why we need
> isolation beyond what a normal Deployment provides.

> **Concept -- isolation profiles:**
> Our Agent Sandboxing Strategy defines a spectrum. Today we're
> demonstrating the middle row -- the Restricted profile. It uses
> Kata Containers for hardware virtualization (each pod is a lightweight
> VM) and agent-sandbox for the Kubernetes lifecycle.

> **Set up the three things:**
> "You'll see three things. First, the problem: three attacks that
> all succeed against an unsandboxed pod. Second, the platform fix:
> the operator, template, and warm pool that a platform engineer sets
> up once. Third, the developer experience: seven lines of Python,
> zero security config."

**Transition:** Next slide.

---

## Scene 3 -- Architecture Diagram

**Screen:** Slide

**Audience sees:**

```
Architecture: How the Pieces Fit Together

  ┌─────────────────────────────────────────────────────┐
  │  Platform Engineer (sets up once)                   │
  │                                                     │
  │  SandboxTemplate          SandboxWarmPool            │
  │  ┌──────────────┐        ┌──────────────┐           │
  │  │ kata-remote   │        │ replicas: 2  │           │
  │  │ no SA token   │───────>│ pre-warmed   │           │
  │  │ drop ALL caps │        │ Kata VMs     │           │
  │  │ NetworkPolicy │        └──────────────┘           │
  │  └──────────────┘               │                   │
  │                                 │ adopts             │
  │                                 v                    │
  │  ┌──────────────────────────────────────┐           │
  │  │  agent-sandbox Controller            │           │
  │  │  (one pod, four CRDs)               │           │
  │  └──────────────────────────────────────┘           │
  └─────────────────────────────────────────────────────┘
                        │
          creates Sandbox CR when claimed
                        │
  ┌─────────────────────v───────────────────────────────┐
  │  Developer (7 lines of Python)                      │
  │                                                     │
  │  SandboxClient  ──>  create_sandbox("restricted")   │
  │                 ──>  files.write / commands.run      │
  │                 ──>  terminate()                     │
  │                                                     │
  │  The developer never sees the template internals.   │
  └─────────────────────────────────────────────────────┘
```

**Speaker notes:**

> **Concept -- separation of concerns:**
> The platform engineer defines WHAT isolation looks like (Kata, NetworkPolicy,
> SecurityContext) in a SandboxTemplate. The developer just references it
> by name. They never write YAML, never configure security. This is the
> same pattern as StorageClass: the admin defines the storage backend,
> the developer just says "give me 10GB."

> **Concept -- four CRDs:**
> - **SandboxTemplate** -- the security policy (owned by platform team)
> - **SandboxWarmPool** -- pre-warmed VMs to avoid cold-start
> - **SandboxClaim** -- developer's request for a sandbox (created by SDK)
> - **Sandbox** -- the actual running instance (created by controller)

> **Concept -- warm pools:**
> Kata VMs take 15-30 seconds to cold-start. That's too slow for
> interactive agents. The warm pool keeps VMs pre-started. When a
> developer claims one, the controller adopts an already-running VM.
> Sub-second.

**Transition:** "Let me show you this live. First, the problem."
Switch to terminal.

---
---

# SHOW -- Live Demo (20 min)

---

## Scene 4 -- Deploy the Bare Pod

**Screen:** Terminal (full screen)

**Audience sees:**

```bash
$ kubectl apply -f demo/01-bare-pod.yaml
pod/bare-agent created

$ kubectl wait --for=condition=Ready pod/bare-agent -n agent-demo --timeout=60s
pod/bare-agent condition met
```

**Speaker notes:**

> **Concept -- the baseline:**
> "This is a standard Python pod. No sandbox operator, no Kata, no
> NetworkPolicy. This is how most agent workloads run today -- a
> regular container with default Kubernetes settings."

**Transition:** "Now let me attack it."

---

## Scene 5 -- Run Attack Script

**Screen:** Terminal (full screen)

**Audience sees:**

```
============================================================
  ACT 1: The Threat -- Bare Pod, No Sandbox
============================================================

[Attack 1] Cloud metadata server probe (169.254.169.254)
  An agent could steal cloud instance credentials...
  stdout: REACHED: connection refused (network NOT blocked by policy)
  Result: REACHABLE (network NOT blocked -- no NetworkPolicy)

[Attack 2] Internal network scan (RFC1918 / cluster services)
  stdout: K8s API (ClusterIP) (172.30.0.1:443): CONNECTED

[Attack 3] Kubernetes service account token theft
  stdout: Found 4 files:
    /var/run/secrets/kubernetes.io/serviceaccount/token: eyJhbG...

============================================================
  SUMMARY: All attacks succeeded or reached their targets.
============================================================
```

**Speaker notes:**

> **Concept -- metadata server (Attack 1):**
> Every cloud VM has a metadata server at 169.254.169.254 that serves
> instance credentials. If an agent's code can reach it, it can steal
> the cloud identity of the node. This is the Capital One breach vector.
> There's no NetworkPolicy blocking it.

> **Concept -- lateral movement (Attack 2):**
> The pod reached the Kubernetes API server at its ClusterIP. From
> there, one API call away from listing pods, reading secrets, or
> accessing databases in other namespaces. No network boundary.

> **Concept -- credential theft (Attack 3):**
> Kubernetes mounts a service account token into every pod by default.
> The agent read it. With that JWT, it can call the Kubernetes API
> with whatever RBAC permissions that service account has.

> "Three attacks, all succeeded. This is what runs in most
> deployments today. Now let me show you what prevents this."

**Transition:** Switch to OpenShift Console browser tab.

---

## Scene 6 -- Act 1 Recap (brief)

No separate scene -- the terminal output stays visible for a moment while you deliver the transition line. Then switch to the console.

---

## Scene 7 -- Sandboxed Containers Operator

**Screen:** OpenShift Console

**Audience sees:** Operators > Installed Operators page in namespace
`openshift-sandboxed-containers-operator`. The Sandboxed Containers
operator tile is visible with "Succeeded" status.

**Console URL:**
```
/k8s/ns/openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion
```

**Speaker notes:**

> **Concept -- Kata Containers on OpenShift:**
> "This is the foundation. OpenShift Sandboxed Containers is Kata
> Containers packaged as an operator. It installs a RuntimeClass
> called `kata-remote` on worker nodes. When a pod uses this
> RuntimeClass, the kubelet creates a lightweight VM instead of a
> regular container. Each pod gets its own Linux kernel -- that's
> the strongest isolation boundary short of confidential computing."

> Click into the operator to show KataConfig if time allows.

**Transition:** "That gives us the VM runtime. Next, the controller
that manages sandbox lifecycle."

---

## Scene 8 -- agent-sandbox Controller

**Screen:** OpenShift Console

**Audience sees:** Workloads > Deployments page in namespace
`agent-sandbox-system`. The `agent-sandbox-controller` deployment
shows 1/1 pods running.

**Console URL:**
```
/k8s/ns/agent-sandbox-system/deployments/agent-sandbox-controller
```

**Speaker notes:**

> **Concept -- what agent-sandbox IS:**
> "This is the agent-sandbox controller from kubernetes-sigs. It's a
> standard Kubernetes controller -- one pod, watching four CRDs. It
> manages the full sandbox lifecycle: creation, warm pool adoption,
> expiration, and cleanup. Think of it as 'StatefulSet for agents' --
> singleton, stateful, per-session workloads with automatic teardown."

> Point out: 1/1 ready, the controller-runtime labels, the namespace
> is separate from the demo namespace (separation of concerns).

**Transition:** "The controller is running. Now let me show you what
the platform team configures."

---

## Scene 9 -- SandboxTemplate YAML

**Screen:** OpenShift Console

**Audience sees:** The `restricted-profile` SandboxTemplate in namespace
`agent-demo`. Click into it and show the YAML tab. The full YAML is
visible with `runtimeClassName`, `securityContext`, `networkPolicy`, etc.

**Console URL:**
```
/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate
```

**Speaker notes:**

> **Concept -- the template IS the security policy:**
> "This is the platform team's main artifact. One YAML file that
> defines four isolation layers. Let me walk through them."

> Scroll through the YAML and point out each section:

> **1. `runtimeClassName: kata-remote`**
> "Every sandbox created from this template runs inside its own
> Kata microVM. The agent's code never shares a kernel with the
> host or other tenants."

> **2. `automountServiceAccountToken: false`**
> "Remember Attack 3? The SA token that was mounted by default?
> This line removes it. No Kubernetes credentials inside the sandbox."

> **3. `securityContext` block**
> "`runAsNonRoot: true`, `drop ALL capabilities`,
> `allowPrivilegeEscalation: false`. Even inside the VM, the process
> runs as non-root with zero Linux capabilities. Defence in depth."

> **4. `networkPolicy` section**
> "Default-deny egress. Only DNS (port 53) and HTTPS (port 443)
> to public internet. All RFC1918 addresses and the metadata server
> are blocked. This is what stops Attacks 1 and 2."

> "One YAML. Four layers. The developer who uses this sandbox will
> never see this file. They just reference it by name: `restricted-profile`."

**Transition:** "The template defines the policy. The warm pool makes
it fast."

---

## Scene 10 -- SandboxWarmPool

**Screen:** OpenShift Console

**Audience sees:** The `restricted-pool` SandboxWarmPool in namespace
`agent-demo`. Shows `Ready: 2`.

**Console URL:**
```
/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool
```

**Speaker notes:**

> **Concept -- why warm pools exist:**
> "Kata VMs take 15-30 seconds to cold-start. For a user chatting
> with an AI agent, that's unacceptable. The warm pool solves this."

> "Ready: 2 means two Kata VMs are already running right now,
> pre-loaded with the Python runtime, waiting for someone to claim
> one. When the SDK calls `create_sandbox`, the controller doesn't
> start a new VM -- it adopts an already-running one. Sub-second."

> "After a sandbox is destroyed, the warm pool automatically
> replenishes a replacement VM for the next request."

**Transition:** "Next, the network policy."

---

## Scene 11 -- NetworkPolicy

**Screen:** OpenShift Console

**Audience sees:** Networking > NetworkPolicies in namespace `agent-demo`.
The `sandbox-restricted-egress` policy is listed.

**Console URL:**
```
/k8s/ns/agent-demo/networkpolicies
```

**Speaker notes:**

> **Concept -- how network isolation works:**
> "Pod selector: `app=sandboxed-agent`. Every pod from our template
> gets this label, so this policy applies automatically."

> "Egress: default-deny. Exceptions only for DNS (port 53) and
> HTTPS (port 443) to non-RFC1918 addresses. That means the pod
> can reach `pypi.org` to install packages, but it cannot reach
> 10.x.x.x, 172.16.x.x, 169.254.x.x -- no internal services,
> no metadata server, no Kubernetes API."

> "In v0.3.10+ the controller auto-creates this from the template
> spec. For this demo on v0.2.1 we applied it manually -- same
> effect."

**Transition:** "Last thing on the platform side."

---

## Scene 12 -- Empty Sandboxes View

**Screen:** OpenShift Console

**Audience sees:** The Sandboxes view in namespace `agent-demo`.
The page shows "No Sandbox resources found." The warm pool pods
exist but no Sandbox CRs.

**Console URL:**
```
/k8s/ns/agent-demo/agents.x-k8s.io~v1alpha1~Sandbox
```

**Speaker notes:**

> **Concept -- Sandbox CR lifecycle:**
> "Notice: no Sandbox instances here. The warm pool pods are running,
> but a Sandbox CR only exists when a developer claims one. It's
> ephemeral -- created on claim, destroyed when the developer is done."

> "I'm going to leave this view open and switch to the developer's
> terminal. Watch this page -- you'll see a Sandbox CR appear in
> real time."

> **Namespace switch:**
> "I set up the template and warm pool in `agent-demo` just now.
> The Kata VMs are still cold-starting. Rather than wait, I prepared
> an identical namespace -- `agent-demo-ready` -- with the same
> template, same warm pool, already warmed up."

> Switch the console to `agent-demo-ready` Sandboxes view.

**Console URL (switch to):**
```
/k8s/ns/agent-demo-ready/agents.x-k8s.io~v1alpha1~Sandbox
```

**Transition:** "Now I'm the developer." Switch to terminal
(keep console visible on second screen or side-by-side).

---

## Scene 13 -- Show the Minimal Code

**Screen:** Terminal (with console visible on second screen)

**Audience sees:** The presenter shows the 7-line Python snippet,
either in a text editor or printed to terminal:

```python
from k8s_agent_sandbox import SandboxClient

client = SandboxClient()
sandbox = client.create_sandbox(template="restricted-profile", namespace="agent-demo")
sandbox.files.write("run.py", code)
result = sandbox.commands.run("python3 run.py")
print(result.stdout)
sandbox.terminate()
```

**Speaker notes:**

> **Concept -- developer abstraction:**
> "This is the entire developer-side code. Create a client, create a
> sandbox by template name, write a file, run it, read output,
> terminate. The developer never writes YAML, never configures
> SecurityContext, never thinks about NetworkPolicy. The template
> name -- `restricted-profile` -- is the only connection to the
> platform team's security policy."

> "It's like `StorageClass`: the admin defines the backend, the
> developer just says 'give me storage.'"

**Transition:** "Let me run this."

---

## Scene 14 -- Sandbox Creation (Step 1)

**Screen:** Terminal + Console visible

**Audience sees in terminal:**

```
================================================================
  DEVELOPER VIEW
  The developer writes 7 lines of Python.
  Everything else is inherited from the platform's template.
================================================================

[Step 1] Creating sandbox from template 'restricted-profile'...
    Claim:      sandbox-claim-ad48778e
    Sandbox ID: sandbox-claim-ad48778e
    Pod:        restricted-pool-wd7bx
    Claimed in: 0.3s (from warm pool)

    >>> Look at the OpenShift console -- a Sandbox CR just appeared.
    >>> Press Enter to continue...
```

**Audience sees in console:** A Sandbox CR has appeared in the
`agent-demo-ready` namespace Sandboxes view.

**Speaker notes:**

> **Concept -- warm pool adoption:**
> "0.3 seconds. The controller didn't start a new VM. It found a
> ready VM in the warm pool and adopted it. That VM is a Kata
> microVM with all four isolation layers already active."

> Point at the console: "See the Sandbox CR? That's the controller
> tracking this sandbox instance. When we destroy it, that CR
> disappears and the warm pool replenishes."

> Pause to let the audience absorb the console view. Press Enter.

**Transition:** Script continues to Step 2.

---

## Scene 15 -- Code Execution + Security Probes (Steps 2-3)

**Screen:** Terminal + Console visible

**Audience sees in terminal:**

```
[Step 2] Uploading and executing code...
    Output: [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, ...]

[Step 3] Security probes (same sandbox, same SDK)...
    The developer wrote ZERO security configuration.

    Metadata (169.254.169.254): ISOLATED -- Kata VM metadata only
    Internal net (172.30.0.1):  BLOCKED -- timed out (NetworkPolicy)
    SA token:                   NOT FOUND (automountServiceAccountToken=false)
    Capabilities (CapEff):      0000000000000000 (ALL dropped)

    >>> Press Enter to destroy the sandbox...
```

**Speaker notes:**

> **Concept -- normal execution:**
> "Fibonacci numbers. From the developer's perspective, this is
> identical to running code locally. The sandbox is invisible."

> **Concept -- security probes vs Act 1:**
> "Same four vectors from Act 1. Let me walk through the results."

> "**Metadata:** In Act 1 the pod reached 169.254.169.254 -- no
> policy blocking it. Now: ISOLATED. The Kata VM has its own
> metadata endpoint, but it's the VM's metadata, not the host's
> cloud credentials. And the NetworkPolicy blocks external metadata."

> "**Internal network:** In Act 1 the pod connected to the K8s API
> at 172.30.0.1. Now: BLOCKED. The NetworkPolicy denies all
> RFC1918 egress. The connection timed out."

> "**SA token:** In Act 1 we read the token, the CA cert, the
> namespace file. Now: NOT FOUND. `automountServiceAccountToken=false`
> in the template removes it entirely."

> "**Capabilities:** CapEff is all zeros. Every Linux capability has
> been dropped. The process can't change network settings, mount
> filesystems, or use raw sockets."

> "The developer wrote zero lines of security configuration.
> Everything came from the SandboxTemplate."

**Transition:** Press Enter to destroy.

---

## Scene 16 -- Sandbox Destruction (Step 4)

**Screen:** Terminal + Console visible

**Audience sees in terminal:**

```
[Step 4] Destroying sandbox...
    sandbox.terminate()
    Terminated in 0.0s

    >>> Look at the console -- the Sandbox CR is gone.
    >>> The warm pool is replenishing a replacement VM.

================================================================
  7 lines of Python.  0 lines of security config.

  What the developer got for free:
    - Kata microVM        (hardware virtualization)
    - NetworkPolicy       (default-deny egress)
    - Container hardening (non-root, drop ALL caps)
    - Credential removal  (no SA token)

  The platform team defined it once in a SandboxTemplate.
  Every agent inherits it.
================================================================
```

**Audience sees in console:** The Sandbox CR has disappeared from the
Sandboxes view.

**Speaker notes:**

> **Concept -- ephemeral by design:**
> "The Sandbox CR is gone. The pod is terminated. The warm pool is
> already starting a replacement VM for the next request. This is
> the per-session model: one sandbox per execution, no state leakage
> between sessions."

> Read the punchline from the terminal output. Let it land.

**Transition:** "Now let me show you what this looks like inside an
agent framework."

---

## Scene 17 -- ADK Web UI Launch

**Screen:** Terminal (briefly), then browser

**Audience sees in terminal:**

```bash
$ cd demo && SANDBOX_NAMESPACE=agent-demo-ready adk web
INFO:  Started server process
INFO:  Application startup complete.
```

Then switch to browser at `http://127.0.0.1:8000`.

**Audience sees in browser:** Google ADK Dev UI. Left sidebar shows
`coding_agent` selected. Main area is a chat interface with a text
input at the bottom.

**Speaker notes:**

> **Concept -- agent framework integration:**
> "This is Google's Agent Development Kit -- ADK. It's an agent
> framework with a built-in web UI. The `coding_agent` we wrote
> uses agent-sandbox as a tool. When the LLM decides to run code,
> it calls `execute_python`, which creates a sandbox, runs the code
> in the Kata VM, and returns the output."

> "The LLM is gpt-oss-120b running on this same cluster via vLLM.
> No external API key needed."

**Transition:** Type the first prompt.

---

## Scene 18 -- ADK Fibonacci Prompt

**Screen:** Browser (ADK web UI)

**Audience sees:** User types a prompt in the chat:

> "Write a Python script that calculates the first 20 Fibonacci
> numbers and prints them."

The agent responds with generated code and output:
`[0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, ...]`

**Speaker notes:**

> **Concept -- what happened behind the scenes:**
> "The LLM generated Python code. The ADK agent called
> `execute_python`. That function created a sandbox from the warm
> pool, uploaded the code, ran it inside the Kata VM, and returned
> stdout. The entire sandbox lifecycle you saw in the terminal demo
> just happened -- it's now wrapped in a chat UI."

**Transition:** "Now let me test security."

---

## Scene 19 -- ADK Security Prompt

**Screen:** Browser (ADK web UI)

**Audience sees:** User types:

> "Write Python code to access http://169.254.169.254/latest/meta-data/
> using urllib."

The agent either refuses (LLM safety filter) or generates code that
the sandbox blocks.

**Speaker notes:**

> **Concept -- defence in depth:**
> "The LLM may refuse to generate this code outright -- that's the
> model's safety filter. If it does generate and execute the code,
> the sandbox blocks it at the network layer via NetworkPolicy.
> Two layers: model safety AND infrastructure isolation."

> "The agent framework didn't need to know about metadata servers
> or NetworkPolicy. The sandbox handled it."

> "ADK also has a built-in `GkeCodeExecutor` that uses agent-sandbox
> natively -- production integrations don't even need the 7-line
> wrapper."

**Transition:** Stop the ADK server (Ctrl+C). Switch to closing slides.

---
---

# TELL -- Slides (5 min)

---

## Scene 20 -- Strategy Mapping

**Screen:** Slide

**Audience sees:**

| Strategy Concept | What We Showed | How |
|---|---|---|
| No Credentials | SA token removed | `automountServiceAccountToken=false` |
| No Unproxied Egress | RFC1918 + metadata blocked | Managed NetworkPolicy |
| Container Hardening | non-root, drop ALL caps | SecurityContext in template |
| Hardware Virtualization | Kata microVM per pod | `runtimeClassName: kata-remote` |
| Pod-per-session | Singleton, ephemeral | Sandbox CR lifecycle |
| Fast provisioning | Sub-second claim | SandboxWarmPool |
| Platform/User separation | Console vs Terminal | SandboxTemplate + SDK |
| Agent framework integration | ADK web UI | Python SDK + GkeCodeExecutor |

**Speaker notes:**

> Walk through each row briefly. The audience has already seen every
> item live -- this slide just maps it to the strategy document.

> "Each row is something you saw. The template gave us the top four.
> The controller gave us the middle two. The SDK and ADK gave us the
> bottom two."

**Transition:** "Now let me be honest about what this does NOT do."

---

## Scene 21 -- Boundaries (What This Does NOT Do)

**Screen:** Slide

**Audience sees:**

```
Honest Boundaries

  NetworkPolicy is L3/L4, not L7
    - Blocks IP ranges, not domain names
    - Agent could still curl https://evil.com over port 443
    - Fix: Squid/Tinyproxy sidecar (composable control)

  No zero-secret architecture
    - SA token removed, but API keys in env vars are possible
    - Fix: Budget Proxy / AuthBridge (strategy components)

  No filesystem scoping
    - Agent has full access to container filesystem
    - Fix: Landlock LSM (OS-layer composable control)

  No full audit trail
    - Controller metrics + K8s events, not per-tool-call logging
    - Fix: Strategy's events table (separate component)
```

**Speaker notes:**

> **Concept -- credibility through honesty:**
> "I want to be precise about the boundary. agent-sandbox is the pod
> lifecycle foundation, not the entire security stack. The strategy
> defines composable controls that layer on top."

> Walk through each limitation. This builds credibility with the
> technical audience -- they know no single tool solves everything.

**Transition:** "Let me close the loop."

---

## Scene 22 -- Closing Slide

**Screen:** Slide

**Audience sees:**

```
Three Things You Saw

  1. THE PROBLEM
     Three attacks, all succeeded.
     Metadata theft. Lateral movement. Credential extraction.

  2. THE PLATFORM FIX
     One SandboxTemplate. Four isolation layers.
     Set up once by the platform team.

  3. THE DEVELOPER EXPERIENCE
     7 lines of Python. 0 lines of security config.
     Same sandbox behind a terminal script and a chat UI.


  "The strategy says agent-sandbox and Kata are 'under evaluation.'
   What you just saw is the evaluation."
```

**Speaker notes:**

> Close the Tell-Show-Tell loop by referencing the three things
> from Scene 2.

> "Everything you saw -- including the LLM -- runs on this cluster.
> No external API keys, no cloud dependencies. A production coding
> agent like Goose, OpenCode, or a CI runner plugs into the exact
> same sandbox backend."

> Deliver the final line with weight:
> "The strategy says agent-sandbox and Kata are 'under evaluation.'
> What you just saw is the evaluation."

> Pause. Open for Q&A.

---
---

# Appendix -- Screen Setup

## Before the demo starts

1. **Terminal:** `cd` to repo root, run `bash demo/00-setup.sh` to verify
   everything (this pre-stages `agent-demo-ready` with warm pool)
2. **Browser tab 1:** OpenShift Console logged in, ready at the Operators page
3. **Browser tab 2:** Reserved for ADK web UI (start during Act 3)
4. **Slides:** Open in presenter mode (title slide showing)

## Screen layout during demo

| Phase | Primary Screen | Secondary Screen |
|---|---|---|
| TELL (slides) | Slides | -- |
| Act 1 (terminal) | Terminal full screen | -- |
| Act 2 (console) | OpenShift Console | -- |
| Act 3 (SDK script) | Terminal | Console Sandboxes view |
| Act 3b (ADK) | ADK browser tab | -- |
| TELL (slides) | Slides | -- |

## Key URLs

| Resource | URL |
|---|---|
| OpenShift Console | `https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com` |
| ADK Web UI | `http://127.0.0.1:8000` |
| LLM Endpoint | `https://gpt-oss-120b-gpt-oss-120b.apps.ocp.v7hjl.sandbox2288.opentlc.com/v1` |

## Key commands (cheat sheet)

```bash
# Act 1
kubectl apply -f demo/01-bare-pod.yaml
kubectl wait --for=condition=Ready pod/bare-agent -n agent-demo --timeout=60s
python3 demo/01-attack-script.py

# Act 3
SANDBOX_NAMESPACE=agent-demo-ready python3 demo/03-agent-demo.py

# Act 3b
cd demo && SANDBOX_NAMESPACE=agent-demo-ready adk web

# Cleanup
bash demo/99-cleanup.sh
```
