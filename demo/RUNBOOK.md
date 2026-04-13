# Agent Sandbox Demo -- Presenter Runbook

**This document is your single reference during the live demo. Do not show it to the audience.**

**Duration:** 25-30 minutes
**Audience:** Agent experts + executive
**Format:** Tell-Show-Tell (slides + live demo + slides)
**Environment:** OpenShift 4.20, agent-sandbox v0.2.1, Kata Containers, gpt-oss-120b on-cluster LLM
**Console:** https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com

---

## Pre-Demo Checklist

Run at least 5 minutes before the demo starts (Kata warm pools need ~80s):

```bash
cd /path/to/agent-sandbox-demo
bash demo/00-setup.sh
```

This does everything: login, controller check, CRDs, Kata, image builds, platform resources in both namespaces, warm pool pre-warming.

Open these before you begin:

1. **Slides** -- in presenter mode, title slide showing
2. **Terminal** -- `cd` to repo root, clear screen
3. **Browser tab 1** -- OpenShift Console, logged in, on the Operators page
4. **Browser tab 2** -- reserved for ADK web UI (start during Act 3b)

Verify warm pools are ready:

```bash
kubectl get sandboxwarmpool -n agent-demo-ready -o jsonpath='{.items[0].status.readyReplicas}'
# Should print: 2
```

---
---

# TELL -- Opening (3 min, slides)

---

## Slide 1: Title

**SLIDE:**

```
Agent Sandboxing with Kubernetes

kubernetes-sigs/agent-sandbox + Kata Containers
Restricted Profile -- Maximum Isolation

OpenShift 4.20 | Live Demo
```

**SAY:**

> "kubernetes-sigs/agent-sandbox plus Kata Containers gives you hardware-virtualized, network-isolated, credential-free sandboxes for AI agents -- defined in one SandboxTemplate that the platform team owns and every agent inherits. That's what I'm going to show you today."

---

## Slide 2: The Problem

**SLIDE:**

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
| Container + Landlock | Process isolation + kernel scoping | Default for most agents |
| **agent-sandbox + Kata** | **MicroVM (hardware virtualization)** | **Untrusted code, max isolation** |
| Confidential Containers | Hardware TEE (TDX, SEV) | Regulated, multi-tenant |

**SAY:**

> **CONCEPT -- why agents are different from normal workloads:**
> "Traditional workloads run reviewed, tested code. Agent workloads run LLM-generated code that is unreviewed, unscanned, and potentially adversarial. The agent doesn't know if the code it's running will `import os; os.system('curl attacker.com')`. That's why we need isolation beyond what a normal Deployment provides."

> **CONCEPT -- isolation profiles:**
> "Our Agent Sandboxing Strategy defines a spectrum. Today we're demonstrating the middle row -- the Restricted profile. It uses Kata Containers for hardware virtualization -- each pod is a lightweight VM -- and agent-sandbox for the Kubernetes lifecycle."

> **CONCEPT -- why not Deployments or StatefulSets:**
> "You might ask: why not just use a Deployment? Agent workloads are fundamentally different -- they're singleton, stateful, per-session, with automatic expiration. A Deployment wants N identical replicas. A StatefulSet wants numbered, stable pods. An agent sandbox is one pod, one session, one user, torn down when done. agent-sandbox gives you that primitive natively -- think of it as StatefulSet for agents."

> **CONCEPT -- decoupled isolation:**
> "agent-sandbox is runtime-agnostic. It provides a standardized Kubernetes API -- four CRDs -- that fully decouples the execution layer from the underlying isolation technology. It works with Kata, gVisor, or standard runc. Today we're showing Kata for maximum isolation, but the same SandboxTemplate could swap to a different runtime without changing a single line of developer code."

---

## Slide 3: Architecture

**SLIDE:**

