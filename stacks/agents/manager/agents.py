"""Role definitions and the shared ChatOllama client.

All inference is offloaded to the Ollama instance on llm-lxc. The model is
pinned and kept resident (keep_alive=-1) so the single RTX 3060 never thrashes.
"""
import os

from langchain_ollama import ChatOllama

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://192.168.50.32:11434")
MODEL = os.environ.get("AGENTS_MODEL", "qwen2.5:7b-instruct")

# Roles (MVP, YAGNI): supervisor + a generic worker.
ROLES = {
    "worker": (
        "You are a capable local worker agent. You complete the task you are "
        "given directly, concisely, and correctly. You do not ask follow-up "
        "questions; you make reasonable assumptions and produce a final answer."
    ),
}


def make_llm() -> ChatOllama:
    """Build the shared ChatOllama client pointed at llm-lxc Ollama."""
    return ChatOllama(
        base_url=OLLAMA_BASE_URL,
        model=MODEL,
        keep_alive=-1,
        temperature=0.2,
    )


# Single shared client instance.
llm = make_llm()
