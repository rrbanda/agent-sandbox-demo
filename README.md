# agent-sandbox-demo

## Understanding kubernetes-sigs/agent-sandbox

### What Problem Does It Solve?

Kubernetes has two core workload primitives: **Deployments** (stateless, replicated) and **StatefulSets** (numbered, ordered, stable). Neither is designed for a pattern that is now critical in the AI agent era:

> **A single, isolated, stateful container with a stable identity and specialized lifecycle management.**

Today, approximating this requires manually combining a StatefulSet (replica count 1), a headless Service, and PersistentVolumeClaims. This is cumbersome, lacks lifecycle features like hibernation and warm pools, and provides no built-in security defaults.

**agent-sandbox fills this gap** by introducing a purpose-built `Sandbox` CRD and controller that manages isolated, stateful, singleton workloads with first-class lifecycle automation.

### Four Target Use Cases

1. **AI Agent Runtimes** — Isolated environments for executing untrusted, LLM-generated code at high velocity
2. **Cloud Development Environments** — Persistent, network-accessible dev environments (like Codespaces on your own cluster)
3. **Notebooks and Research Tools** — Persistent single-container sessions for Jupyter, ML experimentation
4. **Stateful Single-Pod Services** — Build agents, small databases, CI runners needing stable identity

### Why Existing K8s Primitives Fall Short

| Gap | Detail |
|-----|--------|
| No hibernation | StatefulSets cannot pause/resume; scale-to-zero loses state |
| No warm pools | No way to pre-create pods and instantly assign them to users |
| No shutdown scheduling | No native TTL or expiration for singleton workloads |
| No template/claim abstraction | No way for platform teams to define templates, let users claim instances |
| No managed NetworkPolicy | NetworkPolicy must be manually created; no automatic default-deny posture |

---

## Architecture Deep Dive

### Four CRDs

#### 1. Sandbox (Core) — `agents.x-k8s.io/v1alpha1`

The foundational CRD. Manages a **single pod + headless service + optional PVCs**.

- `spec.podTemplate` — Embedded PodSpec (any container image)
- `spec.volumeClaimTemplates` — PVCs that persist across restarts
- `spec.replicas` — Constrained to **0 or 1** (singleton enforcement)
- `spec.lifecycle.shutdownTime` — Absolute expiration timestamp (UTC)
- `spec.lifecycle.shutdownPolicy` — `Delete` (remove CR on expiry) or `Retain` (mark expired)
- `status.serviceFQDN` — Stable DNS name (e.g., `my-sandbox.default.svc.cluster.local`)
- `status.podIPs` — Current pod IP addresses

**Controller reconciliation loop:**
1. Check if sandbox is being deleted or already expired → short-circuit
2. Reconcile PVCs → create or adopt (with ownership checks)
3. Reconcile Pod → create new, or adopt existing (e.g., from warm pool via `agents.x-k8s.io/pod-name` annotation)
4. Reconcile Service → create headless service with label-based selector
5. Compute Ready condition from pod + service state
6. Handle expiry → delete child resources, optionally delete the Sandbox CR itself

#### 2. SandboxTemplate (Extension) — `extensions.agents.x-k8s.io/v1alpha1`

Defines reusable configurations (pod spec + network policy). Platform teams create templates; users never touch pod specs.

**NetworkPolicy management is built in:**
- `Managed` (default): Controller auto-creates a shared NetworkPolicy per template
  - Default-deny ingress (allows only `app: sandbox-router` pods)
  - Default-deny egress to RFC1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and link-local/metadata (`169.254.0.0/16`)
  - Allows public internet egress only
  - Sets DNS to public resolvers (8.8.8.8, 1.1.1.1) to prevent internal DNS enumeration
- `Unmanaged`: External CNI (Cilium, etc.) handles networking
- Custom rules: User provides explicit ingress/egress rules

**Secure defaults applied to all sandboxes:**
- `automountServiceAccountToken` set to `false` (prevents K8s API access)
- DNS policy set to `None` with public nameservers (in Managed + no custom rules mode)

#### 3. SandboxClaim (Extension) — `extensions.agents.x-k8s.io/v1alpha1`

Users request a sandbox by referencing a SandboxTemplate.

- `spec.sandboxTemplateRef.name` — Points to a SandboxTemplate
- `spec.warmpool` — Warm pool policy: `none` (always fresh), `default` (any matching pool), or a named pool
- `spec.lifecycle.shutdownTime` — Claim-level expiration
- `spec.lifecycle.shutdownPolicy` — `Delete`, `DeleteForeground` (wait for pod termination), `Retain`

**Controller reconciliation logic:**
1. **Fast path**: Look up existing sandbox by status name or claim name, or adopt from warm pool
2. **Cold path**: Fetch template, reconcile NetworkPolicy, create new Sandbox from template
3. Warm pool adoption uses optimistic concurrency (resourceVersion) to handle racing claims
4. Candidates sorted: ready sandboxes first, then by creation time (oldest first)
5. Hash-based starting index reduces contention across concurrent workers

