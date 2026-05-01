from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, _is_guest_user, _resolve_display_name
from app.config import settings
from app.connect_token import issue_connect_token
from app.db import get_db
from app.models import GameServer, Room, RoomMember, Session, User
from app.room_config import RoomConfigParseError, parse_room_config_json

router = APIRouter(prefix="/v1/rooms", tags=["rooms"])

ROOM_STATUS_PENDING = "Pending"
ROOM_LISTABLE_STATUSES = ("Lobby", "InGame")
RESUMABLE_MEMBER_STATUSES = ("active", "reconnecting")


def _resolve_default_ws_url() -> str:
    ws_url = str(settings.default_ws_url).strip()
    if ws_url:
        return ws_url
    return "ws://localhost:7000"


def _healthy_game_server_cutoff() -> datetime:
    return datetime.now(timezone.utc) - timedelta(seconds=75)


async def _get_latest_healthy_game_server(db: AsyncSession) -> Optional[GameServer]:
    return (await db.execute(
        select(GameServer)
        .where(GameServer.last_heartbeat_at >= _healthy_game_server_cutoff())
        .order_by(GameServer.last_heartbeat_at.desc())
        .limit(1)
    )).scalar_one_or_none()


async def _resolve_room_connection_target(db: AsyncSession, room: Room) -> tuple[Optional[str], str]:
    ws_url = str(room.ws_url or "").strip()
    game_server_id = str(room.game_server_id or "").strip()
    room_status = str(room.status or "").strip()

    if game_server_id:
        gs = (await db.execute(
            select(GameServer).where(
                GameServer.game_server_id == game_server_id,
                GameServer.last_heartbeat_at >= _healthy_game_server_cutoff(),
            )
        )).scalar_one_or_none()
        if gs is not None:
            latest_ws_url = str(gs.ws_url or "").strip()
            if latest_ws_url and latest_ws_url != ws_url:
                room.ws_url = latest_ws_url
                ws_url = latest_ws_url
            return game_server_id, ws_url or _resolve_default_ws_url()
        # Active rooms must stay pinned to their assigned game server. Falling
        # back to another healthy server would issue a valid token for a room
        # that does not actually exist on that process.
        if room_status != ROOM_STATUS_PENDING:
            return game_server_id, ws_url or _resolve_default_ws_url()

    latest = await _get_latest_healthy_game_server(db)
    if latest is None:
        return (game_server_id or None), ws_url or _resolve_default_ws_url()

    room.game_server_id = str(latest.game_server_id)
    latest_ws_url = str(latest.ws_url or "").strip()
    if latest_ws_url:
        room.ws_url = latest_ws_url
        ws_url = latest_ws_url
    elif not ws_url:
        ws_url = _resolve_default_ws_url()
        room.ws_url = ws_url
    return str(room.game_server_id), ws_url or _resolve_default_ws_url()


async def _get_room_for_update(db: AsyncSession, room_code: str) -> Optional[Room]:
    return (await db.execute(
        select(Room).where(Room.room_code == room_code).with_for_update()
    )).scalar_one_or_none()


async def _get_active_room_member(db: AsyncSession, room_id: str, user_id: str) -> Optional[RoomMember]:
    return (await db.execute(
        select(RoomMember).where(
            RoomMember.room_id == room_id,
            RoomMember.user_id == user_id,
            RoomMember.left_at.is_(None),
            RoomMember.member_status != "left",
            RoomMember.member_status != "ended",
        )
    )).scalar_one_or_none()


def _parse_request_room_config_json(config_json: Optional[str]) -> dict:
    try:
        return parse_room_config_json(config_json, "config_json")
    except RoomConfigParseError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _parse_stored_room_config_json(config_json: Optional[str], room_code: str = "") -> dict:
    source = "room.config_json"
    code = str(room_code or "").strip().upper()
    if code:
        source = "room %s config_json" % code
    try:
        return parse_room_config_json(config_json, source)
    except RoomConfigParseError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


def _is_resume_room_config(config: dict) -> bool:
    return str(config.get("room_mode", "")).strip() == "resume_archive"


