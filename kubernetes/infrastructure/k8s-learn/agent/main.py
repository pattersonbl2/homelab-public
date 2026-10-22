# infrastructure/k8s-learn/agent/main.py
from fastapi import FastAPI
from pydantic import BaseModel
import httpx
from tasks import SYSTEM_PROMPT
from k8s_client import get_namespace_state

app = FastAPI()

OLLAMA_URL = "http://192.168.50.68:11434/api/chat"
MODEL = "gemma4:e4b"


class AskRequest(BaseModel):
    question: str
    namespace: str


class AskResponse(BaseModel):
    answer: str


@app.get("/healthz")
async def health():
    return {"status": "ok"}


@app.post("/ask", response_model=AskResponse)
async def ask(req: AskRequest):
    if len(req.question) < 10:
        return AskResponse(answer="Please ask a question with at least 10 characters.")
    if len(req.question) > 500:
        return AskResponse(answer="Please keep your question under 500 characters.")

    cluster_state = await get_namespace_state(req.namespace)
    messages = build_messages(req.question, cluster_state)
    answer = await call_ollama(messages)
    return AskResponse(answer=answer)


def build_messages(question: str, cluster_state: str) -> list:
    user_content = question
    if cluster_state:
        user_content = f"[CLUSTER STATE]\n{cluster_state}\n\n[QUESTION]\n{question}"
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_content},
    ]


async def call_ollama(messages: list) -> str:
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(OLLAMA_URL, json={
                "model": MODEL,
                "messages": messages,
                "stream": False,
                "options": {"num_predict": 300}
            })
            resp.raise_for_status()
            return resp.json()["message"]["content"]
    except Exception:
        return "The help assistant is busy right now. Try again in a moment."