#### 4. SandboxWarmPool (Extension) — `extensions.agents.x-k8s.io/v1alpha1`

Maintains a pool of pre-created, ready-to-use sandbox pods.

- `spec.replicas` — Desired pool size (supports HPA via `/scale` subresource)
- `spec.sandboxTemplateRef` — Template to use for pool sandboxes
- `spec.updateStrategy.type` — `Recreate` (replace stale pods immediately) or `OnReplenish` (replace when adopted)

**Controller mechanics:**
- Computes pod template hash to detect template drift (stale sandboxes)
- 5-minute grace period for sandbox readiness; stuck sandboxes are deleted
- Excess sandboxes deleted in priority order: unready first, then newest first
- Watches SandboxTemplate changes and re-reconciles affected warm pools
- Orphaned sandboxes (no controller owner) are adopted or deleted if stale

### Python SDK and Router

**Python SDK** (`k8s-agent-sandbox` on PyPI):
- `SandboxClient` → `create_sandbox()` → returns `Sandbox` handle
- `sandbox.commands.run("python script.py")` — Execute commands via HTTP POST to `/execute`
- `sandbox.files.write()` / `sandbox.files.read()` — File I/O via `/upload` and `/download` endpoints
- `sandbox.files.list()` / `sandbox.files.exists()` — Directory listing and existence checks
- Async client (`AsyncSandboxClient`) for agent orchestrators
- Auto-cleanup via `atexit` handler; `delete_all()` on program exit
- OTel tracing integration (trace context propagated to K8s annotations)

**Sandbox Router** (FastAPI reverse proxy):
- Receives all requests, reads `X-Sandbox-ID`, `X-Sandbox-Namespace`, `X-Sandbox-Port` headers
- Constructs K8s internal DNS target: `{sandbox_id}.{namespace}.svc.cluster.local:{port}`
- Proxies request via `httpx` async client with streaming response
- Three connection modes:
  - **Gateway mode** (production): Client → Cloud LB → Router → Sandbox Pod
  - **Tunnel mode** (dev): Client → `kubectl port-forward` → Router → Sandbox Pod
  - **Direct mode**: Client → provided URL → Sandbox Pod

**Python Runtime** (reference sandbox container):
- FastAPI server on port 8888
- `/execute` — Runs shell commands via `subprocess.run` in `/app` directory
- `/upload` — Saves uploaded files to `/app`
- `/download/{path}` — Downloads files with path traversal protection (`os.path.realpath` check)
- `/list/{path}` — Lists directory contents
- `/exists/{path}` — Checks file/directory existence

### Policy Examples (Upstream Reference)

The upstream agent-sandbox project describes a **ValidatingAdmissionPolicy** pattern that enforces security controls such as requiring a sandbox runtime, blocking host networking, dropping ALL capabilities, enforcing runAsNonRoot, and preventing privilege escalation. This demo achieves the same controls declaratively through the `SandboxTemplate` in `demo/02-python-sandbox-template.yaml` rather than a separate VAP resource.

---

## Mapping to Agent Sandboxing Strategy Document

### What agent-sandbox Provides (per strategy control)

| Strategy Control | agent-sandbox Coverage | Implementation Detail |
|---|---|---|
| **Container Hardening** (non-root, drop caps, seccomp) | Partial — via SandboxTemplate PodSpec | User must configure `securityContext` in template; `automountServiceAccountToken=false` is auto-set |
| **Network Isolation** (default-deny, OSI L3/L4) | Full — via SandboxTemplate NetworkPolicy | Auto-creates NetworkPolicy blocking RFC1918, metadata server, link-local; allows only public internet |
| **Runtime Agnosticism** (runc, Kata, gVisor) | Full — via standard `runtimeClassName` | Examples provided for gVisor (KIND), Kata (minikube), standard runc |
| **Pod-per-session Model** | Full — `replicas` constrained to 0 or 1 | Enforced by kubebuilder validation (`Minimum=0, Maximum=1`) |
| **Warm Pool / Fast Provisioning** | Full — SandboxWarmPool CRD | Pre-warmed pods, HPA support, template drift detection, optimistic concurrency adoption |
| **Shutdown/Expiration** | Full — `shutdownTime` + `shutdownPolicy` | Absolute UTC time, auto-deletion or retain-as-expired |
| **Stable Identity / DNS** | Full — headless Service per sandbox | `{name}.{namespace}.svc.cluster.local` |
| **Persistent Storage** | Full — `volumeClaimTemplates` | PVCs with ownership tracking, survive restarts |
| **Programmable API** | Full — Python SDK + Go client (roadmap) | `k8s-agent-sandbox` PyPI package, async support |
| **OTel Tracing** | Partial — trace context propagation | Annotations carry trace context; controller exposes standard controller-runtime metrics |
| **ValidatingAdmissionPolicy** | Pattern described upstream | Security controls enforced via SandboxTemplate SecurityContext in this demo |

