from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.connect_token import verify_token
from app.models import GameServer, Room, RoomMember

INTERNAL_HEADERS = {"X-Internal-Secret": "dev-internal-secret-change-in-production"}


async def _create_user(client: AsyncClient) -> dict:
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-{id(client)}-{pytest.importorskip('random').randint(0,99999)}"})
    return resp.json()


async def _heartbeat_room(client: AsyncClient, game_server_id: str, room_code: str, ws_url: str | None = None) -> None:
    payload: dict = {
        "game_server_id": game_server_id,
        "room_codes": [room_code],
    }
    if ws_url is not None:
        payload["ws_url"] = ws_url
    resp = await client.post("/internal/game_servers/heartbeat", headers=INTERNAL_HEADERS, json=payload)
    assert resp.status_code == 200


def _resume_room_config_json(desired_player_count: int = 2, participant_bindings: list[dict] | None = None) -> str:
    payload = {
        "room_mode": "resume_archive",
        "desired_player_count": desired_player_count,
        "seed_mode": "fixed",
        "seed": 12345,
        "allow_spectators": True,
        "enabled_modules_v2": [],
        "modules_v2_base_dir": "res://modules",
        "resume_summary": {
            "source_name": "backend_resume_test.json",
            "player_count": desired_player_count,
            "round_number": 0,
            "phase": "Setup",
            "current_index": 0,
        },
    }
    if participant_bindings is not None:
        payload["resume_participant_bindings"] = list(participant_bindings)
    return json.dumps(payload)


@pytest.mark.asyncio
async def test_create_room(client: AsyncClient, db_session: AsyncSession):
    user = await _create_user(client)
    resp = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    assert resp.status_code == 200
    data = resp.json()
    assert "room_code" in data
    assert "connect_token" in data
    assert data["ws_url"] == "ws://localhost:7000"
    payload = verify_token(str(data["connect_token"]))
    assert payload is not None
    assert str(payload.get("display_name", "")).startswith("游客#")
    assert int(payload.get("generation", -1)) == 1
    assert str(payload.get("join_policy", "")) == "public"
    assert not payload.get("password_hash")
    room = (await db_session.execute(
        select(Room).where(Room.room_code == data["room_code"])
    )).scalar_one()
    host_member = (await db_session.execute(
        select(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.user_id == user["user_id"],
            RoomMember.left_at.is_(None),
        )
    )).scalar_one()
    assert int(host_member.generation) == 2


@pytest.mark.asyncio
async def test_create_room_uses_configured_default_ws_url(client: AsyncClient, monkeypatch: pytest.MonkeyPatch):
    import app.rooms as rooms_module

    monkeypatch.setattr(rooms_module.settings, "default_ws_url", "wss://ws.fcmapp.ygowill.net:18443")

    user = await _create_user(client)
    resp = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["ws_url"] == "wss://ws.fcmapp.ygowill.net:18443"


@pytest.mark.asyncio
async def test_create_room_prefers_latest_healthy_game_server_ws_url(client: AsyncClient):
    hb = await client.post(
        "/internal/game_servers/heartbeat",
        headers={"X-Internal-Secret": "dev-internal-secret-change-in-production"},
        json={"game_server_id": "gs-single-1", "ws_url": "wss://single.example.test", "room_codes": []},
    )
    assert hb.status_code == 200

    user = await _create_user(client)
    resp = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["ws_url"] == "wss://single.example.test"


@pytest.mark.asyncio
async def test_room_member_active_uniqueness_constraints(db_session: AsyncSession):
    room = Room(
        room_code="UNI001",
        owner_user_id="u_owner_uni",
        status="Lobby",
        join_policy="public",
        config_json="{\"desired_player_count\":2}",
    )
    db_session.add(room)
    await db_session.flush()

    db_session.add(RoomMember(room_id=room.room_id, user_id="u_player_uni_1", role="player", seat_index=0))
    db_session.add(RoomMember(room_id=room.room_id, user_id="u_player_uni_1", role="player", seat_index=1))
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()

    db_session.add(RoomMember(room_id=room.room_id, user_id="u_player_uni_1", role="player", seat_index=0))
    await db_session.commit()

    db_session.add(RoomMember(room_id=room.room_id, user_id="u_player_uni_2", role="player", seat_index=0))
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()


