import pytest
from httpx import AsyncClient

import app.auth as auth_module


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
async def test_register_creates_user_and_session(client: AsyncClient):
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
async def test_register_duplicate_display_name_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={
        "email": "nick1@b.com",
        "password": "pw",
        "display_name": "Alice",
    })
    resp = await client.post("/v1/auth/register", json={
        "email": "nick2@b.com",
        "password": "pw",
        "display_name": "alice",
    })
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
async def test_admin_env_login_bootstraps_account_without_registration(client: AsyncClient, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(auth_module.settings, "admin_email", "admin@fcm.test")
    monkeypatch.setattr(auth_module.settings, "admin_password", "super-secret")
    monkeypatch.setattr(auth_module.settings, "admin_display_name", "SystemAdmin")
    monkeypatch.setattr(auth_module.settings, "admin_user_ids", "")
    resp = await client.post("/v1/auth/login", json={"email": "admin@fcm.test", "password": "super-secret"})
    assert resp.status_code == 200
    assert resp.json()["display_name"] == "SystemAdmin"

    me = await client.get("/v1/auth/me", params={"session_id": resp.json()["session_id"]})
    assert me.status_code == 200
    assert me.json()["is_admin"] is True
    assert me.json()["email"] == "admin@fcm.test"


@pytest.mark.asyncio
async def test_bind_guest_to_email_upgrades_account_immediately(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-dev"})
    sid = guest.json()["session_id"]
    uid = guest.json()["user_id"]
    resp = await client.post("/v1/auth/bind", json={
        "session_id": sid,
        "provider": "email",
        "email": "bind@b.com",
        "password": "pw",
    })
    assert resp.status_code == 200
    assert resp.json()["user_id"] == uid
    assert resp.json()["is_guest"] is False
    assert str(resp.json().get("display_name", "")).startswith("账号#")

    me = await client.get("/v1/auth/me", params={"session_id": sid})
    assert me.status_code == 200
    assert me.json()["is_guest"] is False
    assert me.json()["email"] == "bind@b.com"


@pytest.mark.asyncio
async def test_guest_login_after_bind_creates_new_guest_user(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-reuse-device"})
    sid = guest.json()["session_id"]
    original_user_id = guest.json()["user_id"]

    bind = await client.post("/v1/auth/bind", json={
        "session_id": sid,
        "provider": "email",
        "email": "bind-reuse@b.com",
        "password": "pw",
    })
    assert bind.status_code == 200
    assert bind.json()["user_id"] == original_user_id
    assert bind.json()["is_guest"] is False

    relogin = await client.post("/v1/auth/guest", json={"device_id": "bind-reuse-device"})
    assert relogin.status_code == 200
    assert relogin.json()["user_id"] != original_user_id
    assert relogin.json()["is_guest"] is True
    assert str(relogin.json().get("display_name", "")).startswith("游客#")


@pytest.mark.asyncio
async def test_bind_unsupported_provider_rejected(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-bad-provider"})
    resp = await client.post("/v1/auth/bind", json={
        "session_id": guest.json()["session_id"],
        "provider": "steam",
        "email": "x@b.com",
        "password": "p",
    })
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_bind_duplicate_email_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={"email": "taken@b.com", "password": "p"})
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-dup"})
    resp = await client.post("/v1/auth/bind", json={
        "session_id": guest.json()["session_id"],
        "provider": "email",
        "email": "taken@b.com",
        "password": "p2",
    })
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_logout_revokes_session(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "logout-dev"})
    sid = guest.json()["session_id"]
    resp = await client.post("/v1/auth/logout", json={"session_id": sid})
    assert resp.status_code == 200

    resp2 = await client.post("/v1/auth/bind", json={
        "session_id": sid,
        "provider": "email",
        "email": "x@b.com",
        "password": "p",
    })
    assert resp2.status_code == 401


@pytest.mark.asyncio
async def test_register_with_custom_display_name(client: AsyncClient):
    resp = await client.post("/v1/auth/register", json={
        "email": "nick@b.com",
        "password": "pw",
        "display_name": "Alice",
    })
    assert resp.status_code == 200
    assert resp.json()["display_name"] == "Alice"


@pytest.mark.asyncio
async def test_me_returns_display_name(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={
        "email": "me@b.com",
        "password": "pw",
        "display_name": "MeName",
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
async def test_update_profile_duplicate_display_name_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={
        "email": "dup-name-1@b.com",
        "password": "pw",
        "display_name": "Bob",
    })
    reg = await client.post("/v1/auth/register", json={"email": "dup-name-2@b.com", "password": "pw"})
    sid = reg.json()["session_id"]
    resp = await client.put("/v1/auth/profile", json={"session_id": sid, "display_name": "bob"})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_update_profile_guest_forbidden(client: AsyncClient):
    guest = await client.post("/v1/auth/guest", json={"device_id": "guest-profile"})
    sid = guest.json()["session_id"]
    resp = await client.put("/v1/auth/profile", json={"session_id": sid, "display_name": "Nope"})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_update_email_success(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={"email": "email-old@b.com", "password": "pw"})
    sid = reg.json()["session_id"]
    resp = await client.put("/v1/auth/email", json={
        "session_id": sid,
        "email": "email-new@b.com",
        "password": "pw",
    })
    assert resp.status_code == 200
    assert resp.json()["email"] == "email-new@b.com"

    login = await client.post("/v1/auth/login", json={"email": "email-new@b.com", "password": "pw"})
    assert login.status_code == 200
    assert login.json()["user_id"] == reg.json()["user_id"]


@pytest.mark.asyncio
async def test_update_email_duplicate_rejected(client: AsyncClient):
    await client.post("/v1/auth/register", json={"email": "email-a@b.com", "password": "pw"})
    reg = await client.post("/v1/auth/register", json={"email": "email-b@b.com", "password": "pw"})
    sid = reg.json()["session_id"]
    resp = await client.put("/v1/auth/email", json={
        "session_id": sid,
        "email": "email-a@b.com",
        "password": "pw",
    })
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_update_email_wrong_password_rejected(client: AsyncClient):
    reg = await client.post("/v1/auth/register", json={"email": "email-pass@b.com", "password": "pw"})
    sid = reg.json()["session_id"]
    resp = await client.put("/v1/auth/email", json={
        "session_id": sid,
        "email": "email-pass-new@b.com",
        "password": "wrong",
    })
    assert resp.status_code == 401