### What agent-sandbox Does NOT Provide (Strategy Must Layer On Top)

| Strategy Control | Gap | How Strategy Fills It |
|---|---|---|
| **Pillar 1: Zero Credentials** | Not addressed — agent-sandbox doesn't manage secrets | Budget Proxy (holds LLM API keys), AuthBridge (SPIFFE→OAuth token exchange), HashiCorp Vault (planned) |
| **Filesystem Isolation (Landlock)** | Not addressed — OS-level kernel LSM, not K8s API | Landlock LSM enforcement per tool call (~7ms overhead), deployed in container runtime |
| **Egress Filtering (OSI L7)** | Partial — NetworkPolicy is L3/L4 only | Squid/Tinyproxy domain allowlist proxy for HTTP CONNECT filtering; ~50MB RAM overhead |
| **Encryption (mTLS)** | Not addressed — transport-level concern | Istio Ambient mTLS (ztunnel) for zero-config pod-to-pod encryption |
| **Authentication** | Not addressed — application-level concern | Keycloak + AuthBridge sidecar for OIDC authentication |
| **Authorization (K8s RBAC)** | Partial — namespace-scoped CRDs enable RBAC | Strategy adds per-agent RBAC via Kubernetes RBAC per namespace |
| **Human Oversight (HITL)** | Not addressed — application-level workflow | HITL approval gates in the agent framework layer |
| **Full Audit Trail** | Partial — controller metrics and OTel traces | Events table capturing tool calls (args + output), OTel export to Phoenix/MLflow |
| **Code Scanning** | Not addressed — defense-in-depth addition | Optional pre-execution or post-execution scanning |
| **Session Pause/Resume (CRIU)** | Not started — on roadmap as PVC-based scale-down | Strategy lists CRIU checkpoint as aspirational upstream feature |
| **Confidential Computing** | Not started — on roadmap | Kata/CoCo for hardware TEE (Intel TDX, AMD-SEV) |

### Precise Mapping to Strategy Isolation Profiles

| Profile | agent-sandbox Role | Additional Strategy Components |
|---|---|---|
| **Development** | Sandbox CRD with basic template | Egress Proxy sidecar |
| **Standard** | SandboxTemplate with managed NetworkPolicy | Container hardening via SecurityContext + Egress Proxy |
| **Production** | SandboxTemplate + NetworkPolicy + gVisor/Kata RuntimeClass | Landlock filesystem isolation + Egress Proxy |
| **Restricted** | SandboxTemplate + NetworkPolicy + source policy (VAP) + Kata | Landlock + Egress Proxy + image provenance policy |
| **Confidential** | SandboxTemplate + NetworkPolicy + Kata/CoCo RuntimeClass | Landlock + Egress Proxy + hardware TEE |

### Integration Points

The strategy document lists `kubernetes-sigs/agent-sandbox` as **"Under Evaluation"** with blocker: **"Upstream maturity"** (currently alpha API; this demo uses v0.2.1, latest upstream is v0.3.10 which adds auto-managed NetworkPolicy). The precise integration model:

1. **agent-sandbox provides the pod lifecycle layer** — create, adopt, warm pool, shutdown, DNS
2. **Strategy layers security controls on top** — via SecurityContext in templates, NetworkPolicy (built-in), Landlock (in-container), egress proxy (sidecar), AuthBridge (sidecar), Budget Proxy (separate service)
3. **ValidatingAdmissionPolicy enforces invariants** — the 16-control VAP example blocks non-compliant sandboxes at admission time
4. **OTel traces flow end-to-end** — SDK injects trace context → controller propagates to annotations → OTel collector exports

### Key Gaps and Risks

1. **gVisor ruled out by strategy** — Strategy rules out gVisor (no SELinux, incompatible with OpenShift), but agent-sandbox examples prominently feature gVisor. Kata is the strategy's preferred runtime.
2. **No L7 egress filtering** — NetworkPolicy operates at L3/L4. The strategy requires L7 domain filtering (Squid proxy). This must be deployed as a sidecar or egress gateway, not via agent-sandbox.
3. **Zero-secret architecture is entirely separate** — Budget Proxy, AuthBridge, and Vault are independent infrastructure components. agent-sandbox has no concept of credential management.
4. **Alpha API maturity** — `v1alpha1` API may change. The strategy notes "upstream maturity" as a blocker for adoption.
5. **Python runtime has no security hardening** — The reference `main.py` runtime executes arbitrary commands via `subprocess.run` with no sandboxing within the container. Security depends entirely on the container/VM boundary.
6. **NetworkPolicy coverage gap on Podman** — Strategy highlights no Podman equivalent to NetworkPolicy; agent-sandbox is K8s-only for network isolation.