@pytest.mark.asyncio
async def test_get_room(client: AsyncClient):
    user = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    code = create.json()["room_code"]
    resp = await client.get(f"/v1/rooms/{code}")
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code
    assert resp.json()["status"] == "Pending"


@pytest.mark.asyncio
async def test_get_room_not_found(client: AsyncClient):
    resp = await client.get("/v1/rooms/ZZZZZZ")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_list_rooms_requires_session(client: AsyncClient):
    resp = await client.get("/v1/rooms")
    assert resp.status_code == 422 or resp.status_code == 401


@pytest.mark.asyncio
async def test_list_rooms(client: AsyncClient):
    user = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    code = create.json()["room_code"]

    # Mark room as alive (directory should list only heartbeated rooms by default).
    hb = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-test-1", "room_codes": [code]},
    )
    assert hb.status_code == 200

    resp = await client.get(f"/v1/rooms?session_id={user['session_id']}")
    assert resp.status_code == 200
    rooms = resp.json()
    assert isinstance(rooms, list)
    assert any(r.get("room_code") == code for r in rooms)

    # When the room disappears from heartbeat, it should be delisted.
    hb2 = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-test-1", "room_codes": []},
    )
    assert hb2.status_code == 200
    resp2 = await client.get(f"/v1/rooms?session_id={user['session_id']}")
    assert resp2.status_code == 200
    assert not any(r.get("room_code") == code for r in resp2.json())


@pytest.mark.asyncio
async def test_pending_room_is_hidden_and_rejects_join(client: AsyncClient):
    hb = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-pending-1", "ws_url": "wss://pending.example.test", "room_codes": []},
    )
    assert hb.status_code == 200

    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"], "password": "secret"})
    code = create.json()["room_code"]

    rooms_resp = await client.get(f"/v1/rooms?session_id={host['session_id']}")
    assert rooms_resp.status_code == 200
    assert not any(r.get("room_code") == code for r in rooms_resp.json())

    hb2 = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-pending-1", "ws_url": "wss://pending.example.test", "room_codes": []},
    )
    assert hb2.status_code == 200

    room_resp = await client.get(f"/v1/rooms/{code}")
    assert room_resp.status_code == 200
    assert room_resp.json()["status"] == "Pending"

    player = await _create_user(client)
    join_resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"], "password": "secret"})
    assert join_resp.status_code == 409


@pytest.mark.asyncio
async def test_join_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-join-1", code)

    player = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code
    payload = verify_token(str(resp.json()["connect_token"]))
    assert payload is not None
    assert str(payload.get("display_name", "")).startswith("游客#")


@pytest.mark.asyncio
async def test_join_room_idempotent(client: AsyncClient, db_session: AsyncSession):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-join-2", code)

    player = await _create_user(client)
    r1 = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    r2 = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert r1.status_code == 200
    assert r2.status_code == 200
    payload1 = verify_token(str(r1.json()["connect_token"]))
    payload2 = verify_token(str(r2.json()["connect_token"]))
    assert payload1 is not None
    assert payload2 is not None
    assert int(payload1.get("generation", -1)) == 1
    assert int(payload2.get("generation", -1)) == 2
    room = (await db_session.execute(
        select(Room).where(Room.room_code == code)
    )).scalar_one()
    player_member = (await db_session.execute(
        select(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.user_id == player["user_id"],
            RoomMember.left_at.is_(None),
        )
    )).scalar_one()
    assert int(player_member.generation) == 3


