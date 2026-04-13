"""ADK coding agent backed by kubernetes-sigs/agent-sandbox.

Based on the upstream example:
https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/adk

Adapted for OpenShift with on-cluster LLM (gpt-oss-120b via vLLM).
"""

import os

from google.adk.agents.llm_agent import Agent
from google.adk.models.lite_llm import LiteLlm
from k8s_agent_sandbox import SandboxClient
from k8s_agent_sandbox.models import SandboxLocalTunnelConnectionConfig

os.environ.setdefault("OPENAI_API_BASE",
    "https://gpt-oss-120b-gpt-oss-120b.apps.ocp.v7hjl.sandbox2288.opentlc.com/v1")
os.environ.setdefault("OPENAI_API_KEY", "unused")

_client = SandboxClient(connection_config=SandboxLocalTunnelConnectionConfig())


def execute_python(code: str):
    sandbox = _client.create_sandbox(
        template=os.environ.get("SANDBOX_TEMPLATE", "python-sandbox-template"),
        namespace=os.environ.get("SANDBOX_NAMESPACE", "agent-demo"),
    )
    try:
        sandbox.files.write("run.py", code)
        result = sandbox.commands.run("python3 run.py")
        return result.stdout
    finally:
        sandbox.terminate()


root_agent = Agent(
    model=LiteLlm(model="openai/gpt-oss-120b"),
    name="coding_agent",
    description="Writes Python code and executes it in a sandbox.",
    instruction=(
        "You are a helpful assistant that can write Python code and execute "
        "it in the sandbox. Use the 'execute_python' tool for this purpose."
    ),
    tools=[execute_python],
)
