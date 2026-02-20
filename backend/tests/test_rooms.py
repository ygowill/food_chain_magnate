import pytest
from httpx import AsyncClient


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
async def test_join_room(client: AsyncClient):
    host = await _create_user(client)
    create = await client.post("/v1/rooms", json={"session_id": host["session_id"]})
    code = create.json()["room_code"]

    player = await _create_user(client)
    resp = await client.post(f"/v1/rooms/{code}/join", json={"session_id": player["session_id"]})
    assert resp.status_code == 200
    assert resp.json()["room_code"] == code


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