@pytest.mark.asyncio
async def test_resume_room_existing_member(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-resume-1", code)

    player = await _create_user(client)
    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200
    joined_payload = verify_token(str(joined.json()["connect_token"]))
    assert joined_payload is not None
    assert int(joined_payload.get("generation", -1)) == 1

    resumed = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": player["session_id"]})
    assert resumed.status_code == 200
    payload = verify_token(str(resumed.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "player"
    assert int(payload.get("seat_index", -1)) == 1
    assert int(payload.get("generation", -1)) == 2


@pytest.mark.asyncio
async def test_create_resume_room_uses_seatless_host(client: AsyncClient, db_session: AsyncSession):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": _resume_room_config_json(),
    })
    assert create.status_code == 200

    payload = verify_token(str(create.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "host"
    assert payload.get("seat_index") is None
    assert int(payload.get("generation", -1)) == 1

    room = (await db_session.execute(
        select(Room).where(Room.room_code == create.json()["room_code"])
    )).scalar_one()
    host_member = (await db_session.execute(
        select(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.user_id == room.owner_user_id,
            RoomMember.left_at.is_(None),
        )
    )).scalar_one()
    assert host_member.role == "host"
    assert host_member.seat_index is None
    assert int(host_member.generation) == 2


@pytest.mark.asyncio
async def test_join_resume_room_uses_seatless_player(client: AsyncClient, db_session: AsyncSession):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": _resume_room_config_json(),
    })
    assert create.status_code == 200
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-resume-seatless-join", code)

    player = await _create_user(client)
    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200

    payload = verify_token(str(joined.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "player"
    assert payload.get("seat_index") is None
    assert int(payload.get("generation", -1)) == 1

    room = (await db_session.execute(
        select(Room).where(Room.room_code == code)
    )).scalar_one()
    player_member = (await db_session.execute(
        select(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.user_id == player["user_id"],
            RoomMember.left_at.is_(None),
        )
    )).scalar_one()
    assert player_member.role == "player"
    assert player_member.seat_index is None
    assert int(player_member.generation) == 2


@pytest.mark.asyncio
async def test_resume_resume_room_allows_seatless_members(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": _resume_room_config_json(),
    })
    assert create.status_code == 200
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-resume-seatless-resume", code)

    player = await _create_user(client)
    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200

    resumed_host = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": host["session_id"]})
    assert resumed_host.status_code == 200
    resumed_host_payload = verify_token(str(resumed_host.json()["connect_token"]))
    assert resumed_host_payload is not None
    assert resumed_host_payload.get("role") == "host"
    assert resumed_host_payload.get("seat_index") is None
    assert int(resumed_host_payload.get("generation", -1)) == 2

    resumed_player = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": player["session_id"]})
    assert resumed_player.status_code == 200
    resumed_player_payload = verify_token(str(resumed_player.json()["connect_token"]))
    assert resumed_player_payload is not None
    assert resumed_player_payload.get("role") == "player"
    assert resumed_player_payload.get("seat_index") is None
    assert int(resumed_player_payload.get("generation", -1)) == 2


@pytest.mark.asyncio
async def test_create_resume_room_prebinds_host_seat_from_participant_bindings(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": _resume_room_config_json(participant_bindings=[
            {"user_id": host["user_id"], "seat_index": 0, "player_id": 0, "role": "host"},
        ]),
    })
    assert create.status_code == 200
    payload = verify_token(str(create.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "host"
    assert int(payload.get("seat_index", -1)) == 0


@pytest.mark.asyncio
async def test_join_resume_room_prebinds_player_seat_from_participant_bindings(client: AsyncClient):
    host = await _create_user(client)
    player = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": _resume_room_config_json(participant_bindings=[
            {"user_id": host["user_id"], "seat_index": 0, "player_id": 0, "role": "host"},
            {"user_id": player["user_id"], "seat_index": 1, "player_id": 1, "role": "player"},
        ]),
    })
    assert create.status_code == 200
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-resume-bindings-join", code)

    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200
    payload = verify_token(str(joined.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "player"
    assert int(payload.get("seat_index", -1)) == 1


@pytest.mark.asyncio
async def test_resume_resume_room_recovers_seat_from_participant_bindings(
    client: AsyncClient,
    db_session: AsyncSession,
):
    host = await _create_user(client)
    player = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": _resume_room_config_json(participant_bindings=[
            {"user_id": host["user_id"], "seat_index": 0, "player_id": 0, "role": "host"},
            {"user_id": player["user_id"], "seat_index": 1, "player_id": 1, "role": "player"},
        ]),
    })
    assert create.status_code == 200
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-resume-bindings-resume", code)

    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200

    room = (await db_session.execute(
        select(Room).where(Room.room_code == code)
    )).scalar_one()
    player_member = (await db_session.execute(
        select(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.user_id == player["user_id"],
            RoomMember.left_at.is_(None),
        )
    )).scalar_one()
    player_member.seat_index = None
    await db_session.commit()

    resumed = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": player["session_id"]})
    assert resumed.status_code == 200
    payload = verify_token(str(resumed.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "player"
    assert int(payload.get("seat_index", -1)) == 1


@pytest.mark.asyncio
async def test_resume_room_refreshes_ws_url_from_healthy_game_server(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    hb = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-single-2", "ws_url": "wss://recover.example.test", "room_codes": [code]},
    )
    assert hb.status_code == 200

    player = await _create_user(client)
    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200

    resumed = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": player["session_id"]})
    assert resumed.status_code == 200
    assert resumed.json()["ws_url"] == "wss://recover.example.test"


@pytest.mark.asyncio
async def test_join_room_keeps_active_room_pinned_to_assigned_server_when_other_server_is_healthier(
    client: AsyncClient,
    db_session: AsyncSession,
):
    old_hb = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-old-1", "ws_url": "wss://old.example.test", "room_codes": []},
    )
    assert old_hb.status_code == 200

    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    assert create.status_code == 200
    code = create.json()["room_code"]
    assert create.json()["ws_url"] == "wss://old.example.test"

    await _heartbeat_room(client, "gs-old-1", code, "wss://old.example.test")

    old_server = (await db_session.execute(
        select(GameServer).where(GameServer.game_server_id == "gs-old-1")
    )).scalar_one()
    old_server.last_heartbeat_at = datetime.now(timezone.utc) - timedelta(seconds=120)
    await db_session.commit()

    new_hb = await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-new-1", "ws_url": "wss://new.example.test", "room_codes": []},
    )
    assert new_hb.status_code == 200

    player = await _create_user(client)
    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert joined.status_code == 200
    assert joined.json()["ws_url"] == "wss://old.example.test"