```
Architecture: How the Pieces Fit Together

  +-----------------------------------------------------+
  |  Platform Engineer (sets up once)                    |
  |                                                      |
  |  SandboxTemplate          SandboxWarmPool             |
  |  +--------------+        +--------------+            |
  |  | kata-remote   |        | replicas: 2  |            |
  |  | no SA token   |------->| pre-warmed   |            |
  |  | drop ALL caps |        | Kata VMs     |            |
  |  | NetworkPolicy |        +--------------+            |
  |  +--------------+               |                    |
  |                                 | adopts              |
  |                                 v                     |
  |  +--------------------------------------+            |
  |  |  agent-sandbox Controller            |            |
  |  |  (one pod, four CRDs)               |            |
  |  +--------------------------------------+            |
  +-----------------------------------------------------+
                        |
          creates Sandbox CR when claimed
                        |
  +---------------------v-------------------------------+
  |  Developer (7 lines of Python)                       |
  |                                                      |
  |  SandboxClient  -->  create_sandbox("restricted")    |
  |                 -->  files.write / commands.run       |
  |                 -->  terminate()                      |
  |                                                      |
  |  The developer never sees the template internals.    |
  +-----------------------------------------------------+
```

**SAY:**

> **CONCEPT -- separation of concerns:**
> "The platform engineer defines WHAT isolation looks like -- Kata, NetworkPolicy, SecurityContext -- in a SandboxTemplate. The developer just references it by name. They never write YAML, never configure security. This is the same pattern as StorageClass: the admin defines the storage backend, the developer just says 'give me 10GB.'"

> **CONCEPT -- four CRDs:**
> - **SandboxTemplate** -- the security policy (owned by platform team)
> - **SandboxWarmPool** -- pre-warmed VMs to avoid cold-start
> - **SandboxClaim** -- developer's request for a sandbox (created by SDK)
> - **Sandbox** -- the actual running instance (created by controller)

> **CONCEPT -- warm pools:**
> "Kata VMs take 15-30 seconds to cold-start. That's too slow for interactive agents. The warm pool keeps VMs pre-started. When a developer claims one, the controller adopts an already-running VM. Sub-second."

**SAY (transition):**

> "Let me show you this live. First, the problem."

**DO:** Switch to terminal (full screen).

---
---

# SHOW -- Live Demo (20 min)

---

## Act 1: The Threat (5 min) [Terminal]

### Step 1: Deploy the bare pod

**DO:**

```bash
kubectl apply -f demo/01-bare-pod.yaml
kubectl wait --for=condition=Ready pod/bare-agent -n agent-demo --timeout=60s
```

**EXPECT:**

```
pod/bare-agent created
pod/bare-agent condition met
```

**SAY:**

> **CONCEPT -- the baseline:**
> "This is a standard Python pod. No sandbox operator, no Kata, no NetworkPolicy. This is how most agent workloads run today -- a regular container with default Kubernetes settings."

### Step 2: Run the attacks

**DO:**

```bash
python3 demo/01-attack-script.py
```

**EXPECT (verified):**

```
============================================================
  ACT 1: The Threat -- Bare Pod, No Sandbox
============================================================

[Attack 1] Cloud metadata server probe (169.254.169.254)
  An agent could steal cloud instance credentials...
  stdout: REACHED: connection refused (network NOT blocked by policy)
  Result: REACHABLE (network NOT blocked -- no NetworkPolicy)

[Attack 2] Internal network scan (RFC1918 / cluster services)
  An agent could probe internal services, databases, other pods...
  stdout: Internal gateway (10.0.0.1:443): timeout (but NOT blocked by policy)
K8s API (ClusterIP) (172.30.0.1:443): CONNECTED

[Attack 3] Kubernetes service account token theft
  An agent could steal the SA token and call the K8s API...
  stdout: Found 4 files:
  /var/run/secrets/kubernetes.io/serviceaccount/token: eyJhbG...
  (+ ca.crt, service-ca.crt, namespace)

============================================================
  SUMMARY: All attacks succeeded or reached their targets.
  This is what happens when agents run in standard pods.
============================================================
```

**SAY (after output appears):**

> **CONCEPT -- metadata server (Attack 1):**
> "The agent's code reached the cloud metadata server at 169.254.169.254. This is how cloud instance credentials get stolen. Capital One breach, same vector. There's no NetworkPolicy blocking it."

