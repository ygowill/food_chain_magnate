from __future__ import annotations

import base64
import binascii
import hashlib
from datetime import datetime, timezone
import hmac
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.models import GameServer, Room, RoomMember, RoomTombstone, Match, MatchParticipant, MatchReplay, MatchArtifact
from app.replay_storage import save_local_match_artifact, save_local_replay_archive
from app.room_config import RoomConfigParseError, parse_room_config_json

router = APIRouter(prefix="/internal", tags=["internal"])
ACTIVE_ROOM_STATUSES = ("Lobby", "Starting", "InGame")
RESUMABLE_MEMBER_STATUSES = ("active", "reconnecting")
ARTIFACT_TYPE_LATEST_AUTOSAVE = "autosave_latest"
ARTIFACT_TYPE_MAP_SNAPSHOT = "map_snapshot"
SNAPSHOT_KIND_ROUND_END = "round_end"
SNAPSHOT_KIND_GAME_OVER = "game_over"

async def _mark_room_members_left(
    db: AsyncSession,
    room_ids: list[str],
    now: datetime,
    member_status: str = "left",
) -> None:
    if not room_ids:
        return
    members = (await db.execute(
        select(RoomMember).where(
            RoomMember.room_id.in_(room_ids),
            RoomMember.left_at.is_(None),
        )
    )).scalars().all()
    for member in members:
        member.left_at = now
        member.member_status = member_status


def _require_internal_secret(x_internal_secret: Optional[str] = Header(default=None, alias="X-Internal-Secret")) -> None:
    expected = str(settings.internal_api_secret).strip()
    if expected == "":
        raise HTTPException(status_code=500, detail="internal_api_secret not configured")
    provided = str(x_internal_secret or "").strip()
    if not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unauthorized")


class HeartbeatRequest(BaseModel):
    game_server_id: str
    ws_url: Optional[str] = None
    room_codes: list[str] = []


@router.post("/game_servers/heartbeat", dependencies=[Depends(_require_internal_secret)])
async def heartbeat(req: HeartbeatRequest, db: AsyncSession = Depends(get_db)):
    now = datetime.now(timezone.utc)
    reported_room_codes: list[str] = []
    seen_reported_room_codes: set[str] = set()
    for raw_code in req.room_codes:
        room_code = str(raw_code).strip().upper()
        if not room_code or room_code in seen_reported_room_codes:
            continue
        seen_reported_room_codes.add(room_code)
        reported_room_codes.append(room_code)
    ended_room_codes: list[str] = []
    gs = (await db.execute(
        select(GameServer).where(GameServer.game_server_id == req.game_server_id)
    )).scalar_one_or_none()
    if gs:
        gs.last_heartbeat_at = now
        gs.status = "healthy"
        gs.ws_url = str(req.ws_url).strip() or gs.ws_url
    else:
        db.add(GameServer(
            game_server_id=req.game_server_id,
            ws_url=str(req.ws_url).strip() or None,
            last_heartbeat_at=now,
        ))

    # Mark alive rooms (refresh updated_at, claim ownership).
    if reported_room_codes:
        tombstones = (await db.execute(
            select(RoomTombstone.room_code).where(RoomTombstone.room_code.in_(reported_room_codes))
        )).scalars().all()
        tombstone_codes = {str(room_code).strip().upper() for room_code in tombstones}
        rooms = (await db.execute(select(Room).where(Room.room_code.in_(reported_room_codes)))).scalars().all()
        for r in rooms:
            room_code = str(r.room_code).strip().upper()
            if room_code in tombstone_codes:
                ended_room_codes.append(room_code)
                continue
            r.game_server_id = req.game_server_id
            if str(req.ws_url or "").strip():
                r.ws_url = str(req.ws_url).strip()
            # Pending rooms may become active after the game server claims them.
            # Ended rooms must never be revived by heartbeat alone, otherwise stale
            # in-memory room codes can resurrect finished rooms into the directory.
            if r.status == "Pending":
                r.status = "Lobby"
            elif r.status == "Ended":
                ended_room_codes.append(room_code)
            r.updated_at = now
        for room_code in reported_room_codes:
            if room_code in tombstone_codes and room_code not in ended_room_codes:
                ended_room_codes.append(room_code)

    # GC: rooms previously on this game server but no longer present -> Ended.
    stmt = select(Room).where(
        Room.game_server_id == req.game_server_id,
        Room.status.in_(ACTIVE_ROOM_STATUSES),
    )
    if reported_room_codes:
        stmt = stmt.where(~Room.room_code.in_(reported_room_codes))
    stale = (await db.execute(stmt)).scalars().all()
    stale_room_ids: list[str] = []
    for r in stale:
        r.status = "Ended"
        r.updated_at = now
        stale_room_ids.append(str(r.room_id))
    await _mark_room_members_left(db, stale_room_ids, now, "ended")

    await db.commit()
    return {"ok": True, "ended_room_codes": ended_room_codes}


