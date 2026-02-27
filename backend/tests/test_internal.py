import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import GameServer, Room, Match, MatchParticipant, MatchReplay

INTERNAL_HEADERS = {"X-Internal-Secret": settings.internal_api_secret}


async def _create_user(client: AsyncClient) -> dict:
    import random
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-{random.randint(0,99999)}"})
    return resp.json()


@pytest.mark.asyncio
async def test_internal_requires_secret(client: AsyncClient):
    resp = await client.post("/internal/game_servers/heartbeat", json={"game_server_id": "gs-auth"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_heartbeat_creates_server(client: AsyncClient, db_session: AsyncSession):
    resp = await client.post("/internal/game_servers/heartbeat", json={
        "game_server_id": "gs-1",
    }, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    gs = (await db_session.execute(select(GameServer).where(GameServer.game_server_id == "gs-1"))).scalar_one()
    assert gs.status == "healthy"


@pytest.mark.asyncio
async def test_heartbeat_updates_existing(client: AsyncClient, db_session: AsyncSession):
    await client.post("/internal/game_servers/heartbeat", json={"game_server_id": "gs-2"}, headers=INTERNAL_HEADERS)
    resp = await client.post("/internal/game_servers/heartbeat", json={"game_server_id": "gs-2"}, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_heartbeat_links_rooms(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    code = create.json()["room_code"]

    await client.post("/internal/game_servers/heartbeat", json={
        "game_server_id": "gs-3", "room_codes": [code],
    }, headers=INTERNAL_HEADERS)
    room = (await db_session.execute(select(Room).where(Room.room_code == code))).scalar_one()
    assert room.game_server_id == "gs-3"


@pytest.mark.asyncio
async def test_finalize_creates_match(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    resp = await client.post("/internal/matches/finalize", json={
        "room_code": "TEST01",
        "status": "completed",
        "player_count": 2,
        "participants": [
            {"user_id": user["user_id"], "role": "player", "seat_index": 0, "result": "win"},
        ],
        "replay_uri": "s3://bucket/replay.bin",
        "replay_checksum": "sha256abc",
        "replay_size_bytes": 2048,
    }, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    mid = resp.json()["match_id"]

    match = (await db_session.execute(select(Match).where(Match.match_id == mid))).scalar_one()
    assert match.status == "completed"
    assert match.player_count == 2

    part = (await db_session.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == mid)
    )).scalar_one()
    assert part.result == "win"

    replay = (await db_session.execute(
        select(MatchReplay).where(MatchReplay.match_id == mid)
    )).scalar_one()
    assert replay.storage_uri == "s3://bucket/replay.bin"


@pytest.mark.asyncio
async def test_finalize_without_replay(client: AsyncClient, db_session: AsyncSession):
    resp = await client.post("/internal/matches/finalize", json={
        "status": "abandoned",
        "player_count": 1,
    }, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    mid = resp.json()["match_id"]
    replay = (await db_session.execute(
        select(MatchReplay).where(MatchReplay.match_id == mid)
    )).scalar_one_or_none()
    assert replay is None


@pytest.mark.asyncio
async def test_finalize_with_replay_archive_json(client: AsyncClient, db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        user = await _create_user(client)
        replay_archive_json = '{"schema_version":3,"commands":[]}'
        resp = await client.post("/internal/matches/finalize", json={
            "room_code": "TEST02",
            "status": "completed",
            "player_count": 1,
            "participants": [
                {"user_id": user["user_id"], "role": "player", "seat_index": 0, "result": "win"},
            ],
            "replay_archive_json": replay_archive_json,
        }, headers=INTERNAL_HEADERS)
        assert resp.status_code == 200
        mid = resp.json()["match_id"]

        replay = (await db_session.execute(
            select(MatchReplay).where(MatchReplay.match_id == mid)
        )).scalar_one()
        assert replay.storage_uri == f"local_file://{mid}.json"
        replay_file = tmp_path / f"{mid}.json"
        assert replay_file.read_text(encoding="utf-8") == replay_archive_json
    finally:
        settings.replay_storage_dir = old_replay_storage_dir