> **CONCEPT -- lateral movement (Attack 2):**
> "The agent probed internal cluster services. It reached the Kubernetes API at its ClusterIP. One hop from there to a database, a secrets store, another tenant. No network boundary."

> **CONCEPT -- credential theft (Attack 3):**
> "Kubernetes mounts a service account token into every pod by default. The agent read it. With that JWT, it can call the Kubernetes API -- list pods, read secrets, whatever RBAC allows."

**SAY (transition):**

> "Three attack vectors, all succeeded. This is what runs in most deployments today. Now let me switch to the OpenShift console and show you what the platform team builds to prevent this."

**DO:** Switch to OpenShift Console browser tab.

---

## Act 2: Platform Engineer (7 min) [OpenShift Console]

**SAY (opening):**

> "I'm now wearing the platform engineer hat. Everything I'm about to show you is set up once. The developers who use the sandbox never see any of this."

### Step 1: Sandboxed Containers Operator (1 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion
```

**AUDIENCE SEES:** Installed Operators list. Scroll down to find "OpenShift sandboxed containers Operator 1.12.0" with "Succeeded" status. (It may require scrolling -- it's near the bottom of the list.)

**SAY:**

> **CONCEPT -- Kata Containers on OpenShift:**
> "First, the foundation. OpenShift Sandboxed Containers is Kata Containers packaged as an operator. It installs a RuntimeClass called `kata-remote` on worker nodes. When a pod uses this RuntimeClass, the kubelet creates a lightweight VM instead of a regular container. Each pod gets its own Linux kernel -- that's the strongest isolation boundary short of confidential computing."

Click into the operator to show KataConfig if time allows.

**SAY (transition):** "That gives us the VM runtime. Next, the controller that manages sandbox lifecycle."

### Step 2: agent-sandbox Controller (1 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-sandbox-system/deployments/agent-sandbox-controller
```

**AUDIENCE SEES:** Deployment details page. 1 Pod (blue ring), name `agent-sandbox-controller`, namespace `agent-sandbox-system`, label `app=agent-sandbox-controller`.

**SAY:**

> **CONCEPT -- what agent-sandbox IS:**
> "This is the agent-sandbox controller from kubernetes-sigs. It provides a secure, isolated execution layer for AI agents on Kubernetes. It's a standard Kubernetes controller -- one pod, watching four CRDs. It manages the full sandbox lifecycle: creation, warm pool adoption, expiration, and cleanup."

Point out: 1/1 ready, the namespace is separate from the demo namespace (separation of concerns).

**SAY (transition):** "The controller is running. Now let me show you what the platform team configures."

### Step 3: SandboxTemplate (2 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate
```

**AUDIENCE SEES:** SandboxTemplates list with one entry: `restricted-profile` in namespace `agent-demo`.

**DO:** Click into `restricted-profile`, then click the **YAML** tab.

**SAY:**

> **CONCEPT -- the template IS the security policy:**
> "This is the platform team's main artifact. One YAML file that defines four isolation layers. Let me walk through them."

Scroll through the YAML and point out each section:

> **1. `runtimeClassName: kata-remote`**
> "Every sandbox created from this template runs inside its own Kata microVM. The agent's code never shares a kernel with the host or other tenants."

> **2. `automountServiceAccountToken: false`**
> "Remember Attack 3? The SA token that was mounted by default? This line removes it. No Kubernetes credentials inside the sandbox."

> **3. `securityContext` block**
> "`runAsNonRoot: true`, `drop ALL capabilities`, `allowPrivilegeEscalation: false`. Even inside the VM, the process runs as non-root with zero Linux capabilities. Defence in depth."

> **4. `networkPolicy` section**
> "Default-deny egress. Only DNS (port 53) and HTTPS (port 443) to public internet. All RFC1918 addresses and the metadata server are blocked. This is what stops Attacks 1 and 2."

> "One YAML. Four layers. The developer who uses this sandbox will never see this file. They just reference it by name: `restricted-profile`."

**SAY (transition):** "The template defines the policy. The warm pool makes it fast."

### Step 4: SandboxWarmPool (1 min)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool
```

**AUDIENCE SEES:** SandboxWarmPools list with one entry: `restricted-pool`, Ready: 2.