class ActiveRoomOut(BaseModel):
    room_code: str
    status: str
    ws_url: Optional[str] = None


@router.get("/game_servers/{game_server_id}/rooms/active", dependencies=[Depends(_require_internal_secret)])
async def list_active_rooms_for_server(game_server_id: str, db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(Room)
        .where(
            Room.game_server_id == game_server_id,
            Room.status.in_(ACTIVE_ROOM_STATUSES),
        )
        .order_by(Room.updated_at.desc())
    )).scalars().all()
    return {
        "ok": [
            ActiveRoomOut(
                room_code=str(room.room_code),
                status=str(room.status),
                ws_url=str(room.ws_url) if room.ws_url else None,
            ).model_dump()
            for room in rows
        ]
    }


class RoomMemberSyncIn(BaseModel):
    user_id: str
    role: str
    seat_index: Optional[int] = None
    member_status: str = "active"
    generation: int = 1


class RoomDirectorySyncIn(BaseModel):
    room_code: str
    owner_user_id: str
    status: str
    join_policy: str
    password_hash: Optional[str] = None
    config_json: str = "{}"
    ws_url: Optional[str] = None
    members: list[RoomMemberSyncIn] = []


class RoomDirectorySyncRequest(BaseModel):
    ws_url: Optional[str] = None
    rooms: list[RoomDirectorySyncIn] = []


