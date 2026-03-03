from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, is_admin_user_id
from app.config import settings
from app.db import get_db
from app.models import AuthIdentity, Match, MatchParticipant, MatchReplay, Room, RoomMember, Session, User
from app.replay_storage import get_local_replay_path, parse_local_replay_filename

router = APIRouter(prefix="/v1/admin", tags=["admin"])


def _to_iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.isoformat()


def _normalize_limit(limit: int, default_value: int = 50, max_value: int = 200) -> int:
    normalized = int(limit)
    if normalized <= 0:
        return default_value
    return min(normalized, max_value)


def _normalize_offset(offset: int) -> int:
    return max(0, int(offset))


async def _require_admin_session(
    session_id: str = Query(...),
    db: AsyncSession = Depends(get_db),
) -> Session:
    sess = await get_current_user(db=db, session_id=session_id)
    if str(settings.admin_user_ids or "").strip() == "":
        raise HTTPException(status_code=403, detail="admin disabled")
    if not is_admin_user_id(sess.user_id):
        raise HTTPException(status_code=403, detail="admin only")
    return sess


class AdminUserSummary(BaseModel):
    user_id: str
    status: str
    created_at: str
    email: str | None
    is_guest: bool
    active_sessions: int
    room_count: int
    match_count: int


class AdminUserStatusUpdateRequest(BaseModel):
    status: str


class AdminBatchUserStatusRequest(BaseModel):
    user_ids: list[str] = Field(default_factory=list)
    status: str


class AdminBatchUserDeleteRequest(BaseModel):
    user_ids: list[str] = Field(default_factory=list)


class AdminRoomSummary(BaseModel):
    room_code: str
    status: str
    owner_user_id: str
    join_policy: str
    game_server_id: str | None
    ws_url: str | None
    player_count: int
    spectator_count: int
    created_at: str
    updated_at: str


class AdminMatchSummary(BaseModel):
    match_id: str
    room_code: str | None
    status: str
    player_count: int
    participant_count: int
    has_replay: bool
    started_at: str | None
    ended_at: str | None
    created_at: str


class AdminBatchRoomRequest(BaseModel):
    room_codes: list[str] = Field(default_factory=list)


class AdminBatchMatchDeleteRequest(BaseModel):
    match_ids: list[str] = Field(default_factory=list)


class SimpleOkResponse(BaseModel):
    ok: bool = True


class BatchActionResult(BaseModel):
    ok: bool = True
    requested: int
    affected: int
    missing: list[str] = Field(default_factory=list)
    meta: dict[str, int] = Field(default_factory=dict)


def _build_user_summary(
    user: User,
    email_by_user_id: dict[str, str | None],
    has_guest_identity: dict[str, bool],
    active_sessions_by_user_id: dict[str, int],
    room_count_by_user_id: dict[str, int],
    match_count_by_user_id: dict[str, int],
) -> AdminUserSummary:
    return AdminUserSummary(
        user_id=user.user_id,
        status=str(user.status or "active"),
        created_at=_to_iso(user.created_at) or "",
        email=email_by_user_id.get(user.user_id),
        is_guest=bool(has_guest_identity.get(user.user_id, False)),
        active_sessions=int(active_sessions_by_user_id.get(user.user_id, 0)),
        room_count=int(room_count_by_user_id.get(user.user_id, 0)),
        match_count=int(match_count_by_user_id.get(user.user_id, 0)),
    )