@pytest.mark.asyncio
async def test_join_password_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"], "password": "secret",
    })
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-password-1", code)

    player = await _create_user(client)
    # Wrong password
    bad = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"], "password": "wrong"})
    assert bad.status_code == 403
    # Correct password
    good = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"], "password": "secret"})
    assert good.status_code == 200


@pytest.mark.asyncio
async def test_create_password_room_token_preserves_password_metadata(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"], "password": "secret",
    })
    assert create.status_code == 200
    payload = verify_token(str(create.json()["connect_token"]))
    assert payload is not None
    assert str(payload.get("join_policy", "")) == "password"
    assert str(payload.get("password_hash", "")).strip() != ""


@pytest.mark.asyncio
async def test_resume_host_room_token_preserves_password_metadata(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"], "password": "secret",
    })
    code = create.json()["room_code"]

    resumed = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": host["session_id"]})
    assert resumed.status_code == 200
    payload = verify_token(str(resumed.json()["connect_token"]))
    assert payload is not None
    assert str(payload.get("role", "")) == "host"
    assert str(payload.get("join_policy", "")) == "password"
    assert str(payload.get("password_hash", "")).strip() != ""


@pytest.mark.asyncio
async def test_resume_password_room_without_password(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"], "password": "secret",
    })
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-password-2", code)

    player = await _create_user(client)
    joined = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"], "password": "secret"})
    assert joined.status_code == 200

    resumed = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": player["session_id"]})
    assert resumed.status_code == 200
    payload = verify_token(str(resumed.json()["connect_token"]))
    assert payload is not None
    assert payload.get("role") == "player"
    assert int(payload.get("seat_index", -1)) == 1


