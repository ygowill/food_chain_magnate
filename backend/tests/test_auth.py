from urllib.parse import parse_qs, urlparse

import pytest
from httpx import AsyncClient

import app.auth as auth_module


def _extract_token(verification_url: str) -> str:
    parsed = urlparse(str(verification_url))
    return str(parse_qs(parsed.query)["token"][0])


@pytest.fixture
def sent_verifications(monkeypatch: pytest.MonkeyPatch) -> list[dict]:
    sent: list[dict] = []

    async def _fake_send(recipient: str, verification_url: str, purpose: str) -> None:
        sent.append({
            "recipient": recipient,
            "verification_url": verification_url,
            "purpose": purpose,
        })

    monkeypatch.setattr(auth_module, "send_verification_email", _fake_send)
    return sent


async def _confirm_latest_verification(client: AsyncClient, sent_verifications: list[dict]) -> dict:
    token = _extract_token(sent_verifications[-1]["verification_url"])
    resp = await client.post("/v1/auth/email-verification/confirm", json={"token": token})
    assert resp.status_code == 200
    return resp.json()


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
async def test_register_creates_pending_verification(client: AsyncClient, sent_verifications: list[dict]):
    resp = await client.post("/v1/auth/register", json={"email": "a@b.com", "password": "pass123"})
    assert resp.status_code == 202
    data = resp.json()
    assert data["status"] == "pending_verification"
    assert data["email"] == "a@b.com"
    assert data["resend_after_sec"] == 60
    assert len(sent_verifications) == 1
    assert sent_verifications[0]["recipient"] == "a@b.com"
    assert sent_verifications[0]["purpose"] == "register"


@pytest.mark.asyncio
async def test_register_duplicate_email_reuses_pending_verification(client: AsyncClient, sent_verifications: list[dict]):
    first = await client.post("/v1/auth/register", json={"email": "dup@b.com", "password": "p1"})
    second = await client.post("/v1/auth/register", json={"email": "dup@b.com", "password": "p2"})
    assert first.status_code == 202
    assert second.status_code == 202
    assert len(sent_verifications) == 1


@pytest.mark.asyncio
async def test_register_duplicate_email_casefold_reuses_pending_verification(client: AsyncClient, sent_verifications: list[dict]):
    await client.post("/v1/auth/register", json={"email": "DUP@b.com", "password": "p1"})
    resp = await client.post("/v1/auth/register", json={"email": "dup@b.com", "password": "p2"})
    assert resp.status_code == 202
    assert len(sent_verifications) == 1


@pytest.mark.asyncio
async def test_login_success_after_email_verification(client: AsyncClient, sent_verifications: list[dict]):
    reg = await client.post("/v1/auth/register", json={"email": "login@b.com", "password": "secret"})
    assert reg.status_code == 202
    confirmed = await _confirm_latest_verification(client, sent_verifications)
    resp = await client.post("/v1/auth/login", json={"email": "login@b.com", "password": "secret"})
    assert resp.status_code == 200
    assert resp.json()["user_id"] == confirmed["user_id"]
    assert resp.json()["display_name"] == confirmed["display_name"]


@pytest.mark.asyncio
async def test_login_unverified_email_rejected(client: AsyncClient, sent_verifications: list[dict]):
    await client.post("/v1/auth/register", json={"email": "pending@b.com", "password": "correct"})
    resp = await client.post("/v1/auth/login", json={"email": "pending@b.com", "password": "correct"})
    assert resp.status_code == 403
    detail = resp.json()["detail"]
    assert detail["code"] == "EMAIL_NOT_VERIFIED"
    assert detail["email"] == "pending@b.com"
    assert detail["resend_after_sec"] >= 0
    assert len(sent_verifications) == 1


