import os
from typing import List

GUIDANCE_DIR = os.path.join(os.path.dirname(__file__), "..", "guidance")

KNOWN_TYPES = {
    "privacy_breach": "privacy_breach.md",
    "banking_code": "banking_code.md",
}

def load_guidance(incident_types: List[str]) -> str:
    sections = []
    for t in incident_types:
        filename = KNOWN_TYPES.get(t)
        if not filename:
            continue
        path = os.path.join(GUIDANCE_DIR, filename)
        if os.path.exists(path):
            with open(path) as f:
                sections.append(f.read().strip())
    return "\n\n---\n\n".join(sections)
