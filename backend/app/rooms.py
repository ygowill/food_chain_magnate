from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, _is_guest_user, _resolve_display_name
from app.config import settings
from app.connect_token import issue_connect_token
from app.db import get_db
from app.models import GameServer, Room, RoomMember, Session, User

router = APIRouter(prefix="/v1/rooms", tags=["rooms"])


def _resolve_default_ws_url() -> str:
    ws_url = str(settings.default_ws_url).strip()
    if ws_url:
        return ws_url
    return "ws://localhost:7000"


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
    config_json: str | None


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
    status: str | None = None,
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
                Room.status != "Ended",
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
                RoomMember.seat_index.is_not(None),
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

    import json
    out: list[RoomSummary] = []
    for r in rooms:
        cfg = {}
        if r.config_json:
            try:
                cfg = json.loads(r.config_json)
            except Exception:
                cfg = {}

        desired = int(cfg.get("desired_player_count", 0) or 0)
        allow_spectators = bool(cfg.get("allow_spectators", True))
        password_required = r.join_policy == "password"
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

    from app.auth import _hash_password
    room = Room(
        owner_user_id=sess.user_id,
        config_json=req.config_json,
        ws_url=_resolve_default_ws_url(),
        join_policy="password" if req.password else "public",
        password_hash=_hash_password(req.password) if req.password else None,
    )
    db.add(room)
    await db.flush()

    db.add(RoomMember(room_id=room.room_id, user_id=sess.user_id, role="host", seat_index=0))
    await db.commit()

    token = issue_connect_token(
        sess.user_id,
        room.room_code,
        "host",
        display_name=display_name,
        seat_index=0,
        config_json=req.config_json,
    )
    return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)


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
    room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
    if not room:
        raise HTTPException(404, "room not found")
    if room.join_policy == "password":
        from app.auth import _verify_password
        if not room.password_hash or not _verify_password(req.password, room.password_hash):
            raise HTTPException(403, "wrong password")

    # Check already joined
    existing = (await db.execute(
        select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.user_id == sess.user_id, RoomMember.left_at.is_(None))
    )).scalar_one_or_none()
    if existing:
        if name_changed:
            await db.commit()
        token = issue_connect_token(
            sess.user_id, room.room_code, existing.role,
            display_name=display_name,
            seat_index=existing.seat_index,
        )
        return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)

    # Assign next seat
    members = (await db.execute(
        select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.left_at.is_(None))
    )).scalars().all()
    taken = {m.seat_index for m in members if m.seat_index is not None}
    seat = 0
    while seat in taken:
        seat += 1

    db.add(RoomMember(room_id=room.room_id, user_id=sess.user_id, role="player", seat_index=seat))
    await db.commit()
    token = issue_connect_token(sess.user_id, room.room_code, "player", display_name=display_name, seat_index=seat)
    return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)


@router.post("/{room_code}/resume", response_model=RoomResponse)
async def resume_room(room_code: str, req: ResumeRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, name_changed = _resolve_display_name(user, is_guest)

    room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
    if not room:
        raise HTTPException(404, "room not found")
    if str(room.status) == "Ended":
        raise HTTPException(409, "room already ended")

    existing = (await db.execute(
        select(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.user_id == sess.user_id,
            RoomMember.left_at.is_(None),
        )
    )).scalar_one_or_none()
    if existing is None:
        raise HTTPException(403, "room membership not found")

    role = str(existing.role)
    seat_index = existing.seat_index
    if role in {"host", "player"} and seat_index is None:
        raise HTTPException(409, "seat missing for resumable role")

    if name_changed:
        await db.commit()

    token = issue_connect_token(
        sess.user_id,
        room.room_code,
        role,
        display_name=display_name,
        seat_index=seat_index,
    )
    return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)


@router.post("/{room_code}/spectate", response_model=RoomResponse)
async def spectate_room(room_code: str, req: JoinRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, name_changed = _resolve_display_name(user, is_guest)
    room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
    if not room:
        raise HTTPException(404, "room not found")

    existing = (await db.execute(
        select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.user_id == sess.user_id, RoomMember.left_at.is_(None))
    )).scalar_one_or_none()
    if existing:
        if name_changed:
            await db.commit()
        token = issue_connect_token(
            sess.user_id, room.room_code, existing.role,
            display_name=display_name,
            seat_index=existing.seat_index,
        )
        return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)

    db.add(RoomMember(room_id=room.room_id, user_id=sess.user_id, role="spectator", seat_index=None))
    await db.commit()
    token = issue_connect_token(sess.user_id, room.room_code, "spectator", display_name=display_name)
    return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)


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
