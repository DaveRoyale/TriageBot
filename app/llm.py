from typing import List, Dict
from app.config import (
    LLM_PROVIDER,
    ANTHROPIC_API_KEY, ANTHROPIC_MODEL,
    GEMINI_API_KEY, GEMINI_MODEL,
    OLLAMA_BASE_URL, OLLAMA_MODEL,
)


async def chat(messages: List[Dict], system: str) -> str:
    if LLM_PROVIDER == "anthropic":
        return await _anthropic_chat(messages, system)
    if LLM_PROVIDER == "gemini":
        return await _gemini_chat(messages, system)
    if LLM_PROVIDER == "ollama":
        return await _ollama_chat(messages, system)
    raise ValueError(f"Unknown LLM_PROVIDER: {LLM_PROVIDER!r}")


async def _anthropic_chat(messages: List[Dict], system: str) -> str:
    import anthropic
    client = anthropic.AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
    response = await client.messages.create(
        model=ANTHROPIC_MODEL,
        max_tokens=1024,
        system=system,
        messages=messages,
    )
    return response.content[0].text


async def _gemini_chat(messages: List[Dict], system: str) -> str:
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=GEMINI_API_KEY)
    contents = []
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        contents.append(types.Content(role=role, parts=[types.Part(text=msg["content"])]))

    response = await client.aio.models.generate_content(
        model=GEMINI_MODEL,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=system,
            max_output_tokens=1024,
        ),
    )
    return response.text


async def _ollama_chat(messages: List[Dict], system: str) -> str:
    import httpx
    ollama_messages = [{"role": "system", "content": system}] + messages
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_BASE_URL}/api/chat",
            json={"model": OLLAMA_MODEL, "messages": ollama_messages, "stream": False},
            timeout=120.0,
        )
        response.raise_for_status()
        return response.json()["message"]["content"]
