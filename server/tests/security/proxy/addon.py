"""
D2's mitmproxy addon: writes every request/response pair and every WebSocket message that goes
through the proxy to a JSON-lines file ($D2_FLOWLOG), one object per line, for
server/tests/security/proxy.live.test.ts to scan. Reverse-proxy mode only, localhost only: the
proxy listens on 127.0.0.1 and forwards to the local server or the local Supabase, over plain
HTTP, so no certificate is installed anywhere.

Run (the test starts it for you):
  D2_LABEL=api D2_FLOWLOG=/tmp/flows.jsonl mitmdump --mode reverse:http://127.0.0.1:3122 \
      --listen-host 127.0.0.1 --listen-port 3123 -s addon.py
"""
import hashlib
import json
import os

LOG = os.environ["D2_FLOWLOG"]
LABEL = os.environ.get("D2_LABEL", "proxy")
TEXT_TYPES = ("json", "text", "xml", "javascript", "x-www-form-urlencoded", "html")


def describe(content, headers):
    """Text bodies in full; binary ones as a short fingerprint (images can be large)."""
    content = content or b""
    ctype = headers.get("content-type", "").lower()
    if not content:
        return {"text": ""}
    if any(t in ctype for t in TEXT_TYPES) or not ctype:
        try:
            return {"text": content.decode("utf-8")}
        except UnicodeDecodeError:
            pass
    return {
        "binary": True,
        "type": ctype,
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
        "magic": content[:4].hex(),
    }


def write(obj):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj) + "\n")


def response(flow):
    write(
        {
            "kind": "http",
            "label": LABEL,
            "ts": flow.request.timestamp_start,
            "method": flow.request.method,
            "path": flow.request.path,
            "req": {"headers": dict(flow.request.headers), **describe(flow.request.content, flow.request.headers)},
            "res": {
                "status": flow.response.status_code,
                "headers": dict(flow.response.headers),
                "set_cookie": flow.response.headers.get_all("set-cookie"),
                **describe(flow.response.content, flow.response.headers),
            },
        }
    )


def websocket_message(flow):
    message = flow.websocket.messages[-1]
    write(
        {
            "kind": "ws",
            "label": LABEL,
            "ts": message.timestamp,
            "path": flow.request.path.split("?")[0],
            "from_client": message.from_client,
            "text": message.text if message.is_text else "[binary %d bytes]" % len(message.content),
        }
    )
