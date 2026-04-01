import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import GameServer, Room, RoomMember, RoomTombstone, Match, MatchParticipant, MatchReplay

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
async def test_heartbeat_updates_room_ws_url(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    code = create.json()["room_code"]

    hb = await client.post("/internal/game_servers/heartbeat", json={
        "game_server_id": "gs-ws-1",
        "ws_url": "wss://ws.example.test",
        "room_codes": [code],
    }, headers=INTERNAL_HEADERS)
    assert hb.status_code == 200

    room = (await db_session.execute(select(Room).where(Room.room_code == code))).scalar_one()
    assert room.ws_url == "wss://ws.example.test"


@pytest.mark.asyncio
async def test_list_active_rooms_for_server(client: AsyncClient):
    user = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    code = create.json()["room_code"]

    hb = await client.post("/internal/game_servers/heartbeat", json={
        "game_server_id": "gs-active-1",
        "ws_url": "ws://127.0.0.1:7000",
        "room_codes": [code],
    }, headers=INTERNAL_HEADERS)
    assert hb.status_code == 200

    resp = await client.get("/internal/game_servers/gs-active-1/rooms/active", headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    data = resp.json()["ok"]
    assert isinstance(data, list)
    assert any(item["room_code"] == code and item["status"] == "Lobby" for item in data)


@pytest.mark.asyncio
async def test_sync_room_directory_creates_room_and_members(client: AsyncClient, db_session: AsyncSession):
    payload = {
        "ws_url": "wss://single.example.test",
        "rooms": [
            {
                "room_code": "SYNC01",
                "owner_user_id": "u_host_sync",
                "status": "Lobby",
                "join_policy": "public",
                "config_json": "{\"desired_player_count\":2}",
                "members": [
                    {"user_id": "u_host_sync", "role": "host", "seat_index": 0},
                    {"user_id": "u_p2_sync", "role": "player", "seat_index": 1},
                ],
            }
        ],
    }
    resp = await client.post("/internal/game_servers/gs-sync-1/rooms/sync", json=payload, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    assert resp.json()["accepted_room_codes"] == ["SYNC01"]
    assert resp.json()["skipped_ended_room_codes"] == []

    room = (await db_session.execute(select(Room).where(Room.room_code == "SYNC01"))).scalar_one()
    assert room.game_server_id == "gs-sync-1"
    assert room.ws_url == "wss://single.example.test"
    assert room.owner_user_id == "u_host_sync"
    members = (await db_session.execute(
        select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.left_at.is_(None))
    )).scalars().all()
    assert len(members) == 2


@pytest.mark.asyncio
async def test_sync_room_directory_marks_missing_rooms_ended(client: AsyncClient, db_session: AsyncSession):
    initial = await client.post("/internal/game_servers/gs-sync-2/rooms/sync", json={
        "rooms": [
            {
                "room_code": "SYNC02",
                "owner_user_id": "u_host_sync",
                "status": "Lobby",
                "join_policy": "public",
                "config_json": "{}",
                "members": [{"user_id": "u_host_sync", "role": "host", "seat_index": 0}],
            }
        ],
    }, headers=INTERNAL_HEADERS)
    assert initial.status_code == 200

    second = await client.post("/internal/game_servers/gs-sync-2/rooms/sync", json={
        "rooms": [],
    }, headers=INTERNAL_HEADERS)
    assert second.status_code == 200

    room = (await db_session.execute(select(Room).where(Room.room_code == "SYNC02"))).scalar_one()
    assert room.status == "Ended"


@pytest.mark.asyncio
async def test_sync_room_directory_does_not_revive_ended_room(client: AsyncClient, db_session: AsyncSession):
    room = Room(
        room_code="SYNC03",
        owner_user_id="u_owner_sync3",
        game_server_id="gs-sync-3",
        status="Ended",
        join_policy="public",
        config_json="{}",
        ws_url="wss://old.example.test",
    )
    db_session.add(room)
    await db_session.commit()

    resp = await client.post("/internal/game_servers/gs-sync-3/rooms/sync", json={
        "ws_url": "wss://single.example.test",
        "rooms": [
            {
                "room_code": "SYNC03",
                "owner_user_id": "u_owner_sync3_new",
                "status": "Lobby",
                "join_policy": "public",
                "config_json": "{}",
                "members": [{"user_id": "u_owner_sync3_new", "role": "host", "seat_index": 0}],
            }
        ],
    }, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    assert resp.json()["accepted_room_codes"] == []
    assert resp.json()["skipped_ended_room_codes"] == ["SYNC03"]

    room_after = (await db_session.execute(select(Room).where(Room.room_code == "SYNC03"))).scalar_one()
    assert room_after.status == "Ended"
    assert room_after.owner_user_id == "u_owner_sync3"


@pytest.mark.asyncio
async def test_sync_room_directory_does_not_recreate_deleted_room(client: AsyncClient, db_session: AsyncSession):
    db_session.add(RoomTombstone(room_code="SYNC04"))
    await db_session.commit()

    resp = await client.post("/internal/game_servers/gs-sync-4/rooms/sync", json={
        "ws_url": "wss://single.example.test",
        "rooms": [
            {
                "room_code": "SYNC04",
                "owner_user_id": "u_owner_sync4",
                "status": "Lobby",
                "join_policy": "public",
                "config_json": "{}",
                "members": [{"user_id": "u_owner_sync4", "role": "host", "seat_index": 0}],
            }
        ],
    }, headers=INTERNAL_HEADERS)
    assert resp.status_code == 200
    assert resp.json()["accepted_room_codes"] == []
    assert resp.json()["skipped_ended_room_codes"] == ["SYNC04"]

    room_after = (await db_session.execute(select(Room).where(Room.room_code == "SYNC04"))).scalar_one_or_none()
    assert room_after is None


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
