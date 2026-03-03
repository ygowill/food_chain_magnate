import pytest
from httpx import AsyncClient

from app.connect_token import verify_token


async def _create_user(client: AsyncClient) -> dict:
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-{id(client)}-{pytest.importorskip('random').randint(0,99999)}"})
    return resp.json()


@pytest.mark.asyncio
async def test_create_room(client: AsyncClient):
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


@pytest.mark.asyncio
async def test_get_room(client: AsyncClient):
    user = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": user["session_id"]})
    code = create.json()["room_code"]
    resp = await client.get(f"/v1/rooms/{code}")
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code
    assert resp.json()["status"] == "Lobby"


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
        headers={"X-Internal-Secret": "dev-internal-secret-change-in-production"},
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
        headers={"X-Internal-Secret": "dev-internal-secret-change-in-production"},
        json={"game_server_id": "gs-test-1", "room_codes": []},
    )
    assert hb2.status_code == 200
    resp2 = await client.get(f"/v1/rooms?session_id={user['session_id']}")
    assert resp2.status_code == 200
    assert not any(r.get("room_code") == code for r in resp2.json())


@pytest.mark.asyncio
async def test_join_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    player = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code
    payload = verify_token(str(resp.json()["connect_token"]))
    assert payload is not None
    assert str(payload.get("display_name", "")).startswith("游客#")


@pytest.mark.asyncio
async def test_join_room_idempotent(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    player = await _create_user(client)
    r1 = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    r2 = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert r1.status_code == 200
    assert r2.status_code == 200


@pytest.mark.asyncio
async def test_join_password_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={
        "session_id": host["session_id"], "password": "secret",
    })
    code = create.json()["room_code"]

    player = await _create_user(client)
    # Wrong password
    bad = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"], "password": "wrong"})
    assert bad.status_code == 403
    # Correct password
    good = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"], "password": "secret"})
    assert good.status_code == 200


@pytest.mark.asyncio
async def test_spectate_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    spectator = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/spectate", json={"session_id": spectator["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code


@pytest.mark.asyncio
async def test_join_nonexistent_room(client: AsyncClient):
    user = await _create_user(client)
    resp = await client.post("/v1/rooms/ZZZZZZ/join", json={"session_id": user["session_id"]})
    assert resp.status_code == 404
