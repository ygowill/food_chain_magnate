from __future__ import annotations

from pathlib import Path

from app.config import settings

LOCAL_REPLAY_URI_PREFIX = "local_file://"


def build_local_replay_uri(filename: str) -> str:
    return f"{LOCAL_REPLAY_URI_PREFIX}{filename}"


def parse_local_replay_filename(storage_uri: str | None) -> str | None:
    if not storage_uri:
        return None
    raw = str(storage_uri)
    if not raw.startswith(LOCAL_REPLAY_URI_PREFIX):
        return None
    filename = raw[len(LOCAL_REPLAY_URI_PREFIX):].strip()
    if not filename:
        return None
    # Keep only base name to avoid path traversal.
    safe = Path(filename).name
    if safe != filename:
        return None
    return safe


def get_local_replay_path(filename: str) -> Path:
    base_dir = Path(str(settings.replay_storage_dir)).expanduser()
    return base_dir / filename


def save_local_replay_archive(match_id: str, replay_archive_json: str) -> str:
    filename = f"{match_id}.json"
    path = get_local_replay_path(filename)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(replay_archive_json, encoding="utf-8")
    return build_local_replay_uri(filename)
