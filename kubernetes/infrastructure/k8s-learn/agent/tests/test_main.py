# infrastructure/k8s-learn/agent/tests/test_main.py
import pytest


def test_build_messages_includes_question():
    from main import build_messages
    msgs = build_messages("why is my pod pending", "Namespace: learn-test\nPod: hello (Pending, 0 restarts)")
    user_msg = msgs[1]["content"]
    assert "why is my pod pending" in user_msg
    assert "CLUSTER STATE" in user_msg
    assert "Namespace: learn-test" in user_msg


def test_build_messages_without_cluster_state():
    from main import build_messages
    msgs = build_messages("what is a pod", "")
    user_msg = msgs[1]["content"]
    assert "what is a pod" in user_msg
    assert "CLUSTER STATE" not in user_msg


def test_build_messages_includes_task_definitions():
    from main import build_messages
    msgs = build_messages("what is a deployment", "")
    system_msg = msgs[0]["content"]
    assert "Task 2" in system_msg
    assert "kubectl create deployment" in system_msg


from unittest.mock import patch, AsyncMock
from httpx import AsyncClient, ASGITransport


@pytest.mark.asyncio
async def test_health():
    from main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_ask_too_short():
    from main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.post("/ask", json={"question": "hi", "namespace": "learn-test"})
    assert resp.status_code == 200
    assert "10 characters" in resp.json()["answer"]


@pytest.mark.asyncio
async def test_ask_too_long():
    from main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.post("/ask", json={"question": "x" * 501, "namespace": "learn-test"})
    assert resp.status_code == 200
    assert "500 characters" in resp.json()["answer"]


@pytest.mark.asyncio
async def test_ask_returns_answer():
    from main import app
    with patch("main.get_namespace_state", new_callable=AsyncMock, return_value="Namespace: learn-test\nPod: hello (Running, 0 restarts)"):
        with patch("main.call_ollama", new_callable=AsyncMock, return_value="A pod is the smallest deployable unit."):
            async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
                resp = await ac.post("/ask", json={"question": "what is a kubernetes pod", "namespace": "learn-test"})
    assert resp.status_code == 200
    assert resp.json()["answer"] == "A pod is the smallest deployable unit."


@pytest.mark.asyncio
async def test_ask_ollama_error_returns_fallback():
    from main import app
    with patch("main.get_namespace_state", new_callable=AsyncMock, return_value=""):
        with patch("main.call_ollama", new_callable=AsyncMock, return_value="The help assistant is busy right now. Try again in a moment."):
            async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
                resp = await ac.post("/ask", json={"question": "what is a kubernetes pod", "namespace": "learn-test"})
    assert resp.status_code == 200
    assert "busy" in resp.json()["answer"]