def _coerce_optional_int(value) -> Optional[int]:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return int(value)
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


def _get_resume_participant_bindings(config: dict) -> list[dict]:
    raw = config.get("resume_participant_bindings")
    if not isinstance(raw, list):
        return []
    out: list[dict] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        user_id = str(item.get("user_id", "")).strip()
        if not user_id:
            continue
        seat_index = _coerce_optional_int(item.get("seat_index"))
        if seat_index is None:
            seat_index = _coerce_optional_int(item.get("player_id"))
        if seat_index is None or seat_index < 0:
            continue
        out.append({
            "user_id": user_id,
            "seat_index": int(seat_index),
            "role": "host" if str(item.get("role", "")).strip() == "host" else "player",
        })
    return out


def _find_resume_binding_for_user_id(config: dict, user_id: str) -> Optional[dict]:
    target_user_id = str(user_id or "").strip()
    if not target_user_id:
        return None
    for item in _get_resume_participant_bindings(config):
        if str(item.get("user_id", "")).strip() == target_user_id:
            return dict(item)
    return None


def _resolve_resume_binding_seat_index(
    config: dict,
    user_id: str,
    occupied_seats: set[int] | None = None,
    allow_same_user_existing_seat: Optional[int] = None,
) -> Optional[int]:
    binding = _find_resume_binding_for_user_id(config, user_id)
    if binding is None:
        return None
    seat_index = _coerce_optional_int(binding.get("seat_index"))
    if seat_index is None or seat_index < 0:
        return None
    desired_player_count = _coerce_optional_int(config.get("desired_player_count"))
    if desired_player_count is not None and desired_player_count > 0 and seat_index >= desired_player_count:
        return None
    taken = occupied_seats or set()
    if seat_index in taken and seat_index != allow_same_user_existing_seat:
        return None
    return int(seat_index)


def _issue_member_connect_token(
    member: RoomMember,
    room: Room,
    display_name: str,
    include_host_access: bool = False,
    config_json: str | None = None,
) -> str:
    current_generation = max(1, int(member.generation or 1))
    member.generation = current_generation + 1
    room_cfg = _parse_stored_room_config_json(room.config_json, room.room_code)
    effective_config_json = config_json
    if effective_config_json is None and _is_resume_room_config(room_cfg):
        effective_config_json = str(room.config_json or "{}")
    return issue_connect_token(
        str(member.user_id),
        str(room.room_code),
        str(member.role),
        display_name=display_name,
        seat_index=member.seat_index,
        generation=current_generation,
        config_json=effective_config_json,
        join_policy=str(room.join_policy) if include_host_access else None,
        password_hash=str(room.password_hash) if include_host_access and room.password_hash else None,
    )


class CreateRoomRequest(BaseModel):
    session_id: str
    config_json: str = "{}"
    password: str = ""


class RoomResponse(BaseModel):
    room_code: str
    ws_url: str
    connect_token: str


class RoomInfo(BaseModel):
    room_code: str
    status: str
    owner_user_id: str
    join_policy: str
    config_json: Optional[str]


class RoomSummary(BaseModel):
    room_code: str
    status: str
    join_policy: str
    password_required: bool
    desired_player_count: int
    player_count: int
    allow_spectators: bool
    host_name: str


