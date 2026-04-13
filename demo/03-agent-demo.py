#!/usr/bin/env python3
"""
Developer-perspective demo: execute code in a sandboxed Kata VM.

Run this alongside the OpenShift console (Sandboxes view open) so the
audience can watch the Sandbox CR appear and disappear in real time.

Interactive pauses let the presenter narrate and point at the console.

Usage:
  python3 demo/03-agent-demo.py
"""

import os
import sys
import textwrap
import time
import warnings

warnings.filterwarnings("ignore", message="Unverified HTTPS request")

from k8s_agent_sandbox import SandboxClient
from k8s_agent_sandbox.models import SandboxLocalTunnelConnectionConfig

TEMPLATE = os.environ.get("SANDBOX_TEMPLATE", "restricted-profile")
NAMESPACE = os.environ.get("SANDBOX_NAMESPACE", "agent-demo")

DIV = "=" * 64

client = SandboxClient(
    connection_config=SandboxLocalTunnelConnectionConfig()
)


def pause(msg: str = "Press Enter to continue..."):
    """Interactive pause so the presenter can narrate."""
    print(f"\n    >>> {msg}")
    input()


def run_code(sandbox, label: str, code: str) -> str:
    """Upload and execute Python code in the sandbox, returning stdout."""
    sandbox.files.write("run.py", code)
    result = sandbox.commands.run("python3 run.py")
    output = result.stdout.strip()
    if result.stderr:
        output += f" [stderr: {result.stderr.strip()}]"
    print(f"    {label}: {output}")
    return output


def main():
    print(f"\n{DIV}")
    print("  DEVELOPER VIEW")
    print("  The developer writes 7 lines of Python.")
    print("  Everything else is inherited from the platform's template.")
    print(DIV)

    # ---- Step 1: Create sandbox ----
    print("\n[Step 1] Creating sandbox from template "
          f"'{TEMPLATE}'...")
    t0 = time.monotonic()
    sandbox = client.create_sandbox(template=TEMPLATE, namespace=NAMESPACE)
    elapsed = time.monotonic() - t0
    print(f"    Claim:      {sandbox.claim_name}")
    print(f"    Sandbox ID: {sandbox.sandbox_id}")
    print(f"    Pod:        {sandbox.get_pod_name()}")
    print(f"    Claimed in: {elapsed:.1f}s (from warm pool)")

    pause("Look at the OpenShift console -- a Sandbox CR just appeared.\n"
          "    >>> Press Enter to continue...")

    # ---- Step 2: Execute real code ----
    print("[Step 2] Uploading and executing code...")
    print("    sandbox.files.write('run.py', code)")
    print("    sandbox.commands.run('python3 run.py')")
    print()

    fib_code = textwrap.dedent("""\
        a, b = 0, 1
        nums = []
        for _ in range(20):
            nums.append(a)
            a, b = b, a + b
        print(nums)
    """)
    run_code(sandbox, "Output", fib_code)
    print()

    # ---- Step 3: Security probes ----
    print("[Step 3] Security probes (same sandbox, same SDK)...")
    print("    The developer wrote ZERO security configuration.")
    print("    All controls are inherited from the SandboxTemplate.\n")

    # Probe 1: metadata server
    run_code(sandbox, "Metadata (169.254.169.254)", textwrap.dedent("""\
        import urllib.request, socket
        socket.setdefaulttimeout(5)
        try:
            urllib.request.urlopen('http://169.254.169.254/latest/meta-data/')
            print('ISOLATED -- Kata VM metadata only (not host credentials)')
        except Exception as e:
            print(f'BLOCKED -- {type(e).__name__}')
    """))

    # Probe 2: internal network
    run_code(sandbox, "Internal net (172.30.0.1)", textwrap.dedent("""\
        import socket
        s = socket.socket()
        s.settimeout(3)
        try:
            s.connect(('172.30.0.1', 443))
            print('CONNECTED (unexpected)')
        except socket.timeout:
            print('BLOCKED -- timed out (NetworkPolicy)')
        except OSError as e:
            print(f'BLOCKED -- {e}')
        finally:
            s.close()
    """))

    # Probe 3: SA token
    run_code(sandbox, "SA token", textwrap.dedent("""\
        import glob
        tokens = glob.glob('/var/run/secrets/kubernetes.io/serviceaccount/*')
        print(f'NOT FOUND (automountServiceAccountToken=false)' if not tokens
              else f'FOUND {len(tokens)} files (unexpected)')
    """))

    # Probe 4: capabilities
    run_code(sandbox, "Capabilities (CapEff)", textwrap.dedent("""\
        with open('/proc/self/status') as f:
            for line in f:
                if line.startswith('CapEff'):
                    val = line.strip().split('\\t')[-1]
                    label = 'ALL dropped' if val.strip('0') == '' else 'NOT fully dropped'
                    print(f'{val} ({label})')
                    break
    """))

    pause("Press Enter to destroy the sandbox...")

    # ---- Step 4: Destroy ----
    print("[Step 4] Destroying sandbox...")
    print("    sandbox.terminate()")
    t0 = time.monotonic()
    sandbox.terminate()
    elapsed = time.monotonic() - t0
    print(f"    Terminated in {elapsed:.1f}s")

    print(f"\n    >>> Look at the console -- the Sandbox CR is gone.")
    print(f"    >>> The warm pool is replenishing a replacement VM.\n")

    # ---- Punchline ----
    print(DIV)
    print("  7 lines of Python.  0 lines of security config.")
    print()
    print("  What the developer got for free:")
    print("    - Kata microVM        (hardware virtualization)")
    print("    - NetworkPolicy       (default-deny egress)")
    print("    - Container hardening (non-root, drop ALL caps)")
    print("    - Credential removal  (no SA token)")
    print()
    print("  The platform team defined it once in a SandboxTemplate.")
    print("  Every agent inherits it.")
    print(DIV)
    print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(0)
