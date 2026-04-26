from __future__ import annotations

import json
from typing import Optional

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Match, MatchArtifact, MatchParticipant, MatchReplay


async def _create_user(client: AsyncClient) -> dict:
    import random
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-{random.randint(0,99999)}"})
    return resp.json()


async def _seed_match(db: AsyncSession, user_id: str, score_json: Optional[str] = None) -> str:
    m = Match(room_code="ABCD", status="completed", player_count=2)
    db.add(m)
    await db.flush()
    db.add(MatchParticipant(
        match_id=m.match_id,
        user_id=user_id,
        role="player",
        seat_index=0,
        score_json=score_json,
    ))
    db.add(MatchReplay(match_id=m.match_id, storage_uri="file:///replays/test.bin", checksum="abc123", size_bytes=1024))
    await db.commit()
    return m.match_id


async def _seed_local_replay_match(db: AsyncSession, user_id: str, replay_storage_dir: str) -> str:
    m = Match(room_code="LOCAL1", status="completed", player_count=2)
    db.add(m)
    await db.flush()
    db.add(MatchParticipant(
        match_id=m.match_id,
        user_id=user_id,
        role="player",
        seat_index=0,
    ))
    replay_file = f"{replay_storage_dir}/{m.match_id}.json"
    with open(replay_file, "w", encoding="utf-8") as f:
        f.write('{"schema_version":3,"commands":[]}')
    db.add(MatchReplay(match_id=m.match_id, storage_uri=f"local_file://{m.match_id}.json", checksum="abc123", size_bytes=34))
    await db.commit()
    return m.match_id


async def _seed_local_replay_match_with_archive(
    db: AsyncSession,
    user_id: str,
    replay_storage_dir: str,
    score_json: Optional[str],
    replay_archive_json: str,
) -> str:
    m = Match(room_code="LOCAL2", status="completed", player_count=2)
    db.add(m)
    await db.flush()
    db.add(MatchParticipant(
        match_id=m.match_id,
        user_id=user_id,
        role="player",
        seat_index=0,
        score_json=score_json,
    ))
    replay_file = f"{replay_storage_dir}/{m.match_id}.json"
    with open(replay_file, "w", encoding="utf-8") as f:
        f.write(replay_archive_json)
    db.add(MatchReplay(match_id=m.match_id, storage_uri=f"local_file://{m.match_id}.json", checksum="abc123", size_bytes=len(replay_archive_json)))
    await db.commit()
    return m.match_id


async def _seed_match_with_local_artifacts(db: AsyncSession, user_id: str, replay_storage_dir: str) -> tuple[str, str]:
    m = Match(room_code="ARTDET", status="completed", player_count=1)
    db.add(m)
    await db.flush()
    db.add(MatchParticipant(
        match_id=m.match_id,
        user_id=user_id,
        role="player",
        seat_index=0,
    ))
    autosave_path = f"{replay_storage_dir}/artifacts/rooms/ARTDET/latest_autosave.json"
    snapshot_path = f"{replay_storage_dir}/artifacts/rooms/ARTDET/map_snapshots/round_0002_round_end.png"
    import os
    os.makedirs(os.path.dirname(snapshot_path), exist_ok=True)
    with open(autosave_path, "w", encoding="utf-8") as f:
        f.write('{"round":2}')
    png_bytes = b"\x89PNG\r\n\x1a\nartifact-test"
    with open(snapshot_path, "wb") as f:
        f.write(png_bytes)
    db.add(MatchArtifact(
        match_id=m.match_id,
        room_code="ARTDET",
        artifact_type="autosave_latest",
        snapshot_kind="round_end",
        round_number=2,
        state_hash="hash-2",
        storage_uri="local_artifact://rooms/ARTDET/latest_autosave.json",
        mime_type="application/json",
        checksum="save-checksum",
        size_bytes=len('{"round":2}'),
    ))
    snapshot = MatchArtifact(
        match_id=m.match_id,
        room_code="ARTDET",
        artifact_type="map_snapshot",
        snapshot_kind="round_end",
        round_number=2,
        state_hash="hash-2",
        storage_uri="local_artifact://rooms/ARTDET/map_snapshots/round_0002_round_end.png",
        mime_type="image/png",
        checksum="snapshot-checksum",
        size_bytes=len(png_bytes),
    )
    db.add(snapshot)
    await db.commit()
    return m.match_id, snapshot.id