@router.get("", response_model=list[RoomSummary])
async def list_rooms(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    status: Optional[str] = None,
    limit: int = 50,
    active_only: bool = True,
):
    # Auth required (avoid open directory enumeration)
    await get_current_user(db=db, session_id=session_id)

    lim = int(limit)
    if lim <= 0:
        lim = 50
    lim = min(lim, 200)

    stmt = select(Room)
    if active_only:
        # Only show rooms that are confirmed alive by a recent game server heartbeat.
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=75)
        stmt = (
            stmt.join(GameServer, Room.game_server_id == GameServer.game_server_id)
            .where(
                Room.status.in_(ROOM_LISTABLE_STATUSES),
                GameServer.last_heartbeat_at >= cutoff,
            )
        )

    stmt = stmt.order_by(Room.updated_at.desc()).limit(lim)
    if status:
        stmt = stmt.where(Room.status == status)

    rooms = (await db.execute(stmt)).scalars().all()

    counts: dict[str, int] = {}
    owner_display_name: dict[str, str] = {}
    room_ids = [r.room_id for r in rooms]
    if room_ids:
        rows = (await db.execute(
            select(RoomMember.room_id, func.count())
            .where(
                RoomMember.room_id.in_(room_ids),
                RoomMember.left_at.is_(None),
                RoomMember.role.in_(("host", "player")),
                RoomMember.member_status != "left",
                RoomMember.member_status != "ended",
            )
            .group_by(RoomMember.room_id)
        )).all()
        counts = {rid: int(c) for (rid, c) in rows}
    owner_ids = list({str(r.owner_user_id) for r in rooms if str(r.owner_user_id).strip()})
    if owner_ids:
        owners = (await db.execute(
            select(User.user_id, User.display_name).where(User.user_id.in_(owner_ids))
        )).all()
        owner_display_name = {
            str(uid): str(display_name).strip()
            for uid, display_name in owners
            if str(display_name or "").strip()
        }

    out: list[RoomSummary] = []
    for r in rooms:
        cfg = _parse_stored_room_config_json(r.config_json, r.room_code)

        desired = int(cfg.get("desired_player_count", 0) or 0)
        allow_spectators = bool(cfg.get("allow_spectators", True))
        password_required = r.join_policy == "password" and bool(str(r.password_hash or "").strip())
        host_name = owner_display_name.get(str(r.owner_user_id), (r.owner_user_id or "")[:8])

        out.append(RoomSummary(
            room_code=r.room_code,
            status=r.status,
            join_policy=r.join_policy,
            password_required=password_required,
            desired_player_count=desired,
            player_count=int(counts.get(r.room_id, 0)),
            allow_spectators=allow_spectators,
            host_name=host_name,
        ))
    return out


