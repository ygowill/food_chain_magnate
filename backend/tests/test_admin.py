from pathlib import Path
import random

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Match, MatchParticipant, MatchReplay, Room, RoomMember


async def _create_user(client: AsyncClient) -> dict:
    resp = await client.post("/v1/auth/guest", json={"device_id": f"dev-admin-{random.randint(0, 999999)}"})
    return resp.json()


async def _seed_room_and_match(
    db: AsyncSession,
    owner_user_id: str,
    spectator_user_id: str,
    replay_storage_dir: Path,
    room_code: str = "ADMIN1",
) -> tuple[str, str]:
    room = Room(
        room_code=room_code,
        owner_user_id=owner_user_id,
        status="Lobby",
        join_policy="public",
        ws_url="ws://localhost:7000",
    )
    db.add(room)
    await db.flush()
    db.add(RoomMember(room_id=room.room_id, user_id=owner_user_id, role="host", seat_index=0))
    db.add(RoomMember(room_id=room.room_id, user_id=spectator_user_id, role="spectator", seat_index=None))

    match = Match(room_code=room.room_code, status="completed", player_count=1)
    db.add(match)
    await db.flush()
    db.add(MatchParticipant(match_id=match.match_id, user_id=owner_user_id, role="player", seat_index=0, result="win"))
    db.add(MatchParticipant(match_id=match.match_id, user_id=spectator_user_id, role="spectator", seat_index=None))

    replay_file = replay_storage_dir / f"{match.match_id}.json"
    replay_file.parent.mkdir(parents=True, exist_ok=True)
    replay_file.write_text('{"schema_version":3,"commands":[]}', encoding="utf-8")
    db.add(MatchReplay(
        match_id=match.match_id,
        storage_uri=f"local_file://{match.match_id}.json",
        checksum="admin-test",
        size_bytes=int(replay_file.stat().st_size),
    ))
    await db.commit()
    return room.room_code, match.match_id


@pytest.mark.asyncio
async def test_admin_requires_allowlist(client: AsyncClient):
    user = await _create_user(client)
    old_admin_user_ids = settings.admin_user_ids
    settings.admin_user_ids = ""
    try:
        resp = await client.get("/v1/admin/users", params={"session_id": user["session_id"]})
        assert resp.status_code == 403
        assert resp.json()["detail"] == "admin disabled"
    finally:
        settings.admin_user_ids = old_admin_user_ids


