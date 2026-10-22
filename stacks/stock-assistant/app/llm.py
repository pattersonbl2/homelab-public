import os
import httpx

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b")


async def query_ollama(prompt: str, model: str | None = None) -> str:
    """Send a prompt to Ollama and get a response."""
    model = model or OLLAMA_MODEL
    
    url = f"{OLLAMA_BASE_URL}/api/generate"
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.7,
            "num_predict": 1024,
        }
    }
    
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, json=payload, timeout=120)
            if resp.status_code != 200:
                return f"Error: Ollama returned status {resp.status_code}"
            
            data = resp.json()
            return data.get("response", "No response from model")
    
    except httpx.TimeoutException:
        return "Error: Request to Ollama timed out. The model may be loading or busy."
    except httpx.ConnectError:
        return "Error: Could not connect to Ollama. Make sure it's running."
    except Exception as e:
        return f"Error querying Ollama: {str(e)}"


async def list_models() -> list[str]:
    """List available Ollama models."""
    url = f"{OLLAMA_BASE_URL}/api/tags"
    
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, timeout=10)
            if resp.status_code != 200:
                return []
            
            data = resp.json()
            return [m["name"] for m in data.get("models", [])]
    except:
        return []