@router.post("", response_model=RoomResponse)
async def create_room(req: CreateRoomRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, _ = _resolve_display_name(user, is_guest)

    preferred_server = await _get_latest_healthy_game_server(db)
    preferred_server_id = str(preferred_server.game_server_id) if preferred_server is not None else None
    preferred_ws_url = str(preferred_server.ws_url or "").strip() if preferred_server is not None else ""
    if not preferred_ws_url:
        preferred_ws_url = _resolve_default_ws_url()

    room_cfg = _parse_request_room_config_json(req.config_json)
    is_resume_room = _is_resume_room_config(room_cfg)

    from app.auth import _hash_password
    room = Room(
        owner_user_id=sess.user_id,
        game_server_id=preferred_server_id,
        status=ROOM_STATUS_PENDING,
        config_json=req.config_json,
        ws_url=preferred_ws_url,
        join_policy="password" if req.password else "public",
        password_hash=_hash_password(req.password) if req.password else None,
    )
    db.add(room)
    await db.flush()

    host_seat_index = 0
    if is_resume_room:
        host_seat_index = _resolve_resume_binding_seat_index(room_cfg, sess.user_id)
    host_member = RoomMember(
        room_id=room.room_id,
        user_id=sess.user_id,
        role="host",
        seat_index=host_seat_index,
        member_status="active",
    )
    db.add(host_member)
    token = _issue_member_connect_token(host_member, room, display_name, True, str(req.config_json))
    await db.commit()
    return RoomResponse(room_code=room.room_code, ws_url=str(room.ws_url), connect_token=token)


class JoinRequest(BaseModel):
    session_id: str
    password: str = ""


class ResumeRequest(BaseModel):
    session_id: str


@router.post("/{room_code}/join", response_model=RoomResponse)
async def join_room(room_code: str, req: JoinRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, name_changed = _resolve_display_name(user, is_guest)
    room = await _get_room_for_update(db, room_code)
    if not room:
        raise HTTPException(404, "room not found")
    if str(room.status) == ROOM_STATUS_PENDING:
        raise HTTPException(409, "room not ready")
    if str(room.status) == "Ended":
        raise HTTPException(409, "room already ended")
    if room.join_policy == "password":
        from app.auth import _verify_password
        if not room.password_hash or not _verify_password(req.password, room.password_hash):
            raise HTTPException(403, "wrong password")
    _, room_ws_url = await _resolve_room_connection_target(db, room)

    room_cfg = _parse_stored_room_config_json(room.config_json, room.room_code)
    is_resume_room = _is_resume_room_config(room_cfg)

    # Check already joined
    existing = await _get_active_room_member(db, room.room_id, sess.user_id)
    if existing:
        if str(existing.member_status or "").strip() == "forfeited":
            raise HTTPException(409, "room membership forfeited; use spectate")
        if is_resume_room and existing.seat_index is None:
            members = (await db.execute(
                select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.left_at.is_(None))
            )).scalars().all()
            occupied = {
                int(m.seat_index) for m in members
                if m.seat_index is not None and str(m.user_id) != str(existing.user_id)
            }
            resolved_existing_seat = _resolve_resume_binding_seat_index(
                room_cfg,
                sess.user_id,
                occupied,
            )
            if resolved_existing_seat is not None:
                existing.seat_index = resolved_existing_seat
        token = _issue_member_connect_token(existing, room, display_name, str(existing.role) == "host")
        await db.commit()
        return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)

    if str(room.status) != "Lobby":
        raise HTTPException(409, "room already in game")

    desired_player_count = int(room_cfg.get("desired_player_count", 0) or 0)

    last_integrity_error = False
    for _attempt in range(2):
        members = (await db.execute(
            select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.left_at.is_(None))
        )).scalars().all()
        if is_resume_room:
            active_participants = [
                m for m in members
                if str(m.role or "").strip() in {"host", "player"}
                and str(m.member_status or "").strip() not in {"left", "ended"}
            ]
            if desired_player_count > 0 and len(active_participants) >= desired_player_count:
                raise HTTPException(409, "room is full")
            taken = {int(m.seat_index) for m in members if m.seat_index is not None}
            seat = _resolve_resume_binding_seat_index(room_cfg, sess.user_id, taken)
        else:
            taken = {m.seat_index for m in members if m.seat_index is not None}
            if desired_player_count > 0 and len(taken) >= desired_player_count:
                raise HTTPException(409, "room is full")
            seat = 0
            while seat in taken:
                seat += 1
            if desired_player_count > 0 and seat >= desired_player_count:
                raise HTTPException(409, "room is full")

        member = RoomMember(
            room_id=room.room_id,
            user_id=sess.user_id,
            role="player",
            seat_index=seat,
            member_status="active",
        )
        db.add(member)
        try:
            token = _issue_member_connect_token(member, room, display_name)
            await db.commit()
            return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)
        except IntegrityError:
            await db.rollback()
            last_integrity_error = True
            room = await _get_room_for_update(db, room_code)
            if room is None:
                raise HTTPException(404, "room not found")
            existing = await _get_active_room_member(db, room.room_id, sess.user_id)
            if existing is not None:
                if is_resume_room and existing.seat_index is None:
                    members = (await db.execute(
                        select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.left_at.is_(None))
                    )).scalars().all()
                    occupied = {
                        int(m.seat_index) for m in members
                        if m.seat_index is not None and str(m.user_id) != str(existing.user_id)
                    }
                    resolved_existing_seat = _resolve_resume_binding_seat_index(
                        room_cfg,
                        sess.user_id,
                        occupied,
                    )
                    if resolved_existing_seat is not None:
                        existing.seat_index = resolved_existing_seat
                token = _issue_member_connect_token(existing, room, display_name, str(existing.role) == "host")
                await db.commit()
                return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)

    if last_integrity_error:
        raise HTTPException(409, "room is full")
    raise HTTPException(409, "join failed")