@pytest.mark.asyncio
async def test_admin_env_credentials_enable_admin_access(client: AsyncClient, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "admin_user_ids", "")
    monkeypatch.setattr(settings, "admin_email", "admin-env@fcm.test")
    monkeypatch.setattr(settings, "admin_password", "env-secret")
    monkeypatch.setattr(settings, "admin_display_name", "EnvAdmin")

    login = await client.post("/v1/auth/login", json={
        "email": "admin-env@fcm.test",
        "password": "env-secret",
    })
    assert login.status_code == 200

    resp = await client.get("/v1/admin/users", params={"session_id": login.json()["session_id"]})
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_admin_endpoints_manage_entities(client: AsyncClient, db_session: AsyncSession, tmp_path: Path):
    admin_user = await _create_user(client)
    normal_user = await _create_user(client)

    old_admin_user_ids = settings.admin_user_ids
    old_replay_storage_dir = settings.replay_storage_dir
    settings.admin_user_ids = admin_user["user_id"]
    settings.replay_storage_dir = str(tmp_path)
    try:
        admin_me = await client.get("/v1/auth/me", params={"session_id": admin_user["session_id"]})
        assert admin_me.status_code == 200
        assert admin_me.json()["is_admin"] is True

        normal_me = await client.get("/v1/auth/me", params={"session_id": normal_user["session_id"]})
        assert normal_me.status_code == 200
        assert normal_me.json()["is_admin"] is False

        room_code, match_id = await _seed_room_and_match(
            db_session,
            owner_user_id=normal_user["user_id"],
            spectator_user_id=admin_user["user_id"],
            replay_storage_dir=tmp_path,
            room_code="ADMIN1",
        )

        forbidden = await client.get("/v1/admin/users", params={"session_id": normal_user["session_id"]})
        assert forbidden.status_code == 403
        assert forbidden.json()["detail"] == "admin only"

        list_users_resp = await client.get("/v1/admin/users", params={"session_id": admin_user["session_id"]})
        assert list_users_resp.status_code == 200
        users = list_users_resp.json()
        assert any(item["user_id"] == normal_user["user_id"] for item in users)

        update_status_resp = await client.put(
            f"/v1/admin/users/{normal_user['user_id']}/status",
            params={"session_id": admin_user["session_id"]},
            json={"status": "disabled"},
        )
        assert update_status_resp.status_code == 200
        assert update_status_resp.json()["status"] == "disabled"

        rooms_resp = await client.get("/v1/admin/rooms", params={"session_id": admin_user["session_id"]})
        assert rooms_resp.status_code == 200
        room = next(item for item in rooms_resp.json() if item["room_code"] == room_code)
        assert room["player_count"] == 1
        assert room["spectator_count"] == 1

        end_room_resp = await client.post(
            f"/v1/admin/rooms/{room_code}/end",
            params={"session_id": admin_user["session_id"]},
        )
        assert end_room_resp.status_code == 200
        assert end_room_resp.json()["status"] == "Ended"

        matches_resp = await client.get("/v1/admin/matches", params={"session_id": admin_user["session_id"]})
        assert matches_resp.status_code == 200
        match = next(item for item in matches_resp.json() if item["match_id"] == match_id)
        assert match["has_replay"] is True
        assert match["participant_count"] == 2

        delete_match_resp = await client.delete(
            f"/v1/admin/matches/{match_id}",
            params={"session_id": admin_user["session_id"]},
        )
        assert delete_match_resp.status_code == 200
        assert delete_match_resp.json()["ok"] is True
        assert not (tmp_path / f"{match_id}.json").exists()

        matches_after_delete = await client.get("/v1/admin/matches", params={"session_id": admin_user["session_id"]})
        assert matches_after_delete.status_code == 200
        assert all(item["match_id"] != match_id for item in matches_after_delete.json())
    finally:
        settings.admin_user_ids = old_admin_user_ids
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_admin_batch_endpoints_manage_entities(client: AsyncClient, db_session: AsyncSession, tmp_path: Path):
    admin_user = await _create_user(client)
    user_a = await _create_user(client)
    user_b = await _create_user(client)
    user_c = await _create_user(client)

    old_admin_user_ids = settings.admin_user_ids
    old_replay_storage_dir = settings.replay_storage_dir
    settings.admin_user_ids = admin_user["user_id"]
    settings.replay_storage_dir = str(tmp_path)
    try:
        room_code_a, match_id_a = await _seed_room_and_match(
            db_session,
            owner_user_id=user_a["user_id"],
            spectator_user_id=admin_user["user_id"],
            replay_storage_dir=tmp_path,
            room_code="BATCHA",
        )
        room_code_b, match_id_b = await _seed_room_and_match(
            db_session,
            owner_user_id=user_b["user_id"],
            spectator_user_id=admin_user["user_id"],
            replay_storage_dir=tmp_path,
            room_code="BATCHB",
        )
        room_code_c, match_id_c = await _seed_room_and_match(
            db_session,
            owner_user_id=user_c["user_id"],
            spectator_user_id=admin_user["user_id"],
            replay_storage_dir=tmp_path,
            room_code="BATCHC",
        )

        batch_status_resp = await client.post(
            "/v1/admin/users/batch/status",
            params={"session_id": admin_user["session_id"]},
            json={"user_ids": [user_a["user_id"], user_b["user_id"], "missing_user"], "status": "disabled"},
        )
        assert batch_status_resp.status_code == 200
        batch_status_json = batch_status_resp.json()
        assert batch_status_json["requested"] == 3
        assert batch_status_json["affected"] == 2
        assert "missing_user" in batch_status_json["missing"]

        batch_end_rooms_resp = await client.post(
            "/v1/admin/rooms/batch/end",
            params={"session_id": admin_user["session_id"]},
            json={"room_codes": [room_code_a, room_code_b, "MISSING_ROOM"]},
        )
        assert batch_end_rooms_resp.status_code == 200
        batch_end_rooms_json = batch_end_rooms_resp.json()
        assert batch_end_rooms_json["requested"] == 3
        assert batch_end_rooms_json["affected"] == 2
        assert "MISSING_ROOM" in batch_end_rooms_json["missing"]

        batch_delete_rooms_resp = await client.post(
            "/v1/admin/rooms/batch/delete",
            params={"session_id": admin_user["session_id"]},
            json={"room_codes": [room_code_c, "MISSING_ROOM_2"]},
        )
        assert batch_delete_rooms_resp.status_code == 200
        batch_delete_rooms_json = batch_delete_rooms_resp.json()
        assert batch_delete_rooms_json["requested"] == 2
        assert batch_delete_rooms_json["affected"] == 1
        assert "MISSING_ROOM_2" in batch_delete_rooms_json["missing"]

        batch_delete_matches_resp = await client.post(
            "/v1/admin/matches/batch/delete",
            params={"session_id": admin_user["session_id"]},
            json={"match_ids": [match_id_a, match_id_b, match_id_c, "missing_match"]},
        )
        assert batch_delete_matches_resp.status_code == 200
        batch_delete_matches_json = batch_delete_matches_resp.json()
        assert batch_delete_matches_json["requested"] == 4
        assert batch_delete_matches_json["affected"] == 3
        assert "missing_match" in batch_delete_matches_json["missing"]
        assert not (tmp_path / f"{match_id_a}.json").exists()
        assert not (tmp_path / f"{match_id_b}.json").exists()
        assert not (tmp_path / f"{match_id_c}.json").exists()

        batch_delete_users_resp = await client.post(
            "/v1/admin/users/batch/delete",
            params={"session_id": admin_user["session_id"]},
            json={"user_ids": [user_a["user_id"], user_b["user_id"], "missing_user_2"]},
        )
        assert batch_delete_users_resp.status_code == 200
        batch_delete_users_json = batch_delete_users_resp.json()
        assert batch_delete_users_json["requested"] == 3
        assert batch_delete_users_json["affected"] == 2
        assert "missing_user_2" in batch_delete_users_json["missing"]
        assert int(batch_delete_users_json.get("meta", {}).get("deleted_rooms", 0)) == 2

        users_after_delete = await client.get("/v1/admin/users", params={"session_id": admin_user["session_id"]})
        assert users_after_delete.status_code == 200
        remaining_user_ids = {item["user_id"] for item in users_after_delete.json()}
        assert user_a["user_id"] not in remaining_user_ids
        assert user_b["user_id"] not in remaining_user_ids
    finally:
        settings.admin_user_ids = old_admin_user_ids
        settings.replay_storage_dir = old_replay_storage_dir
