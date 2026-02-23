from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.connect_token import issue_connect_token
from app.db import get_db
from app.models import Room, RoomMember, Session

router = APIRouter(prefix="/v1/rooms", tags=["rooms"])

DEFAULT_WS_URL = "ws://localhost:7000"


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


@router.post("", response_model=RoomResponse)
async def create_room(req: CreateRoomRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)

    from app.auth import _hash_password
    room = Room(
        owner_user_id=sess.user_id,
        config_json=req.config_json,
        ws_url=DEFAULT_WS_URL,
        join_policy="password" if req.password else "public",
        password_hash=_hash_password(req.password) if req.password else None,
    )
    db.add(room)
    await db.flush()

    db.add(RoomMember(room_id=room.room_id, user_id=sess.user_id, role="host", seat_index=0))
    await db.commit()

    token = issue_connect_token(sess.user_id, room.room_code, "host", seat_index=0, config_json=req.config_json)
    return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)


class JoinRequest(BaseModel):
    session_id: str
    password: str = ""


@router.post("/{room_code}/join", response_model=RoomResponse)
async def join_room(room_code: str, req: JoinRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
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
        token = issue_connect_token(
            sess.user_id, room.room_code, existing.role,
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
    token = issue_connect_token(sess.user_id, room.room_code, "player", seat_index=seat)
    return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)


@router.post("/{room_code}/spectate", response_model=RoomResponse)
async def spectate_room(room_code: str, req: JoinRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
    if not room:
        raise HTTPException(404, "room not found")

    existing = (await db.execute(
        select(RoomMember).where(RoomMember.room_id == room.room_id, RoomMember.user_id == sess.user_id, RoomMember.left_at.is_(None))
    )).scalar_one_or_none()
    if existing:
        token = issue_connect_token(
            sess.user_id, room.room_code, existing.role,
            seat_index=existing.seat_index,
        )
        return RoomResponse(room_code=room.room_code, ws_url=room.ws_url, connect_token=token)

    db.add(RoomMember(room_id=room.room_id, user_id=sess.user_id, role="spectator", seat_index=None))
    await db.commit()
    token = issue_connect_token(sess.user_id, room.room_code, "spectator")
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
