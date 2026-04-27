import json
import re
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import List, Dict
import os

from app.llm import chat
from app.context import load_guidance
from app.prompts import SYSTEM_PROMPT, REPORT_INSTRUCTION

app = FastAPI()


class ChatRequest(BaseModel):
    messages: List[Dict]
    incident_types: List[str] = []


def build_system(incident_types: List[str]) -> str:
    guidance = load_guidance(incident_types)
    if not guidance:
        return SYSTEM_PROMPT
    return SYSTEM_PROMPT + "\n\n# INCIDENT-SPECIFIC GUIDANCE\n\n" + guidance


def parse_sidecar(text: str):
    """Strip the JSON sidecar from the LLM response and return clean text plus state."""
    match = re.search(r'\{[^{}]*"incident_types"\s*:\s*\[[^\]]*\][^{}]*\}', text)
    if not match:
        return text.strip(), [], False
    try:
        data = json.loads(match.group())
        clean = text[:match.start()].strip()
        return clean, data.get("incident_types", []), bool(data.get("ready_for_report", False))
    except (json.JSONDecodeError, ValueError):
        return text.strip(), [], False


@app.post("/api/chat")
async def chat_endpoint(req: ChatRequest):
    try:
        system = build_system(req.incident_types)
        raw = await chat(req.messages, system)
        reply, detected, ready = parse_sidecar(raw)
        merged_types = list(set(req.incident_types + detected))
        return {"reply": reply, "incident_types": merged_types, "ready_for_report": ready}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/report")
async def report_endpoint(req: ChatRequest):
    try:
        system = build_system(req.incident_types)
        messages = req.messages + [{"role": "user", "content": REPORT_INSTRUCTION}]
        raw = await chat(messages, system)
        report, _, _ = parse_sidecar(raw)
        return {"report": report}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
async def root():
    return FileResponse(os.path.join(os.path.dirname(__file__), "static", "index.html"))


app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")
