from __future__ import annotations

from pathlib import Path

from app.config import settings

LOCAL_REPLAY_URI_PREFIX = "local_file://"
LOCAL_ARTIFACT_URI_PREFIX = "local_artifact://"


def build_local_replay_uri(filename: str) -> str:
    return f"{LOCAL_REPLAY_URI_PREFIX}{filename}"


def build_local_artifact_uri(relative_path: str) -> str:
    return f"{LOCAL_ARTIFACT_URI_PREFIX}{relative_path}"


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


def parse_local_artifact_relative_path(storage_uri: str | None) -> str | None:
    if not storage_uri:
        return None
    raw = str(storage_uri)
    if not raw.startswith(LOCAL_ARTIFACT_URI_PREFIX):
        return None
    relative_path = raw[len(LOCAL_ARTIFACT_URI_PREFIX):].strip()
    if not relative_path:
        return None
    return _normalize_artifact_relative_path(relative_path)


def get_local_replay_path(filename: str) -> Path:
    base_dir = Path(str(settings.replay_storage_dir)).expanduser()
    return base_dir / filename


def get_local_artifact_path(relative_path: str) -> Path:
    normalized = _normalize_artifact_relative_path(relative_path)
    if normalized is None:
        raise ValueError("invalid artifact path")
    base_dir = Path(str(settings.replay_storage_dir)).expanduser()
    return base_dir / "artifacts" / normalized


def save_local_replay_archive(match_id: str, replay_archive_json: str) -> str:
    filename = f"{match_id}.json"
    path = get_local_replay_path(filename)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(replay_archive_json, encoding="utf-8")
    return build_local_replay_uri(filename)


def save_local_match_artifact(relative_path: str, data: bytes) -> str:
    normalized = _normalize_artifact_relative_path(relative_path)
    if normalized is None:
        raise ValueError("invalid artifact path")
    path = get_local_artifact_path(normalized)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return build_local_artifact_uri(normalized)


def _normalize_artifact_relative_path(relative_path: str) -> str | None:
    raw = str(relative_path).replace("\\", "/").strip().lstrip("/")
    if not raw:
        return None
    parts = [part for part in raw.split("/") if part]
    if not parts:
        return None
    for part in parts:
        if part in (".", ".."):
            return None
        if Path(part).name != part:
            return None
    return "/".join(parts)
