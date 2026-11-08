"""Append a Pi `session_info` entry so a demo session shows a readable title.

usage: python name_session.py <session.jsonl> "<name>"
"""
import json
import secrets
import sys
from datetime import datetime, timezone

path, name = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    lines = [json.loads(l) for l in f if l.strip()]
last = next((e["id"] for e in reversed(lines) if "id" in e and e.get("type") != "session"), None)
entry = {
    "type": "session_info",
    "id": secrets.token_hex(4),
    "parentId": last,
    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "name": name,
}
with open(path, "a", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(entry) + "\n")
print("named", path, "->", name)