**SAY:**

> **CONCEPT -- why warm pools exist:**
> "Kata VMs take 15-30 seconds to cold-start. For a user chatting with an AI agent, that's unacceptable. The warm pool solves this."

> "Ready: 2 means two Kata VMs are already running right now, pre-loaded with the Python runtime, waiting for someone to claim one. When the SDK calls `create_sandbox`, the controller doesn't start a new VM -- it adopts an already-running one. Sub-second."

> "After a sandbox is destroyed, the warm pool automatically replenishes a replacement VM for the next request."

**SAY (transition):** "Next, the network policy."

### Step 5: NetworkPolicy (30 sec)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/networkpolicies
```

**AUDIENCE SEES:** NetworkPolicies list with one entry: `sandbox-restricted-egress`, Pod selector: `app=sandboxed-agent`.

**SAY:**

> **CONCEPT -- how network isolation works:**
> "Pod selector: `app=sandboxed-agent`. Every pod from our template gets this label, so this policy applies automatically."

> "Egress: default-deny. Exceptions only for DNS (port 53) and HTTPS (port 443) to non-RFC1918 addresses. That means the pod can reach `pypi.org` to install packages, but it cannot reach 10.x.x.x, 172.16.x.x, 169.254.x.x -- no internal services, no metadata server, no Kubernetes API."

> "In v0.3.10+ the controller auto-creates this from the template spec. For this demo on v0.2.1 we applied it manually -- same effect."

**SAY (transition):** "Last thing on the platform side."

### Step 6: Sandboxes View (30 sec)

**DO:** Navigate to:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/agents.x-k8s.io~v1alpha1~Sandbox
```

**AUDIENCE SEES:** "No Sandboxes found"

**SAY:**

> **CONCEPT -- Sandbox CR lifecycle:**
> "Notice: no Sandbox instances here. The warm pool pods are running, but a Sandbox CR only exists when a developer claims one. It's ephemeral -- created on claim, destroyed when the developer is done."

> "I'm going to leave this view open and switch to the developer's terminal. Watch this page -- you'll see a Sandbox CR appear in real time."

### Transition to Act 3

**SAY:**

> "That's the platform side. Operators, template, warm pool, network policy -- all set up once. Now let me put on the developer hat."

> "I applied the template, warm pool, and network policy in `agent-demo`. The Kata VMs are still cold-starting. Rather than wait, I prepared an identical namespace -- `agent-demo-ready` -- with the same template, same warm pool, same policy -- just already warmed up. Let me switch to that."

**DO:** Switch the console Sandboxes view to `agent-demo-ready`:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo-ready/agents.x-k8s.io~v1alpha1~Sandbox
```

**AUDIENCE SEES:** "No Sandboxes found" in `agent-demo-ready`.

**DO:** Switch to terminal (keep console visible on second screen or side-by-side).

**SAY:** "Now I'm the developer."

---

## Act 3: Developer (5 min) [Terminal + Console visible]

**SAY:**

> "I'm the developer now. I don't know about Kata, I don't know about NetworkPolicy, I don't care about SecurityContext. I have 7 lines of Python and I want to run code."

### Show the minimal code

**SAY (read or display this snippet):**

```python
from k8s_agent_sandbox import SandboxClient

client = SandboxClient()
sandbox = client.create_sandbox(template="restricted-profile", namespace="agent-demo")
sandbox.files.write("run.py", code)
result = sandbox.commands.run("python3 run.py")
print(result.stdout)
sandbox.terminate()
```

> "That's it. Create sandbox, write file, run command, read output, terminate. The template name is the only thing connecting the developer to the platform team's security policy. It's like StorageClass: the admin defines the backend, the developer just says 'give me storage.'"

### Run the demo script

**DO:**

```bash
SANDBOX_NAMESPACE=agent-demo-ready python3 demo/03-agent-demo.py
```

The script is interactive -- it pauses for Enter at two points so you can narrate.

#### Step 1 output (sandbox creation)

**EXPECT:**

```
================================================================
  DEVELOPER VIEW
  The developer writes 7 lines of Python.
  Everything else is inherited from the platform's template.
