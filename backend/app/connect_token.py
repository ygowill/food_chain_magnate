import base64
import hashlib
import hmac
import json
import time

from app.config import settings


def create_token(payload: dict) -> str:
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    b64 = base64.urlsafe_b64encode(raw).decode()
    sig = hmac.new(settings.hmac_secret.encode(), raw, hashlib.sha256).hexdigest()
    return f"{b64}.{sig}"


def verify_token(token: str) -> dict | None:
    try:
        b64, sig = token.rsplit(".", 1)
    except ValueError:
        return None
    raw = base64.urlsafe_b64decode(b64)
    expected = hmac.new(settings.hmac_secret.encode(), raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected):
        return None
    payload = json.loads(raw)
    if payload.get("exp", 0) < time.time():
        return None
    return payload


def issue_connect_token(
    user_id: str, room_code: str, role: str,
    display_name: str = "", ttl: int = 60,
    seat_index: int | None = None,
    config_json: str | None = None,
) -> str:
    payload = {
        "user_id": user_id,
        "room_code": room_code,
        "role": role,
        "display_name": display_name,
        "exp": int(time.time()) + ttl,
    }
    if seat_index is not None:
        payload["seat_index"] = int(seat_index)
    if config_json is not None:
        payload["config_json"] = config_json
    return create_token(payload)