@router.post("/game_servers/{game_server_id}/rooms/sync", dependencies=[Depends(_require_internal_secret)])
async def sync_room_directory(game_server_id: str, req: RoomDirectorySyncRequest, db: AsyncSession = Depends(get_db)):
    now = datetime.now(timezone.utc)
    server_ws_url = str(req.ws_url or "").strip() or None
    accepted_room_codes: list[str] = []
    skipped_ended_room_codes: list[str] = []

    for index, item in enumerate(req.rooms):
        try:
            parse_room_config_json(item.config_json, f"rooms[{index}].config_json")
        except RoomConfigParseError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    gs = (await db.execute(
        select(GameServer).where(GameServer.game_server_id == game_server_id)
    )).scalar_one_or_none()
    if gs:
        gs.last_heartbeat_at = now
        gs.status = "healthy"
        gs.ws_url = server_ws_url or gs.ws_url
    else:
        db.add(GameServer(
            game_server_id=game_server_id,
            ws_url=server_ws_url,
            last_heartbeat_at=now,
        ))

    payload_codes: set[str] = set()
    for item in req.rooms:
        room_code = str(item.room_code).strip().upper()
        if not room_code:
            continue
        payload_codes.add(room_code)

        room = (await db.execute(
            select(Room).where(Room.room_code == room_code)
        )).scalar_one_or_none()
        tombstone = (await db.execute(
            select(RoomTombstone).where(RoomTombstone.room_code == room_code)
        )).scalar_one_or_none()
        if tombstone is not None:
            skipped_ended_room_codes.append(room_code)
            continue
        if room is not None and str(room.status) == "Ended":
            skipped_ended_room_codes.append(room_code)
            continue
        if room is None:
            incoming_password_hash = str(item.password_hash) if item.password_hash else None
            room = Room(
                room_code=room_code,
                owner_user_id=str(item.owner_user_id),
                game_server_id=game_server_id,
                status=str(item.status),
                join_policy=str(item.join_policy),
                password_hash=incoming_password_hash,
                config_json=str(item.config_json),
                ws_url=str(item.ws_url or "").strip() or server_ws_url,
            )
            db.add(room)
            await db.flush()
        else:
            incoming_join_policy = str(item.join_policy)
            incoming_password_hash = str(item.password_hash) if item.password_hash else None
            room.owner_user_id = str(item.owner_user_id)
            room.game_server_id = game_server_id
            room.status = str(item.status)
            room.join_policy = incoming_join_policy
            if incoming_password_hash is not None:
                room.password_hash = incoming_password_hash
            elif incoming_join_policy != "password":
                room.password_hash = None
            room.config_json = str(item.config_json)
            room.ws_url = str(item.ws_url or "").strip() or server_ws_url or room.ws_url
            room.updated_at = now
        accepted_room_codes.append(room_code)

        existing_members = (await db.execute(
            select(RoomMember).where(
                RoomMember.room_id == room.room_id,
                RoomMember.left_at.is_(None),
            )
        )).scalars().all()
        existing_by_user = {str(member.user_id): member for member in existing_members}
        payload_users: set[str] = set()

        for member_in in item.members:
            user_id = str(member_in.user_id).strip()
            if not user_id:
                continue
            payload_users.add(user_id)
            member = existing_by_user.get(user_id)
            if member is None:
                db.add(RoomMember(
                    room_id=room.room_id,
                    user_id=user_id,
                    role=str(member_in.role),
                    seat_index=member_in.seat_index,
                    member_status=str(member_in.member_status or "active"),
                    generation=max(1, int(member_in.generation or 1)),
                    left_at=None,
                ))
                continue
            member.role = str(member_in.role)
            member.seat_index = member_in.seat_index
            member.member_status = str(member_in.member_status or "active")
            member.generation = max(int(member.generation or 1), max(1, int(member_in.generation or 1)))
            member.left_at = None

        for member in existing_members:
            if str(member.user_id) in payload_users:
                continue
            member.left_at = now
            member.member_status = "left"

    stale_rooms = (await db.execute(
        select(Room).where(
            Room.game_server_id == game_server_id,
            Room.status.in_(ACTIVE_ROOM_STATUSES),
        )
    )).scalars().all()
    stale_room_ids: list[str] = []
    for room in stale_rooms:
        if str(room.room_code) in payload_codes:
            continue
        room.status = "Ended"
        room.updated_at = now
        stale_room_ids.append(str(room.room_id))
    await _mark_room_members_left(db, stale_room_ids, now, "ended")

    await db.commit()
    return {
        "ok": True,
        "accepted_room_codes": accepted_room_codes,
        "skipped_ended_room_codes": skipped_ended_room_codes,
    }


class ParticipantIn(BaseModel):
    user_id: str
    role: str
    seat_index: Optional[int] = None
    result: Optional[str] = None
    score_json: Optional[str] = None


class FinalizeRequest(BaseModel):
    room_id: Optional[str] = None
    room_code: Optional[str] = None
    status: str = "completed"
    started_at: Optional[str] = None
    ended_at: Optional[str] = None
    duration_sec: Optional[int] = None
    player_count: int = 0
    seed: Optional[str] = None
    schema_version: Optional[str] = None
    game_version: Optional[str] = None
    final_hash: Optional[str] = None
    summary_json: Optional[str] = None
    participants: list[ParticipantIn] = []
    replay_uri: Optional[str] = None
    replay_archive_json: Optional[str] = None
    replay_checksum: Optional[str] = None
    replay_size_bytes: Optional[int] = None


class RoundArtifactUploadRequest(BaseModel):
    room_code: str
    round_number: int = Field(ge=0)
    snapshot_kind: str = SNAPSHOT_KIND_ROUND_END
    state_hash: Optional[str] = None
    archive_json: Optional[str] = None
    archive_checksum: Optional[str] = None
    archive_size_bytes: Optional[int] = Field(default=None, ge=0)
    map_snapshot_png_base64: Optional[str] = None
    map_snapshot_checksum: Optional[str] = None
    map_snapshot_size_bytes: Optional[int] = Field(default=None, ge=0)


