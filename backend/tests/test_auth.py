import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_guest_login_creates_user(client: AsyncClient):
    resp = await client.post("/v1/auth/guest", json={"device_id": "test-device-001"})
    assert resp.status_code == 200
    data = resp.json()
    assert "user_id" in data
    assert "session_id" in data
    assert data["is_guest"] is True
    assert str(data.get("display_name", "")).startswith("游客#")


@pytest.mark.asyncio
async def test_guest_login_same_device_returns_same_user(client: AsyncClient):
    r1 = await client.post("/v1/auth/guest", json={"device_id": "device-dup"})
    r2 = await client.post("/v1/auth/guest", json={"device_id": "device-dup"})
    assert r1.json()["user_id"] == r2.json()["user_id"]
    assert r1.json()["session_id"] != r2.json()["session_id"]
    assert r1.json()["display_name"] == r2.json()["display_name"]


@pytest.mark.asyncio
async def test_guest_login_different_device_creates_different_user(client: AsyncClient):
    r1 = await client.post("/v1/auth/guest", json={"device_id": "dev-a"})
    r2 = await client.post("/v1/auth/guest", json={"device_id": "dev-b"})
    assert r1.json()["user_id"] != r2.json()["user_id"]


@pytest.mark.asyncio
async def test_guest_login_empty_device_id_rejected(client: AsyncClient):
    resp = await client.post("/v1/auth/guest", json={"device_id": ""})
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_health(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_register_creates_user(client: AsyncClient):
    resp = await client.post("/v1/auth/register", json={"email": "a@b.com", "password": "pass123"})
    assert resp.status_code == 200
    data = resp.json()
    assert "user_id" in data
    assert "session_id" in data
    assert data["is_guest"] is False
    assert str(data.get("display_name", "")).startswith("账号#")


@pytest.mark.asyncio
async def test_register_duplicate_email_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={"email": "dup@b.com", "password": "p1"})
    resp = await client.post("/v1/auth/register", json={"email": "dup@b.com", "password": "p2"})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_register_duplicate_email_casefold_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={"email": "DUP@b.com", "password": "p1"})
    resp = await client.post("/v1/auth/register", json={"email": "dup@b.com", "password": "p2"})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_login_success(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={"email": "login@b.com", "password": "secret"})
    resp = await client.post("/v1/auth/login", json={"email": "login@b.com", "password": "secret"})
    assert resp.status_code == 200
    assert resp.json()["user_id"] == reg.json()["user_id"]
    assert resp.json()["display_name"] == reg.json()["display_name"]


@pytest.mark.asyncio
async def test_login_wrong_password(client: AsyncClient):
    await client.post("/v1/auth/register", json={"email": "wp@b.com", "password": "correct"})
    resp = await client.post("/v1/auth/login", json={"email": "wp@b.com", "password": "wrong"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_login_nonexistent_email(client: AsyncClient):
    resp = await client.post("/v1/auth/login", json={"email": "no@b.com", "password": "x"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_bind_guest_to_email(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-dev"})
    sid = guest.json()["session_id"]
    uid = guest.json()["user_id"]
    resp = await client.post("/v1/auth/bind", json={
        "session_id": sid, "provider": "email",
        "email": "bind@b.com", "password": "pw",
    })
    assert resp.status_code == 200
    assert resp.json()["user_id"] == uid
    assert resp.json()["is_guest"] is False
    assert str(resp.json().get("display_name", "")).startswith("账号#")
    # Can now login with email
    login = await client.post("/v1/auth/login", json={
        "email": "bind@b.com", "password": "pw",
    })
    assert login.json()["user_id"] == uid


@pytest.mark.asyncio
async def test_bind_unsupported_provider_rejected(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-bad-provider"})
    resp = await client.post("/v1/auth/bind", json={
        "session_id": guest.json()["session_id"], "provider": "steam",
        "email": "x@b.com", "password": "p",
    })
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_bind_duplicate_email_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={
        "email": "taken@b.com", "password": "p",
    })
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-dup"})
    resp = await client.post("/v1/auth/bind", json={
        "session_id": guest.json()["session_id"], "provider": "email",
        "email": "taken@b.com", "password": "p2",
    })
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_logout_revokes_session(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={
        "email": "out@b.com", "password": "p",
    })
    sid = reg.json()["session_id"]
    resp = await client.post("/v1/auth/logout", json={"session_id": sid})
    assert resp.status_code == 200
    # Revoked session should fail auth
    resp2 = await client.post("/v1/auth/bind", json={
        "session_id": sid, "provider": "email",
        "email": "x@b.com", "password": "p",
    })
    assert resp2.status_code == 401


@pytest.mark.asyncio
async def test_register_with_custom_display_name(client: AsyncClient):
    resp = await client.post("/v1/auth/register", json={
        "email": "nick@b.com", "password": "pw", "display_name": "Alice",
    })
    assert resp.status_code == 200
    assert resp.json()["display_name"] == "Alice"


@pytest.mark.asyncio
async def test_me_returns_display_name(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={
        "email": "me@b.com", "password": "pw", "display_name": "MeName",
    })
    sid = reg.json()["session_id"]
    me = await client.get("/v1/auth/me", params={"session_id": sid})
    assert me.status_code == 200
    assert me.json()["display_name"] == "MeName"


@pytest.mark.asyncio
async def test_update_profile_display_name(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={"email": "upd@b.com", "password": "pw"})
    sid = reg.json()["session_id"]
    resp = await client.put("/v1/auth/profile", json={"session_id": sid, "display_name": "Renamed"})
    assert resp.status_code == 200
    assert resp.json()["display_name"] == "Renamed"
    me = await client.get("/v1/auth/me", params={"session_id": sid})
    assert me.status_code == 200
    assert me.json()["display_name"] == "Renamed"


@pytest.mark.asyncio
async def test_update_profile_guest_forbidden(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "guest-profile"})
    sid = guest.json()["session_id"]
    resp = await client.put("/v1/auth/profile", json={"session_id": sid, "display_name": "Nope"})
    assert resp.status_code == 403
