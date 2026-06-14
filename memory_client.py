"""
TAX AI - GreenNode Memory Client
Luu lich su hoi thoai nguoi dung qua GreenNode Memory REST API.
"""
import logging
import os
import time
import requests

logger = logging.getLogger(__name__)

# IAM token cache
_iam_token = ""
_iam_expiry = 0

def _get_iam_token() -> str:
    global _iam_token, _iam_expiry
    if _iam_token and time.time() < _iam_expiry - 60:
        return _iam_token
    cid  = os.getenv("GREENNODE_CLIENT_ID", "")
    csec = os.getenv("GREENNODE_CLIENT_SECRET", "")
    if not cid or not csec:
        return ""
    import base64
    b64 = base64.b64encode(f"{cid}:{csec}".encode()).decode()
    try:
        r = requests.post(
            "https://iam.api.vngcloud.vn/accounts-api/v2/auth/token",
            headers={"Authorization": f"Basic {b64}"},
            data="grant_type=client_credentials",
            timeout=10,
        )
        data = r.json()
        _iam_token = data.get("access_token", "")
        _iam_expiry = time.time() + data.get("expires_in", 3600)
        return _iam_token
    except Exception as e:
        logger.warning("IAM token failed: %s", e)
        return ""


def _headers() -> dict:
    tok = _get_iam_token()
    if not tok:
        return {}
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


def add_event(memory_id: str, actor_id: str, role: str, content: str) -> bool:
    """Luu 1 turn hoi thoai vao GreenNode Memory."""
    if not memory_id or not actor_id:
        return False
    url = f"https://agentbase.api.vngcloud.vn/memory/memories/{memory_id}/events"
    h = _headers()
    if not h:
        return False
    try:
        r = requests.post(url, headers=h, json={
            "actorId": actor_id,
            "messages": [{"role": role, "content": content}],
        }, timeout=8)
        return r.status_code in (200, 201)
    except Exception as e:
        logger.warning("Memory add_event failed: %s", e)
        return False


def get_history(memory_id: str, actor_id: str, limit: int = 10) -> list:
    """Lay lich su hoi thoai gan nhat cua user."""
    if not memory_id or not actor_id:
        return []
    url = f"https://agentbase.api.vngcloud.vn/memory/memories/{memory_id}/events"
    h = _headers()
    if not h:
        return []
    try:
        r = requests.get(url, headers=h, params={
            "actorId": actor_id, "page": 1, "size": limit,
        }, timeout=8)
        if r.status_code == 200:
            data = r.json()
            events = data.get("listData", data) if isinstance(data, dict) else data
            return events[-limit:] if isinstance(events, list) else []
    except Exception as e:
        logger.warning("Memory get_history failed: %s", e)
    return []


# Simple local fallback (in-process, lost on restart)
_local: dict = {}

def save_local(actor_id: str, role: str, content: str, max_turns: int = 20):
    hist = _local.setdefault(actor_id, [])
    hist.append({"role": role, "content": content})
    if len(hist) > max_turns:
        _local[actor_id] = hist[-max_turns:]

def get_local(actor_id: str) -> list:
    return _local.get(actor_id, [])