def _normalize_room_code(value: Optional[str]) -> str:
    return str(value or "").strip().upper()


def _normalize_snapshot_kind(value: str) -> str:
    kind = str(value or SNAPSHOT_KIND_ROUND_END).strip()
    if kind not in (SNAPSHOT_KIND_ROUND_END, SNAPSHOT_KIND_GAME_OVER):
        raise HTTPException(status_code=400, detail="invalid snapshot_kind")
    return kind


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _normalize_checksum(value: Optional[str]) -> str:
    text = str(value or "").strip().lower()
    if text.startswith("sha256:"):
        text = text[len("sha256:"):]
    return text


def _validate_payload_integrity(
    label: str,
    data: bytes,
    expected_size: Optional[int],
    expected_checksum: Optional[str],
) -> str:
    if expected_size is not None and int(expected_size) != len(data):
        raise HTTPException(status_code=400, detail=f"{label} size mismatch")
    computed = _sha256_hex(data)
    provided = _normalize_checksum(expected_checksum)
    if provided and provided != computed:
        raise HTTPException(status_code=400, detail=f"{label} checksum mismatch")
    return computed


async def _find_match_id_for_room(db: AsyncSession, room_code: str) -> Optional[str]:
    match = (await db.execute(
        select(Match)
        .where(Match.room_code == room_code)
        .order_by(Match.created_at.desc())
    )).scalars().first()
    if match is None:
        return None
    return str(match.match_id)


async def _upsert_match_artifact(
    db: AsyncSession,
    *,
    room_code: str,
    artifact_type: str,
    snapshot_kind: str,
    round_number: int,
    state_hash: Optional[str],
    storage_uri: str,
    mime_type: str,
    checksum: Optional[str],
    size_bytes: int,
    match_id: Optional[str],
) -> MatchArtifact:
    stmt = select(MatchArtifact).where(
        MatchArtifact.room_code == room_code,
        MatchArtifact.artifact_type == artifact_type,
    )
    if artifact_type == ARTIFACT_TYPE_MAP_SNAPSHOT:
        stmt = stmt.where(
            MatchArtifact.snapshot_kind == snapshot_kind,
            MatchArtifact.round_number == round_number,
        )
    artifact = (await db.execute(stmt)).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if artifact is None:
        artifact = MatchArtifact(
            match_id=match_id,
            room_code=room_code,
            artifact_type=artifact_type,
            snapshot_kind=snapshot_kind,
            round_number=round_number,
            state_hash=state_hash,
            storage_uri=storage_uri,
            mime_type=mime_type,
            checksum=checksum,
            size_bytes=size_bytes,
            created_at=now,
            updated_at=now,
        )
        db.add(artifact)
        await db.flush()
        return artifact

    artifact.match_id = artifact.match_id or match_id
    artifact.snapshot_kind = snapshot_kind
    artifact.round_number = round_number
    artifact.state_hash = state_hash
    artifact.storage_uri = storage_uri
    artifact.mime_type = mime_type
    artifact.checksum = checksum
    artifact.size_bytes = size_bytes
    artifact.updated_at = now
    return artifact


