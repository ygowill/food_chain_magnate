import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_guest_login_creates_user(client: AsyncClient):
    resp = await client.post("/v1/auth/guest", json={"device_id": "test-device-001"})
    assert resp.status_code == 200
    data = resp.json()
    assert "user_id" in data
    assert "session_id" in data


@pytest.mark.asyncio
async def test_guest_login_same_device_returns_same_user(client: AsyncClient):
    r1 = await client.post("/v1/auth/guest", json={"device_id": "device-dup"})
    r2 = await client.post("/v1/auth/guest", json={"device_id": "device-dup"})
    assert r1.json()["user_id"] == r2.json()["user_id"]
    assert r1.json()["session_id"] != r2.json()["session_id"]


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