def _normalize_non_empty_items(items: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for raw in items:
        item = str(raw).strip()
        if not item or item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


async def _delete_matches_by_ids(db: AsyncSession, match_ids: list[str]) -> list[str]:
    normalized_match_ids = _normalize_non_empty_items(match_ids)
    if not normalized_match_ids:
        return []

    existing_match_ids = [
        str(mid)
        for mid in (await db.execute(
            select(Match.match_id).where(Match.match_id.in_(normalized_match_ids))
        )).scalars().all()
    ]
    if not existing_match_ids:
        return []

    replays = (await db.execute(
        select(MatchReplay).where(MatchReplay.match_id.in_(existing_match_ids))
    )).scalars().all()
    for replay in replays:
        filename = parse_local_replay_filename(replay.storage_uri)
        if not filename:
            continue
        path = get_local_replay_path(filename)
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass

    await db.execute(delete(MatchParticipant).where(MatchParticipant.match_id.in_(existing_match_ids)))
    await db.execute(delete(MatchReplay).where(MatchReplay.match_id.in_(existing_match_ids)))
    await db.execute(delete(Match).where(Match.match_id.in_(existing_match_ids)))
    return existing_match_ids


async def _delete_rooms_by_codes(db: AsyncSession, room_codes: list[str]) -> list[str]:
    normalized_room_codes = _normalize_non_empty_items(room_codes)
    if not normalized_room_codes:
        return []

    rooms = (await db.execute(
        select(Room).where(Room.room_code.in_(normalized_room_codes))
    )).scalars().all()
    if not rooms:
        return []

    room_ids = [str(room.room_id) for room in rooms]
    existing_room_codes = [str(room.room_code) for room in rooms]
    await db.execute(delete(RoomMember).where(RoomMember.room_id.in_(room_ids)))
    await db.execute(delete(Room).where(Room.room_id.in_(room_ids)))
    return existing_room_codes


@router.get("/users", response_model=list[AdminUserSummary])
async def list_users(
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
    status: str | None = None,
    query: str | None = None,
    limit: int = 50,
    offset: int = 0,
):
    lim = _normalize_limit(limit)
    off = _normalize_offset(offset)
    stmt = select(User)
    if status:
        stmt = stmt.where(User.status == status)
    if query:
        q = str(query).strip()
        if q:
            stmt = stmt.where(User.user_id.contains(q))
    stmt = stmt.order_by(User.created_at.desc()).offset(off).limit(lim)
    users = (await db.execute(stmt)).scalars().all()
    if not users:
        return []

    user_ids = [u.user_id for u in users]
    identity_rows = (await db.execute(
        select(AuthIdentity.user_id, AuthIdentity.provider, AuthIdentity.provider_user_id).where(
            AuthIdentity.user_id.in_(user_ids)
        )
    )).all()
    email_by_user_id: dict[str, str | None] = {}
    has_guest_identity: dict[str, bool] = {}
    for uid, provider, provider_user_id in identity_rows:
        if str(provider) == "email" and uid not in email_by_user_id:
            email_by_user_id[uid] = str(provider_user_id)
        if str(provider) == "guest":
            has_guest_identity[uid] = True

    now = datetime.now(timezone.utc)
    session_rows = (await db.execute(
        select(Session.user_id, func.count())
        .where(
            Session.user_id.in_(user_ids),
            Session.revoked_at.is_(None),
            Session.expires_at > now,
        )
        .group_by(Session.user_id)
    )).all()
    active_sessions_by_user_id = {str(uid): int(count_val) for uid, count_val in session_rows}

    room_rows = (await db.execute(
        select(Room.owner_user_id, func.count())
        .where(Room.owner_user_id.in_(user_ids))
        .group_by(Room.owner_user_id)
    )).all()
    room_count_by_user_id = {str(uid): int(count_val) for uid, count_val in room_rows}

    match_rows = (await db.execute(
        select(MatchParticipant.user_id, func.count(func.distinct(MatchParticipant.match_id)))
        .where(MatchParticipant.user_id.in_(user_ids))
        .group_by(MatchParticipant.user_id)
    )).all()
    match_count_by_user_id = {str(uid): int(count_val) for uid, count_val in match_rows}

    return [
        _build_user_summary(
            u,
            email_by_user_id=email_by_user_id,
            has_guest_identity=has_guest_identity,
            active_sessions_by_user_id=active_sessions_by_user_id,
            room_count_by_user_id=room_count_by_user_id,
            match_count_by_user_id=match_count_by_user_id,
        )
        for u in users
    ]


@router.put("/users/{user_id}/status", response_model=AdminUserSummary)
async def update_user_status(
    user_id: str,
    payload: AdminUserStatusUpdateRequest,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    new_status = str(payload.status or "").strip().lower()
    allowed_status = {"active", "disabled", "banned"}
    if new_status not in allowed_status:
        raise HTTPException(status_code=400, detail="status must be one of: active|disabled|banned")

    user = (await db.execute(select(User).where(User.user_id == user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    user.status = new_status
    await db.commit()

    email_row = (await db.execute(
        select(AuthIdentity.provider_user_id).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "email",
        )
    )).scalar_one_or_none()
    guest_row = (await db.execute(
        select(AuthIdentity.id).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "guest",
        )
    )).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    active_sessions = (await db.execute(
        select(func.count()).select_from(Session).where(
            Session.user_id == user_id,
            Session.revoked_at.is_(None),
            Session.expires_at > now,
        )
    )).scalar_one()
    room_count = (await db.execute(
        select(func.count()).select_from(Room).where(Room.owner_user_id == user_id)
    )).scalar_one()
    match_count = (await db.execute(
        select(func.count(func.distinct(MatchParticipant.match_id))).where(MatchParticipant.user_id == user_id)
    )).scalar_one()

    return AdminUserSummary(
        user_id=user.user_id,
        status=str(user.status or "active"),
        created_at=_to_iso(user.created_at) or "",
        email=str(email_row) if email_row else None,
        is_guest=guest_row is not None,
        active_sessions=int(active_sessions or 0),
        room_count=int(room_count or 0),
        match_count=int(match_count or 0),
    )


@router.post("/users/batch/status", response_model=BatchActionResult)
async def batch_update_user_status(
    payload: AdminBatchUserStatusRequest,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    normalized_user_ids = _normalize_non_empty_items(payload.user_ids)
    requested = len(normalized_user_ids)
    if requested == 0:
        return BatchActionResult(requested=0, affected=0)

    new_status = str(payload.status or "").strip().lower()
    allowed_status = {"active", "disabled", "banned"}
    if new_status not in allowed_status:
        raise HTTPException(status_code=400, detail="status must be one of: active|disabled|banned")

    users = (await db.execute(
        select(User).where(User.user_id.in_(normalized_user_ids))
    )).scalars().all()
    existing_ids = {str(user.user_id) for user in users}
    for user in users:
        user.status = new_status
    await db.commit()

    missing = [uid for uid in normalized_user_ids if uid not in existing_ids]
    return BatchActionResult(
        requested=requested,
        affected=len(existing_ids),
        missing=missing,
    )


@router.post("/users/batch/delete", response_model=BatchActionResult)
async def batch_delete_users(
    payload: AdminBatchUserDeleteRequest,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    normalized_user_ids = _normalize_non_empty_items(payload.user_ids)
    requested = len(normalized_user_ids)
    if requested == 0:
        return BatchActionResult(requested=0, affected=0)

    existing_user_ids = [
        str(uid)
        for uid in (await db.execute(
            select(User.user_id).where(User.user_id.in_(normalized_user_ids))
        )).scalars().all()
    ]
    existing_user_set = set(existing_user_ids)

    owned_room_codes = [
        str(code)
        for code in (await db.execute(
            select(Room.room_code).where(Room.owner_user_id.in_(existing_user_ids))
        )).scalars().all()
    ]
    deleted_room_codes = await _delete_rooms_by_codes(db, owned_room_codes)

    candidate_match_ids = [
        str(mid)
        for mid in (await db.execute(
            select(func.distinct(MatchParticipant.match_id)).where(MatchParticipant.user_id.in_(existing_user_ids))
        )).scalars().all()
    ]
    await db.execute(delete(MatchParticipant).where(MatchParticipant.user_id.in_(existing_user_ids)))

    orphan_match_ids: list[str] = []
    if candidate_match_ids:
        candidate_rows = (await db.execute(
            select(Match.match_id, func.count(MatchParticipant.id))
            .outerjoin(MatchParticipant, MatchParticipant.match_id == Match.match_id)
            .where(Match.match_id.in_(candidate_match_ids))
            .group_by(Match.match_id)
        )).all()
        for match_id, participant_count in candidate_rows:
            if int(participant_count or 0) == 0:
                orphan_match_ids.append(str(match_id))
    deleted_orphan_match_ids = await _delete_matches_by_ids(db, orphan_match_ids)

    await db.execute(delete(RoomMember).where(RoomMember.user_id.in_(existing_user_ids)))
    await db.execute(delete(Session).where(Session.user_id.in_(existing_user_ids)))
    await db.execute(delete(AuthIdentity).where(AuthIdentity.user_id.in_(existing_user_ids)))
    await db.execute(delete(User).where(User.user_id.in_(existing_user_ids)))
    await db.commit()

    missing = [uid for uid in normalized_user_ids if uid not in existing_user_set]
    return BatchActionResult(
        requested=requested,
        affected=len(existing_user_ids),
        missing=missing,
        meta={
            "deleted_rooms": len(deleted_room_codes),
            "deleted_orphan_matches": len(deleted_orphan_match_ids),
        },
    )


@router.get("/rooms", response_model=list[AdminRoomSummary])
async def list_rooms(
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
    status: str | None = None,
    room_code: str | None = None,
    limit: int = 50,
    offset: int = 0,
):
    lim = _normalize_limit(limit)
    off = _normalize_offset(offset)
    stmt = select(Room)
    if status:
        stmt = stmt.where(Room.status == status)
    if room_code:
        code = str(room_code).strip()
        if code:
            stmt = stmt.where(Room.room_code.contains(code))
    stmt = stmt.order_by(Room.updated_at.desc()).offset(off).limit(lim)
    rooms = (await db.execute(stmt)).scalars().all()
    if not rooms:
        return []

    room_ids = [room.room_id for room in rooms]
    player_count_rows = (await db.execute(
        select(RoomMember.room_id, func.count())
        .where(
            RoomMember.room_id.in_(room_ids),
            RoomMember.left_at.is_(None),
            RoomMember.seat_index.is_not(None),
        )
        .group_by(RoomMember.room_id)
    )).all()
    player_count_by_room_id = {str(room_id): int(count_val) for room_id, count_val in player_count_rows}

    spectator_rows = (await db.execute(
        select(RoomMember.room_id, func.count())
        .where(
            RoomMember.room_id.in_(room_ids),
            RoomMember.left_at.is_(None),
            RoomMember.role == "spectator",
        )
        .group_by(RoomMember.room_id)
    )).all()
    spectator_count_by_room_id = {str(room_id): int(count_val) for room_id, count_val in spectator_rows}

    return [
        AdminRoomSummary(
            room_code=str(room.room_code),
            status=str(room.status),
            owner_user_id=str(room.owner_user_id),
            join_policy=str(room.join_policy),
            game_server_id=str(room.game_server_id) if room.game_server_id else None,
            ws_url=str(room.ws_url) if room.ws_url else None,
            player_count=int(player_count_by_room_id.get(room.room_id, 0)),
            spectator_count=int(spectator_count_by_room_id.get(room.room_id, 0)),
            created_at=_to_iso(room.created_at) or "",
            updated_at=_to_iso(room.updated_at) or "",
        )
        for room in rooms
    ]


@router.post("/rooms/batch/end", response_model=BatchActionResult)
async def batch_end_rooms(
    payload: AdminBatchRoomRequest,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    normalized_room_codes = _normalize_non_empty_items(payload.room_codes)
    requested = len(normalized_room_codes)
    if requested == 0:
        return BatchActionResult(requested=0, affected=0)

    rooms = (await db.execute(
        select(Room).where(Room.room_code.in_(normalized_room_codes))
    )).scalars().all()
    now = datetime.now(timezone.utc)
    existing_codes: set[str] = set()
    for room in rooms:
        room.status = "Ended"
        room.updated_at = now
        existing_codes.add(str(room.room_code))
    await db.commit()

    missing = [code for code in normalized_room_codes if code not in existing_codes]
    return BatchActionResult(
        requested=requested,
        affected=len(existing_codes),
        missing=missing,
    )


@router.post("/rooms/batch/delete", response_model=BatchActionResult)
async def batch_delete_rooms(
    payload: AdminBatchRoomRequest,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    normalized_room_codes = _normalize_non_empty_items(payload.room_codes)
    requested = len(normalized_room_codes)
    if requested == 0:
        return BatchActionResult(requested=0, affected=0)

    deleted_room_codes = await _delete_rooms_by_codes(db, normalized_room_codes)
    await db.commit()

    deleted_room_set = set(deleted_room_codes)
    missing = [code for code in normalized_room_codes if code not in deleted_room_set]
    return BatchActionResult(
        requested=requested,
        affected=len(deleted_room_codes),
        missing=missing,
    )


@router.post("/rooms/{room_code}/end", response_model=AdminRoomSummary)
async def end_room(
    room_code: str,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
    if room is None:
        raise HTTPException(status_code=404, detail="room not found")
    room.status = "Ended"
    room.updated_at = datetime.now(timezone.utc)
    await db.commit()

    player_count = (await db.execute(
        select(func.count()).select_from(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.left_at.is_(None),
            RoomMember.seat_index.is_not(None),
        )
    )).scalar_one()
    spectator_count = (await db.execute(
        select(func.count()).select_from(RoomMember).where(
            RoomMember.room_id == room.room_id,
            RoomMember.left_at.is_(None),
            RoomMember.role == "spectator",
        )
    )).scalar_one()
    return AdminRoomSummary(
        room_code=str(room.room_code),
        status=str(room.status),
        owner_user_id=str(room.owner_user_id),
        join_policy=str(room.join_policy),
        game_server_id=str(room.game_server_id) if room.game_server_id else None,
        ws_url=str(room.ws_url) if room.ws_url else None,
        player_count=int(player_count or 0),
        spectator_count=int(spectator_count or 0),
        created_at=_to_iso(room.created_at) or "",
        updated_at=_to_iso(room.updated_at) or "",
    )


@router.get("/matches", response_model=list[AdminMatchSummary])
async def list_matches(
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
    status: str | None = None,
    room_code: str | None = None,
    limit: int = 50,
    offset: int = 0,
):
    lim = _normalize_limit(limit)
    off = _normalize_offset(offset)
    stmt = select(Match)
    if status:
        stmt = stmt.where(Match.status == status)
    if room_code:
        code = str(room_code).strip()
        if code:
            stmt = stmt.where(Match.room_code.contains(code))
    stmt = stmt.order_by(Match.created_at.desc()).offset(off).limit(lim)
    matches = (await db.execute(stmt)).scalars().all()
    if not matches:
        return []

    match_ids = [m.match_id for m in matches]
    participant_rows = (await db.execute(
        select(MatchParticipant.match_id, func.count())
        .where(MatchParticipant.match_id.in_(match_ids))
        .group_by(MatchParticipant.match_id)
    )).all()
    participant_count_by_match_id = {str(match_id): int(count_val) for match_id, count_val in participant_rows}

    replay_rows = (await db.execute(
        select(MatchReplay.match_id).where(MatchReplay.match_id.in_(match_ids))
    )).scalars().all()
    replay_match_ids = {str(mid) for mid in replay_rows}

    return [
        AdminMatchSummary(
            match_id=str(m.match_id),
            room_code=str(m.room_code) if m.room_code else None,
            status=str(m.status),
            player_count=int(m.player_count or 0),
            participant_count=int(participant_count_by_match_id.get(m.match_id, 0)),
            has_replay=m.match_id in replay_match_ids,
            started_at=_to_iso(m.started_at),
            ended_at=_to_iso(m.ended_at),
            created_at=_to_iso(m.created_at) or "",
        )
        for m in matches
    ]


@router.post("/matches/batch/delete", response_model=BatchActionResult)
async def batch_delete_matches(
    payload: AdminBatchMatchDeleteRequest,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    normalized_match_ids = _normalize_non_empty_items(payload.match_ids)
    requested = len(normalized_match_ids)
    if requested == 0:
        return BatchActionResult(requested=0, affected=0)

    deleted_match_ids = await _delete_matches_by_ids(db, normalized_match_ids)
    await db.commit()

    deleted_match_set = set(deleted_match_ids)
    missing = [mid for mid in normalized_match_ids if mid not in deleted_match_set]
    return BatchActionResult(
        requested=requested,
        affected=len(deleted_match_ids),
        missing=missing,
    )


@router.delete("/matches/{match_id}", response_model=SimpleOkResponse)
async def delete_match_by_id(
    match_id: str,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    deleted_match_ids = await _delete_matches_by_ids(db, [match_id])
    if not deleted_match_ids:
        raise HTTPException(status_code=404, detail="match not found")
    await db.commit()
    return SimpleOkResponse(ok=True)