@router.post("/matches/round_artifacts", dependencies=[Depends(_require_internal_secret)])
async def upload_round_artifacts(req: RoundArtifactUploadRequest, db: AsyncSession = Depends(get_db)):
    room_code = _normalize_room_code(req.room_code)
    if not room_code:
        raise HTTPException(status_code=400, detail="room_code required")
    snapshot_kind = _normalize_snapshot_kind(req.snapshot_kind)
    round_number = max(0, int(req.round_number))
    state_hash = str(req.state_hash or "").strip() or None
    match_id = await _find_match_id_for_room(db, room_code)
    artifacts: list[dict] = []

    archive_json = str(req.archive_json or "")
    if archive_json.strip():
        archive_bytes = archive_json.encode("utf-8")
        checksum = _validate_payload_integrity(
            "archive",
            archive_bytes,
            req.archive_size_bytes,
            req.archive_checksum,
        )
        try:
            storage_uri = save_local_match_artifact(f"rooms/{room_code}/latest_autosave.json", archive_bytes)
        except (OSError, ValueError) as exc:
            raise HTTPException(status_code=500, detail=f"failed to persist archive artifact: {exc}") from exc
        artifact = await _upsert_match_artifact(
            db,
            room_code=room_code,
            artifact_type=ARTIFACT_TYPE_LATEST_AUTOSAVE,
            snapshot_kind=snapshot_kind,
            round_number=round_number,
            state_hash=state_hash,
            storage_uri=storage_uri,
            mime_type="application/json",
            checksum=checksum,
            size_bytes=len(archive_bytes),
            match_id=match_id,
        )
        artifacts.append({"id": artifact.id, "artifact_type": artifact.artifact_type})

    snapshot_b64 = str(req.map_snapshot_png_base64 or "").strip()
    if snapshot_b64:
        try:
            png_bytes = base64.b64decode(snapshot_b64, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise HTTPException(status_code=400, detail="map snapshot base64 invalid") from exc
        if not png_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
            raise HTTPException(status_code=400, detail="map snapshot must be png")
        checksum = _validate_payload_integrity(
            "map_snapshot",
            png_bytes,
            req.map_snapshot_size_bytes,
            req.map_snapshot_checksum,
        )
        filename = f"round_{round_number:04d}_{snapshot_kind}.png"
        try:
            storage_uri = save_local_match_artifact(f"rooms/{room_code}/map_snapshots/{filename}", png_bytes)
        except (OSError, ValueError) as exc:
            raise HTTPException(status_code=500, detail=f"failed to persist map snapshot: {exc}") from exc
        artifact = await _upsert_match_artifact(
            db,
            room_code=room_code,
            artifact_type=ARTIFACT_TYPE_MAP_SNAPSHOT,
            snapshot_kind=snapshot_kind,
            round_number=round_number,
            state_hash=state_hash,
            storage_uri=storage_uri,
            mime_type="image/png",
            checksum=checksum,
            size_bytes=len(png_bytes),
            match_id=match_id,
        )
        artifacts.append({"id": artifact.id, "artifact_type": artifact.artifact_type})

    if not artifacts:
        raise HTTPException(status_code=400, detail="no artifacts uploaded")

    await db.commit()
    return {"ok": True, "artifacts": artifacts}


@router.post("/matches/finalize", dependencies=[Depends(_require_internal_secret)])
async def finalize(req: FinalizeRequest, db: AsyncSession = Depends(get_db)):
    started = datetime.fromisoformat(req.started_at) if req.started_at else None
    ended = datetime.fromisoformat(req.ended_at) if req.ended_at else None
    room_code = _normalize_room_code(req.room_code) or req.room_code
    m = Match(
        room_id=req.room_id, room_code=room_code, status=req.status,
        started_at=started, ended_at=ended, duration_sec=req.duration_sec,
        player_count=req.player_count, seed=req.seed,
        schema_version=req.schema_version, game_version=req.game_version,
        final_hash=req.final_hash, summary_json=req.summary_json,
    )
    db.add(m)
    await db.flush()

    for p in req.participants:
        db.add(MatchParticipant(
            match_id=m.match_id, user_id=p.user_id, role=p.role,
            seat_index=p.seat_index, result=p.result, score_json=p.score_json,
        ))

    replay_storage_uri: Optional[str] = req.replay_uri
    replay_archive_json = str(req.replay_archive_json or "")
    if replay_archive_json.strip() != "":
        try:
            replay_storage_uri = save_local_replay_archive(m.match_id, replay_archive_json)
        except OSError as exc:
            raise HTTPException(status_code=500, detail=f"failed to persist replay archive: {exc}") from exc

    if replay_storage_uri:
        db.add(MatchReplay(
            match_id=m.match_id, storage_uri=replay_storage_uri,
            checksum=req.replay_checksum, size_bytes=req.replay_size_bytes,
        ))

    if room_code:
        artifact_rows = (await db.execute(
            select(MatchArtifact).where(
                MatchArtifact.room_code == room_code,
                MatchArtifact.match_id.is_(None),
            )
        )).scalars().all()
        for artifact in artifact_rows:
            artifact.match_id = m.match_id

    await db.commit()
    return {"match_id": m.match_id}