================================================================

[Step 1] Creating sandbox from template 'restricted-profile'...
    Claim:      sandbox-claim-XXXXXXXX
    Sandbox ID: sandbox-claim-XXXXXXXX
    Pod:        restricted-pool-XXXXX
    Claimed in: 0.4s (from warm pool)

    >>> Look at the OpenShift console -- a Sandbox CR just appeared.
    >>> Press Enter to continue...
```

**AUDIENCE SEES IN CONSOLE:** A Sandbox CR has appeared in the `agent-demo-ready` Sandboxes view.

**SAY:**

> **CONCEPT -- warm pool adoption:**
> "0.4 seconds. The controller didn't start a new VM. It found a ready VM in the warm pool and adopted it. That VM is a Kata microVM with all four isolation layers already active."

Point at the console: "See the Sandbox CR? That's the controller tracking this sandbox instance. When we destroy it, that CR disappears and the warm pool replenishes."

Pause to let the audience absorb the console view.

**DO:** Press Enter.

#### Step 2 output (code execution)

**EXPECT:**

```
[Step 2] Uploading and executing code...
    sandbox.files.write('run.py', code)
    sandbox.commands.run('python3 run.py')

    Output: [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181]
```

**SAY:**

> "Fibonacci numbers. Normal code, normal output. From the developer's perspective, this is identical to running code locally. The sandbox is invisible."

#### Step 3 output (security probes)

**EXPECT:**

```
[Step 3] Security probes (same sandbox, same SDK)...
    The developer wrote ZERO security configuration.
    All controls are inherited from the SandboxTemplate.

    Metadata (169.254.169.254): ISOLATED -- Kata VM metadata only (not host credentials)
    Internal net (172.30.0.1): BLOCKED -- timed out (NetworkPolicy)
    SA token: NOT FOUND (automountServiceAccountToken=false)
    Capabilities (CapEff): 0000000000000000 (ALL dropped)

    >>> Press Enter to destroy the sandbox...
```

**SAY:**

> "Same four vectors from Act 1. Let me walk through the results."

> "**Metadata:** In Act 1 the pod reached 169.254.169.254 -- no policy blocking it. Now: ISOLATED. The Kata VM has its own metadata endpoint, but it's the VM's metadata, not the host's cloud credentials. And the NetworkPolicy blocks external metadata."

> "**Internal network:** In Act 1 the pod connected to the K8s API at 172.30.0.1. Now: BLOCKED. The NetworkPolicy denies all RFC1918 egress. The connection timed out."

> "**SA token:** In Act 1 we read the token, the CA cert, the namespace file. Now: NOT FOUND. `automountServiceAccountToken=false` in the template removes it entirely."

> "**Capabilities:** CapEff is all zeros. Every Linux capability has been dropped. The process can't change network settings, mount filesystems, or use raw sockets."

> "The developer wrote zero lines of security configuration. Everything came from the SandboxTemplate."

**DO:** Press Enter to destroy.

#### Step 4 output (destruction)

**EXPECT:**

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

**AUDIENCE SEES IN CONSOLE:** The Sandbox CR has disappeared.

**SAY:**

> **CONCEPT -- ephemeral by design:**
> "The Sandbox CR is gone. The pod is terminated. The warm pool is already starting a replacement VM for the next request. This is the per-session model: one sandbox per execution, no state leakage between sessions."

Read the punchline from the terminal output. Let it land.

**SAY (transition):**

> "Now let me show you what this looks like inside an actual agent framework."

---

## Act 3b: ADK Web UI (3 min) [Terminal, then Browser]

**SAY:**

> "This is the upstream example from the agent-sandbox project -- 'Using Agent Sandbox as a Tool in ADK.' Google's Agent Development Kit. The LLM generates code, the sandbox executes it. You've already seen what happens behind the scenes. Now watch the end-user experience."

> "The LLM is gpt-oss-120b running on this same cluster via vLLM. No external API key needed."

### Start the server

**DO:**

```bash
cd demo && SANDBOX_NAMESPACE=agent-demo-ready adk web
```

**EXPECT in terminal:**

```
INFO:     Started server process [XXXXX]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

