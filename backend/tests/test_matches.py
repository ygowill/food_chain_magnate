import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Match, MatchParticipant, MatchReplay


async def _create_user(client: AsyncClient) -> dict:
    import random
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-{random.randint(0,99999)}"})
    return resp.json()


async def _seed_match(db: AsyncSession, user_id: str) -> str:
    m = Match(room_code="ABCD", status="completed", player_count=2)
    db.add(m)
    await db.flush()
    db.add(MatchParticipant(match_id=m.match_id, user_id=user_id, role="player", seat_index=0))
    db.add(MatchReplay(match_id=m.match_id, storage_uri="file:///replays/test.bin", checksum="abc123", size_bytes=1024))
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
async def test_get_replay_forbidden(client: AsyncClient, db_session: AsyncSession):
    user1 = await _create_user(client)
    user2 = await _create_user(client)
    mid = await _seed_match(db_session, user1["user_id"])
    resp = await client.get(f"/v1/matches/{mid}/replay", params={"session_id": user2["session_id"]})
    assert resp.status_code == 403
