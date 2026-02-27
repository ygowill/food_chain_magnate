import json

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Match, MatchParticipant, MatchReplay


async def _create_user(client: AsyncClient) -> dict:
    import random
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-{random.randint(0,99999)}"})
    return resp.json()


async def _seed_match(db: AsyncSession, user_id: str, score_json: str | None = None) -> str:
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
async def test_get_replay_forbidden(client: AsyncClient, db_session: AsyncSession):
    user1 = await _create_user(client)
    user2 = await _create_user(client)
    mid = await _seed_match(db_session, user1["user_id"])
    resp = await client.get(f"/v1/matches/{mid}/replay", params={"session_id": user2["session_id"]})
    assert resp.status_code == 403