@pytest.mark.asyncio
async def test_spectate_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": "{\"desired_player_count\":2,\"allow_spectators\":true}",
    })
    code = create.json()["room_code"]
    sync = await client.post(
        "/internal/game_servers/gs-spectate-1/rooms/sync",
        headers=INTERNAL_HEADERS,
        json={
            "rooms": [
                {
                    "room_code": code,
                    "owner_user_id": host["user_id"],
                    "status": "InGame",
                    "join_policy": "public",
                    "config_json": "{\"desired_player_count\":2,\"allow_spectators\":true}",
                    "members": [{"user_id": host["user_id"], "role": "host", "seat_index": 0}],
                }
            ],
        },
    )
    assert sync.status_code == 200

    spectator = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/spectate", json={"session_id": spectator["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code


@pytest.mark.asyncio
async def test_join_room_rejects_in_game_for_new_member(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": "{\"desired_player_count\":2,\"allow_spectators\":true}",
    })
    code = create.json()["room_code"]
    sync = await client.post(
        "/internal/game_servers/gs-join-ingame-1/rooms/sync",
        headers=INTERNAL_HEADERS,
        json={
            "rooms": [
                {
                    "room_code": code,
                    "owner_user_id": host["user_id"],
                    "status": "InGame",
                    "join_policy": "public",
                    "config_json": "{\"desired_player_count\":2,\"allow_spectators\":true}",
                    "members": [{"user_id": host["user_id"], "role": "host", "seat_index": 0}],
                }
            ],
        },
    )
    assert sync.status_code == 200

    player = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_join_room_rejects_full_lobby(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": "{\"desired_player_count\":1}",
    })
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-join-full-1", code)

    player = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_spectate_room_rejects_lobby_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": "{\"desired_player_count\":2,\"allow_spectators\":true}",
    })
    code = create.json()["room_code"]
    await _heartbeat_room(client, "gs-spectate-lobby-1", code)

    spectator = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/spectate", json={"session_id": spectator["session_id"]})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_spectate_room_rejects_when_disabled(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"],
        "config_json": "{\"desired_player_count\":2,\"allow_spectators\":false}",
    })
    code = create.json()["room_code"]
    sync = await client.post(
        "/internal/game_servers/gs-spectate-disabled-1/rooms/sync",
        headers=INTERNAL_HEADERS,
        json={
            "rooms": [
                {
                    "room_code": code,
                    "owner_user_id": host["user_id"],
                    "status": "InGame",
                    "join_policy": "public",
                    "config_json": "{\"desired_player_count\":2,\"allow_spectators\":false}",
                    "members": [{"user_id": host["user_id"], "role": "host", "seat_index": 0}],
                }
            ],
        },
    )
    assert sync.status_code == 200

    spectator = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/spectate", json={"session_id": spectator["session_id"]})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_resume_room_requires_membership(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    outsider = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/resume", json={"session_id": outsider["session_id"]})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_join_room_rejects_ended_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-ended-join", "room_codes": [code]},
    )
    await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-ended-join", "room_codes": []},
    )

    player = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_spectate_room_rejects_ended_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-ended-spectate", "room_codes": [code]},
    )
    await client.post(
        "/internal/game_servers/heartbeat",
        headers=INTERNAL_HEADERS,
        json={"game_server_id": "gs-ended-spectate", "room_codes": []},
    )

    spectator = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/spectate", json={"session_id": spectator["session_id"]})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_join_nonexistent_room(client: AsyncClient):
    user = await _create_user(client)
    resp = await client.post("/v1/rooms/ZZZZZZ/join", json={"session_id": user["session_id"]})
    assert resp.status_code == 404
