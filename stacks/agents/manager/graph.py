"""LangGraph supervisor graph.

supervisor node -> routes the task to a role -> worker node runs it.

Every Ollama generation is wrapped in a module-level asyncio.Semaphore(1) so
that only one generation runs at a time. This serializes all GPU work on the
single RTX 3060 behind llm-lxc.
"""
import asyncio
from typing import Optional, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage

from agents import ROLES, llm

# GPU serialization: only one Ollama generation at a time, ever.
GPU_SEMAPHORE = asyncio.Semaphore(1)


class State(TypedDict):
    task: str
    role: str          # requested role, or "auto"
    chosen_role: str   # role the supervisor selected
    result: str


async def _ollama_invoke(messages) -> str:
    """Invoke the resident model under the GPU semaphore."""
    async with GPU_SEMAPHORE:
        resp = await llm.ainvoke(messages)
    return resp.content


async def supervisor_node(state: State) -> dict:
    """Decide which role handles the task.

    With a single role (worker) this is trivial, but the routing seam is kept
    so future roles (researcher/coder/summarizer) can be added without changing
    the graph shape.
    """
    requested = state.get("role", "auto")
    if requested != "auto" and requested in ROLES:
        chosen = requested
    else:
        # Only one role in the MVP; default to it.
        chosen = "worker"
    return {"chosen_role": chosen}


async def worker_node(state: State) -> dict:
    role = state["chosen_role"]
    system_prompt = ROLES.get(role, ROLES["worker"])
    messages = [
        SystemMessage(content=system_prompt),
        HumanMessage(content=state["task"]),
    ]
    result = await _ollama_invoke(messages)
    return {"result": result}


def build_graph():
    from langgraph.graph import END, START, StateGraph

    g = StateGraph(State)
    g.add_node("supervisor", supervisor_node)
    g.add_node("worker", worker_node)
    g.add_edge(START, "supervisor")
    g.add_edge("supervisor", "worker")
    g.add_edge("worker", END)
    return g.compile()


GRAPH = build_graph()


async def run_task(task: str, role: str = "auto") -> str:
    """Run the supervisor graph end-to-end and return the worker's result."""
    out = await GRAPH.ainvoke({"task": task, "role": role})
    return out["result"]