@router.post("/{room_code}/resume", response_model=RoomResponse)
async def resume_room(room_code: str, req: ResumeRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, name_changed = _resolve_display_name(user, is_guest)

    room = await _get_room_for_update(db, room_code)
    if not room:
        raise HTTPException(404, "room not found")
    if str(room.status) == "Ended":
        raise HTTPException(409, "room already ended")
    _, room_ws_url = await _resolve_room_connection_target(db, room)

    room_cfg = _parse_stored_room_config_json(room.config_json, room.room_code)
    is_resume_room = _is_resume_room_config(room_cfg)

    existing = await _get_active_room_member(db, room.room_id, sess.user_id)
    if existing is None:
        raise HTTPException(403, "room membership not found")
    if str(existing.member_status or "").strip() not in RESUMABLE_MEMBER_STATUSES:
        raise HTTPException(409, "room membership is not resumable")

    role = str(existing.role)
    seat_index = existing.seat_index
    if seat_index is None and is_resume_room:
        members = (await db.execute(
            select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.left_at.is_(None))
        )).scalars().all()
        occupied = {
            int(m.seat_index) for m in members
            if m.seat_index is not None and str(m.user_id) != str(existing.user_id)
        }
        resolved_seat = _resolve_resume_binding_seat_index(room_cfg, sess.user_id, occupied)
        if resolved_seat is not None:
            existing.seat_index = resolved_seat
            seat_index = resolved_seat
    if role in {"host", "player"} and seat_index is None and not is_resume_room:
        raise HTTPException(409, "seat missing for resumable role")

    token = _issue_member_connect_token(existing, room, display_name, role == "host")
    await db.commit()
    return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)


@router.post("/{room_code}/spectate", response_model=RoomResponse)
async def spectate_room(room_code: str, req: JoinRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, name_changed = _resolve_display_name(user, is_guest)
    room = await _get_room_for_update(db, room_code)
    if not room:
        raise HTTPException(404, "room not found")
    if str(room.status) == ROOM_STATUS_PENDING:
        raise HTTPException(409, "room not ready")
    if str(room.status) == "Ended":
        raise HTTPException(409, "room already ended")
    _, room_ws_url = await _resolve_room_connection_target(db, room)

    existing = await _get_active_room_member(db, room.room_id, sess.user_id)
    if existing:
        if name_changed:
            await db.commit()
        if str(existing.member_status or "").strip() == "forfeited":
            token = issue_connect_token(
                sess.user_id,
                room.room_code,
                "spectator",
                display_name=display_name,
                seat_index=None,
            )
            await db.commit()
            return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)
        token = issue_connect_token(
            sess.user_id, room.room_code, existing.role,
            display_name=display_name,
            seat_index=existing.seat_index,
        )
        await db.commit()
        return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)

    if str(room.status) != "InGame":
        raise HTTPException(409, "room is not in game")

    cfg = _parse_stored_room_config_json(room.config_json, room.room_code)
    allow_spectators = bool(cfg.get("allow_spectators", True))
    if not allow_spectators:
        raise HTTPException(403, "spectators not allowed")

    db.add(RoomMember(
        room_id=room.room_id,
        user_id=sess.user_id,
        role="spectator",
        seat_index=None,
        member_status="active",
    ))
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        room = await _get_room_for_update(db, room_code)
        if room is None:
            raise HTTPException(404, "room not found")
        existing = await _get_active_room_member(db, room.room_id, sess.user_id)
        if existing is None:
            raise HTTPException(409, "spectate failed")
        token = issue_connect_token(
            sess.user_id, room.room_code, existing.role,
            display_name=display_name,
            seat_index=existing.seat_index,
        )
        await db.commit()
        return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)
    token = issue_connect_token(sess.user_id, room.room_code, "spectator", display_name=display_name)
    return RoomResponse(room_code=room.room_code, ws_url=room_ws_url, connect_token=token)


@router.get("/{room_code}", response_model=RoomInfo)
async def get_room(room_code: str, db: AsyncSession = Depends(get_db)):
    room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
    if not room:
        raise HTTPException(404, "room not found")
    return RoomInfo(
        room_code=room.room_code, status=room.status,
        owner_user_id=room.owner_user_id, join_policy=room.join_policy,
        config_json=room.config_json,
    )