@pytest.mark.asyncio
async def test_list_matches_empty(client: AsyncClient):
    user = await _create_user(client)
    resp = await client.get("/v1/matches", params={"session_id": user["session_id"]})
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_list_matches(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    await _seed_match(db_session, user["user_id"])
    resp = await client.get("/v1/matches", params={"session_id": user["session_id"]})
    assert resp.status_code == 200
    assert len(resp.json()) == 1
    assert resp.json()[0]["room_code"] == "ABCD"


@pytest.mark.asyncio
async def test_get_match_detail(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    mid = await _seed_match(db_session, user["user_id"])
    resp = await client.get(f"/v1/matches/{mid}", params={"session_id": user["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["match_id"] == mid
    assert resp.json()["status"] == "completed"


@pytest.mark.asyncio
async def test_get_match_detail_includes_server_artifacts(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user = await _create_user(client)
        mid, snapshot_id = await _seed_match_with_local_artifacts(db_session, user["user_id"], str(tmp_path))
        resp = await client.get(f"/v1/matches/{mid}", params={"session_id": user["session_id"]})
        assert resp.status_code == 200
        body = resp.json()
        assert body["latest_save_round"] == 2
        assert body["map_snapshot_count"] == 1
        assert body["latest_save"]["storage_uri"] == f"/v1/matches/{mid}/autosave/download"
        assert body["latest_save"]["state_hash"] == "hash-2"
        assert body["map_snapshots"][0]["id"] == snapshot_id
        assert body["map_snapshots"][0]["download_url"] == f"/v1/matches/{mid}/map-snapshots/{snapshot_id}/download"
    finally:
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_get_match_detail_stats(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    mid = await _seed_match(
        db_session,
        user["user_id"],
        score_json=json.dumps({
            "name": "测试昵称",
            "restaurant_logo_id": 4,
            "cash": 210,
            "employees": ["ceo", "burger_cook"],
            "reserve_employees": ["trainer"],
            "busy_marketers": ["marketing_trainee", "brand_manager"],
            "restaurants": [{}, {}],
            "inventory": {"burger": 2},
            "stats": {
                "marketing_actions": 7,
                "marketing_by_type": {"billboard": 3, "mailbox": 2},
                "recruit_count": 5,
                "train_count": 2,
                "house_built": 4,
                "restaurant_built": 2,
                "production_counts": {"burger": 11, "pizza": 3, "cola": 1},
                "sales_counts": {"lemonade": 4, "coke": 3, "soda": 2, "beer": 1},
            },
        }),
    )
    resp = await client.get(f"/v1/matches/{mid}", params={"session_id": user["session_id"]})
    assert resp.status_code == 200
    body = resp.json()
    participant = body["participants"][0]
    assert participant["display_name"] == "测试昵称"
    assert participant["restaurant_logo_id"] == 4
    assert participant["restaurant_logo_key"] == "restaurant_logo_xango_blues_bar"
    score = body["participants"][0]["score"]
    assert score["cash"] == 210
    assert score["restaurants"] == 2
    assert score["marketing_campaigns"] == 2
    assert score["stats"]["marketing_actions"] == 7
    assert score["stats"]["billboard_placements"] == 3
    assert score["stats"]["marketing_by_type"] == {"billboard": 3, "mailbox": 2}
    assert score["stats"]["hired_employees"] == 5
    assert score["stats"]["trained_employees"] == 2
    assert score["stats"]["metrics"]["house_built"] == 4
    assert score["stats"]["metrics"]["restaurant_built"] == 2
    assert score["stats"]["produced"] == {"burger": 11, "pizza": 3, "soda": 1}
    assert score["stats"]["sold"] == {"lemonade": 4, "soda": 5, "beer": 1}


@pytest.mark.asyncio
async def test_get_match_detail_negative_logo_id_stays_unset(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    mid = await _seed_match(
        db_session,
        user["user_id"],
        score_json=json.dumps({
            "name": "未选 Logo",
            "restaurant_logo_id": -1,
        }),
    )
    resp = await client.get(f"/v1/matches/{mid}", params={"session_id": user["session_id"]})
    assert resp.status_code == 200
    participant = resp.json()["participants"][0]
    assert participant["restaurant_logo_id"] is None
    assert participant["restaurant_logo_key"] is None


@pytest.mark.asyncio
async def test_matches_prefer_local_replay_logo_over_legacy_score_json(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user = await _create_user(client)
        mid = await _seed_local_replay_match_with_archive(
            db_session,
            user["user_id"],
            str(tmp_path),
            score_json=json.dumps({
                "name": "旧记录玩家",
                "restaurant_logo_id": -1,
            }),
            replay_archive_json=json.dumps({
                "initial_state": {
                    "players": [
                        {"restaurant_logo_id": 4},
                    ],
                },
                "commands": [],
            }),
        )

        list_resp = await client.get("/v1/matches", params={"session_id": user["session_id"]})
        assert list_resp.status_code == 200
        list_match = next(item for item in list_resp.json() if item["match_id"] == mid)
        list_participant = list_match["participants"][0]
        assert list_participant["restaurant_logo_id"] == 4
        assert list_participant["restaurant_logo_key"] == "restaurant_logo_xango_blues_bar"

        detail_resp = await client.get(f"/v1/matches/{mid}", params={"session_id": user["session_id"]})
        assert detail_resp.status_code == 200
        detail_participant = detail_resp.json()["participants"][0]
        assert detail_participant["restaurant_logo_id"] == 4
        assert detail_participant["restaurant_logo_key"] == "restaurant_logo_xango_blues_bar"
    finally:
        settings.replay_storage_dir = old_replay_storage_dir

@pytest.mark.asyncio
async def test_get_match_forbidden(client: AsyncClient, db_session: AsyncSession):
    user1 = await _create_user(client)
    user2 = await _create_user(client)
    mid = await _seed_match(db_session, user1["user_id"])
    resp = await client.get(f"/v1/matches/{mid}", params={"session_id": user2["session_id"]})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_get_replay(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    mid = await _seed_match(db_session, user["user_id"])
    resp = await client.get(f"/v1/matches/{mid}/replay", params={"session_id": user["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["storage_uri"] == "file:///replays/test.bin"


@pytest.mark.asyncio
async def test_get_replay_local_storage_uri(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user = await _create_user(client)
        mid = await _seed_local_replay_match(db_session, user["user_id"], str(tmp_path))
        resp = await client.get(f"/v1/matches/{mid}/replay", params={"session_id": user["session_id"]})
        assert resp.status_code == 200
        assert resp.json()["storage_uri"] == f"/v1/matches/{mid}/replay/download"
    finally:
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_download_replay_local(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user = await _create_user(client)
        mid = await _seed_local_replay_match(db_session, user["user_id"], str(tmp_path))
        resp = await client.get(f"/v1/matches/{mid}/replay/download", params={"session_id": user["session_id"]})
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("application/json")
        assert '"schema_version":3' in resp.text
    finally:
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_download_local_match_artifacts(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user = await _create_user(client)
        mid, snapshot_id = await _seed_match_with_local_artifacts(db_session, user["user_id"], str(tmp_path))

        autosave = await client.get(f"/v1/matches/{mid}/autosave/download", params={"session_id": user["session_id"]})
        assert autosave.status_code == 200
        assert autosave.headers["content-type"].startswith("application/json")
        assert autosave.text == '{"round":2}'

        snapshot = await client.get(
            f"/v1/matches/{mid}/map-snapshots/{snapshot_id}/download",
            params={"session_id": user["session_id"]},
        )
        assert snapshot.status_code == 200
        assert snapshot.headers["content-type"].startswith("image/png")
        assert snapshot.content == b"\x89PNG\r\n\x1a\nartifact-test"
    finally:
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_download_match_artifact_forbidden(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user1 = await _create_user(client)
        user2 = await _create_user(client)
        mid, _snapshot_id = await _seed_match_with_local_artifacts(db_session, user1["user_id"], str(tmp_path))
        resp = await client.get(f"/v1/matches/{mid}/autosave/download", params={"session_id": user2["session_id"]})
        assert resp.status_code == 403
    finally:
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_get_replay_forbidden(client: AsyncClient, db_session: AsyncSession):
    user1 = await _create_user(client)
    user2 = await _create_user(client)
    mid = await _seed_match(db_session, user1["user_id"])
    resp = await client.get(f"/v1/matches/{mid}/replay", params={"session_id": user2["session_id"]})
    assert resp.status_code == 403
