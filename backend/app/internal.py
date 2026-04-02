from __future__ import annotations

from datetime import datetime, timezone
import hmac
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.models import GameServer, Room, RoomMember, RoomTombstone, Match, MatchParticipant, MatchReplay
from app.replay_storage import save_local_replay_archive

router = APIRouter(prefix="/internal", tags=["internal"])
ACTIVE_ROOM_STATUSES = ("Lobby", "InGame")


async def _mark_room_members_left(db: AsyncSession, room_ids: list[str], now: datetime) -> None:
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
    if req.room_codes:
        rooms = (await db.execute(select(Room).where(Room.room_code.in_(req.room_codes)))).scalars().all()
        for r in rooms:
            r.game_server_id = req.game_server_id
            if str(req.ws_url or "").strip():
                r.ws_url = str(req.ws_url).strip()
            # Allow revival if the room became active again.
            if r.status in {"Ended", "Pending"}:
                r.status = "Lobby"
            r.updated_at = now

    # GC: rooms previously on this game server but no longer present -> Ended.
    stmt = select(Room).where(Room.game_server_id == req.game_server_id, Room.status != "Ended")
    if req.room_codes:
        stmt = stmt.where(~Room.room_code.in_(req.room_codes))
    stale = (await db.execute(stmt)).scalars().all()
    stale_room_ids: list[str] = []
    for r in stale:
        r.status = "Ended"
        r.updated_at = now
        stale_room_ids.append(str(r.room_id))
    await _mark_room_members_left(db, stale_room_ids, now)

    await db.commit()
    return {"ok": True}


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
            room = Room(
                room_code=room_code,
                owner_user_id=str(item.owner_user_id),
                game_server_id=game_server_id,
                status=str(item.status),
                join_policy=str(item.join_policy),
                password_hash=str(item.password_hash) if item.password_hash else None,
                config_json=str(item.config_json),
                ws_url=str(item.ws_url or "").strip() or server_ws_url,
            )
            db.add(room)
            await db.flush()
        else:
            room.owner_user_id = str(item.owner_user_id)
            room.game_server_id = game_server_id
            room.status = str(item.status)
            room.join_policy = str(item.join_policy)
            room.password_hash = str(item.password_hash) if item.password_hash else None
            room.config_json = str(item.config_json)
            room.ws_url = str(item.ws_url or "").strip() or server_ws_url or room.ws_url
            room.updated_at = now
        accepted_room_codes.append(room_code)

        existing_members = (await db.execute(
            select(RoomMember).where(
                RoomMember.room_id == room.room_id,
                RoomMember.left_at.is_(None),
                RoomMember.role != "spectator",
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
                    left_at=None,
                ))
                continue
            member.role = str(member_in.role)
            member.seat_index = member_in.seat_index
            member.left_at = None

        for member in existing_members:
            if str(member.user_id) in payload_users:
                continue
            member.left_at = now

    stale_rooms = (await db.execute(
        select(Room).where(
            Room.game_server_id == game_server_id,
            Room.status != "Ended",
        )
    )).scalars().all()
    stale_room_ids: list[str] = []
    for room in stale_rooms:
        if str(room.room_code) in payload_codes:
            continue
        room.status = "Ended"
        room.updated_at = now
        stale_room_ids.append(str(room.room_id))
    await _mark_room_members_left(db, stale_room_ids, now)

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


@router.post("/matches/finalize", dependencies=[Depends(_require_internal_secret)])
async def finalize(req: FinalizeRequest, db: AsyncSession = Depends(get_db)):
    started = datetime.fromisoformat(req.started_at) if req.started_at else None
    ended = datetime.fromisoformat(req.ended_at) if req.ended_at else None
    m = Match(
        room_id=req.room_id, room_code=req.room_code, status=req.status,
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

    await db.commit()
    return {"match_id": m.match_id}