@pytest.mark.asyncio
async def test_login_wrong_password(client: AsyncClient, sent_verifications: list[dict]):
    await client.post("/v1/auth/register", json={"email": "wp@b.com", "password": "correct"})
    await _confirm_latest_verification(client, sent_verifications)
    resp = await client.post("/v1/auth/login", json={"email": "wp@b.com", "password": "wrong"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_login_nonexistent_email(client: AsyncClient):
    resp = await client.post("/v1/auth/login", json={"email": "no@b.com", "password": "x"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_bind_guest_to_email_requires_verification(client: AsyncClient, sent_verifications: list[dict]):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-dev"})
    sid = guest.json()["session_id"]
    uid = guest.json()["user_id"]
    resp = await client.post("/v1/auth/bind", json={
        "session_id": sid,
        "provider": "email",
        "email": "bind@b.com",
        "password": "pw",
    })
    assert resp.status_code == 202
    assert resp.json()["status"] == "pending_verification"

    me_before = await client.get("/v1/auth/me", params={"session_id": sid})
    assert me_before.status_code == 200
    assert me_before.json()["is_guest"] is True
    assert me_before.json()["email"] == "bind@b.com"
    assert me_before.json()["email_verified"] is False
    assert me_before.json()["email_verification_pending"] is True

    confirmed = await _confirm_latest_verification(client, sent_verifications)
    assert confirmed["user_id"] == uid
    assert confirmed["is_guest"] is False

    login = await client.post("/v1/auth/login", json={
        "email": "bind@b.com",
        "password": "pw",
    })
    assert login.status_code == 200
    assert login.json()["user_id"] == uid

    me_after = await client.get("/v1/auth/me", params={"session_id": confirmed["session_id"]})
    assert me_after.status_code == 200
    assert me_after.json()["is_guest"] is False
    assert me_after.json()["email_verified"] is True


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
async def test_bind_duplicate_email_rejected(client: AsyncClient, sent_verifications: list[dict]):
    await client.post("/v1/auth/register", json={"email": "taken@b.com", "password": "p"})
    await _confirm_latest_verification(client, sent_verifications)

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
async def test_register_with_custom_display_name(client: AsyncClient, sent_verifications: list[dict]):
    resp = await client.post("/v1/auth/register", json={
        "email": "nick@b.com",
        "password": "pw",
        "display_name": "Alice",
    })
    assert resp.status_code == 202
    confirmed = await _confirm_latest_verification(client, sent_verifications)
    assert confirmed["display_name"] == "Alice"


@pytest.mark.asyncio
async def test_me_returns_display_name(client: AsyncClient, sent_verifications: list[dict]):
    await client.post("/v1/auth/register", json={
        "email": "me@b.com",
        "password": "pw",
        "display_name": "MeName",
    })
    confirmed = await _confirm_latest_verification(client, sent_verifications)
    sid = confirmed["session_id"]
    me = await client.get("/v1/auth/me", params={"session_id": sid})
    assert me.status_code == 200
    assert me.json()["display_name"] == "MeName"


@pytest.mark.asyncio
async def test_update_profile_display_name(client: AsyncClient, sent_verifications: list[dict]):
    await client.post("/v1/auth/register", json={"email": "upd@b.com", "password": "pw"})
    confirmed = await _confirm_latest_verification(client, sent_verifications)
    sid = confirmed["session_id"]
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


@pytest.mark.asyncio
async def test_resend_verification_email_by_email(
    client: AsyncClient,
    sent_verifications: list[dict],
    monkeypatch: pytest.MonkeyPatch,
):
    await client.post("/v1/auth/register", json={"email": "resend@b.com", "password": "pw"})
    monkeypatch.setattr(auth_module.settings, "email_verify_resend_cooldown_seconds", 0)
    resp = await client.post("/v1/auth/email-verification/resend", json={"email": "resend@b.com"})
    assert resp.status_code == 202
    assert len(sent_verifications) == 2


@pytest.mark.asyncio
async def test_resend_verification_email_by_session(
    client: AsyncClient,
    sent_verifications: list[dict],
    monkeypatch: pytest.MonkeyPatch,
):
    guest = await client.post("/v1/auth/guest", json={"device_id": "bind-resend"})
    sid = guest.json()["session_id"]
    bind = await client.post("/v1/auth/bind", json={
        "session_id": sid,
        "provider": "email",
        "email": "bind-resend@b.com",
        "password": "pw",
    })
    assert bind.status_code == 202

    monkeypatch.setattr(auth_module.settings, "email_verify_resend_cooldown_seconds", 0)
    resp = await client.post("/v1/auth/email-verification/resend", json={"session_id": sid})
    assert resp.status_code == 202
    assert len(sent_verifications) == 2
