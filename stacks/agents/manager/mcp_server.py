"""FastMCP server exposing the LangGraph manager over streamable-HTTP.

Bound to 0.0.0.0:8900 so Hermes (on a different container) can reach it over
the network. stdio transport would not work cross-container.

Tools:
  delegate(task, role="auto") -> str   run the supervisor graph, return result
  list_roles() -> list                 available role names
  healthcheck() -> str                 liveness + Ollama reachability
"""
import os

import httpx
from mcp.server.fastmcp import FastMCP

from agents import OLLAMA_BASE_URL, ROLES
from graph import run_task

mcp = FastMCP(
    name="local_agents",
    host="0.0.0.0",
    port=8900,
)


@mcp.tool()
async def delegate(task: str, role: str = "auto") -> str:
    """Delegate a task to the local Ollama-backed agent manager.

    Args:
        task: The natural-language task to run on a local sub-agent.
        role: Which role to use ("auto" picks automatically; "worker" is the
              generic role).
    Returns:
        The sub-agent's final answer as a string.
    """
    return await run_task(task, role)


@mcp.tool()
async def list_roles() -> list:
    """List the available local agent roles."""
    return list(ROLES.keys())


@mcp.tool()
async def healthcheck() -> str:
    """Check the manager is alive and Ollama is reachable."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            r = await client.get(f"{OLLAMA_BASE_URL}/api/tags")
            r.raise_for_status()
        models = [m["name"] for m in r.json().get("models", [])]
        return f"ok; ollama reachable at {OLLAMA_BASE_URL}; models={models}"
    except Exception as e:  # noqa: BLE001
        return f"degraded; ollama unreachable at {OLLAMA_BASE_URL}: {e}"


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "streamable-http")
    mcp.run(transport=transport)