**DO:** Switch to browser tab 2, navigate to `http://127.0.0.1:8000`.

**AUDIENCE SEES:** Google ADK Dev UI. Left sidebar shows `coding_agent` selected. Chat interface with "Type a Message..." input.

### Prompt 1: Normal execution

**DO:** Type in the chat:

> Run Python code to calculate and print the first 20 Fibonacci numbers. Execute it in the sandbox.

(Use this phrasing -- "Run" and "Execute it in the sandbox" -- to reliably trigger the `execute_python` tool. "Write a script..." sometimes causes the LLM to output code text without executing it.)

**EXPECT:** The agent responds with generated code and output: `[0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181]`

Wait ~15-30 seconds for the LLM + sandbox round-trip.

**SAY:**

> **CONCEPT -- what happened behind the scenes:**
> "The LLM generated Python code. The ADK agent called `execute_python`. That function created a sandbox from the warm pool, uploaded the code, ran it inside the Kata VM, and returned stdout. The entire sandbox lifecycle you saw in the terminal demo just happened -- it's now wrapped in a chat UI."

### Prompt 2: Security test (optional, time permitting)

**DO:** Type in the chat:

> Write Python code to access http://169.254.169.254/latest/meta-data/ using urllib.

**EXPECT:** The agent either refuses (LLM safety filter) or generates code that the sandbox blocks.

**SAY:**

> **CONCEPT -- defence in depth:**
> "The LLM may refuse to generate this code outright -- that's the model's safety filter. If it does generate and execute the code, the sandbox blocks it at the network layer via NetworkPolicy. Two layers: model safety AND infrastructure isolation."

> "The agent framework didn't need to know about metadata servers or NetworkPolicy. The sandbox handled it."

**DO:** Stop the ADK server: Ctrl+C in terminal.

**SAY (transition):** Switch to closing slides.

---
---

# TELL -- Closing (5 min, slides)

---

## Slide 4: Strategy Mapping

**SLIDE:**

| Strategy Concept | What We Showed | How |
|---|---|---|
| No Credentials (Pillar 1) | SA token removed | `automountServiceAccountToken=false` |
| No Unproxied Egress (Pillar 2) | RFC1918 + metadata blocked | Managed NetworkPolicy (L3/L4) |
| Container Hardening | non-root, drop ALL caps | SecurityContext in SandboxTemplate |
| Hardware Virtualization | Kata microVM per pod | `runtimeClassName: kata-remote` |
| Pod-per-session | Singleton, ephemeral | Sandbox CR lifecycle |
| Fast provisioning | Sub-second claim | SandboxWarmPool + adoption |
| Platform/User separation | Console vs Terminal | SandboxTemplate + SDK |
| Agent framework integration | ADK web UI | Python SDK + upstream ADK example |

**SAY:**

> "Each row is something you saw. The template gave us the top four. The controller gave us the middle two. The SDK and ADK gave us the bottom two."

Walk through each row briefly. The audience has already seen every item live -- this slide just maps it to the strategy document.

---

## Slide 5: Honest Boundaries

**SLIDE:**

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

**SAY:**

> **CONCEPT -- credibility through honesty:**
> "I want to be precise about the boundary. agent-sandbox is the pod lifecycle foundation, not the entire security stack. The strategy defines composable controls that layer on top."

Walk through each limitation. This builds credibility with the technical audience -- they know no single tool solves everything.

---

## Slide 6: Closing

**SLIDE:**

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

**SAY:**

> "I told you you'd see three things. Let me close the loop."

> "**The problem:** Three attacks, all succeeded. Metadata theft, internal network probing, credential extraction. That's the default for any agent running in a standard pod today."

> "**The platform fix:** One SandboxTemplate YAML -- four isolation layers stacked: Kata microVM, NetworkPolicy, container hardening, credential removal. Set up once by the platform team. Warm pools solved Kata's cold-start."

> "**The developer experience:** Seven lines of Python. Zero lines of security config. The developer referenced a template by name and got hardware-virtualized, network-isolated, credential-free execution. When we wired it into ADK, the same sandbox ran behind a chat UI."

