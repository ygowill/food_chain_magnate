from __future__ import annotations

import json
from typing import Optional


class RoomConfigParseError(ValueError):
    pass


def parse_room_config_json(config_json: Optional[str], source: str = "config_json") -> dict:
    raw = str(config_json or "").strip()
    if raw == "":
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RoomConfigParseError(f"{source} must be valid JSON object: {exc.msg}") from exc
    if not isinstance(parsed, dict):
        raise RoomConfigParseError(f"{source} must be JSON object")
    return dict(parsed)