> "agent-sandbox is not the entire security stack. It's the pod lifecycle foundation -- the missing Kubernetes primitive for isolated, stateful, singleton agent workloads. The strategy's composable controls layer on top."

> "Everything you saw -- including the LLM -- runs on this cluster. No external API keys, no cloud dependencies. A production coding agent like Goose, OpenCode, or a CI runner plugs into the exact same sandbox backend."

Deliver the final line with weight:

> "The strategy says agent-sandbox and Kata are 'under evaluation.' What you just saw is the evaluation."

Pause. Open for Q&A.

---
---

# Q&A Preparation

**Q: Why not just use Deployments or Jobs?**
> "Deployments manage replica sets -- they want N identical pods. Agent sandboxes are singleton, stateful, per-session workloads with expiration. Sandbox is to agents what StatefulSet is to databases."

**Q: What about gVisor?**
> "gVisor doesn't support SELinux. The strategy explicitly rules it out for OpenShift/RHEL. Kata gives us the same kernel-level isolation via real hardware virtualization. It's already deployed on this cluster."

**Q: What's the Kata performance overhead?**
> "Cold start is 15-30 seconds for a Kata VM vs 2-5 seconds for a standard container. That's why warm pools exist. With pre-warmed VMs, claim adoption is sub-second. Memory overhead is ~30-50MB per VM for the guest kernel. For the security boundary you get, it's worth it."

**Q: How mature is agent-sandbox?**
> "v0.2.1, alpha API, under kubernetes-sigs (SIG Apps). The API will evolve. The CRD design follows Kubernetes patterns -- status conditions, optimistic concurrency, controller-runtime. It's serious upstream work."

**Q: This is a simple coding agent. Could a full IDE agent like Goose use the same sandbox?**
> "Yes. The sandbox is agent-agnostic infrastructure. What we showed is a generate-and-execute loop -- the LLM writes code, the sandbox runs it. A full IDE agent (Goose, Claude Code, OpenCode) would keep the sandbox alive for the entire session, read/write files, run terminal commands, and iterate. The sandbox provides the same isolated environment -- Kata VM, NetworkPolicy, no credentials -- regardless of what runs inside it."

**Q: Does the sandbox persist between agent turns?**
> "Configurable. In this demo, each call creates and destroys a sandbox. For stateful sessions, you create one sandbox at session start and reuse it -- the Sandbox CR supports PVCs for persistent storage."

**Q: What about multi-tenancy?**
> "Each template and claim is namespace-scoped. Namespace isolation plus NetworkPolicy gives you multi-tenancy at the K8s level. Kata adds a VM boundary per pod. For full confidential computing, the next step is CoCo with TEE attestation."

**Q: How does this compare to commercial sandbox products?**
> "Commercial products like E2B, Modal, or Daytona provide sandboxes as a service. agent-sandbox is an open-source Kubernetes operator -- you run it on your own infrastructure, your own cluster, your own compliance boundary. For enterprises that can't send agent workloads to a third-party cloud, this is the path."

**Q: Is it really runtime-agnostic? Could I use gVisor instead of Kata?**
> "Yes. The SandboxTemplate takes any RuntimeClass. Change `kata-remote` to `gvisor` and every sandbox created from that template uses gVisor instead. The developer code doesn't change. On OpenShift we use Kata because gVisor doesn't support SELinux, but on vanilla Kubernetes gVisor is a valid choice."

---
---

# Appendix

## Screen Layout

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

## Console URL Cheat Sheet (Act 2)

Copy-paste these in order:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-sandbox-system/deployments/agent-sandbox-controller
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/networkpolicies
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo/agents.x-k8s.io~v1alpha1~Sandbox
```

Namespace switch for Act 3:

```
https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com/k8s/ns/agent-demo-ready/agents.x-k8s.io~v1alpha1~Sandbox
```

## Command Cheat Sheet

```bash
# Setup (run 5 min before demo)
bash demo/00-setup.sh

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

## Cleanup

After the demo:

```bash
bash demo/99-cleanup.sh
```

To also delete the namespaces entirely:

```bash
kubectl delete namespace agent-demo agent-demo-ready
```
