from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, has_admin_access_configured, is_admin_user
from app.config import settings
from app.db import get_db
from app.models import AuthIdentity, GameServer, Match, MatchArtifact, MatchParticipant, MatchReplay, Room, RoomMember, RoomTombstone, Session, User
from app.replay_storage import (
    get_local_artifact_path,
    get_local_replay_path,
    parse_local_artifact_relative_path,
    parse_local_replay_filename,
)

router = APIRouter(prefix="/v1/admin", tags=["admin"])
GAME_SERVER_HEALTH_WINDOW_SECONDS = 75


def _to_iso(value: Optional[datetime]) -> Optional[str]:
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


def _healthy_game_server_cutoff() -> datetime:
    return datetime.now(timezone.utc) - timedelta(seconds=GAME_SERVER_HEALTH_WINDOW_SECONDS)


def _is_game_server_online(server: Optional[GameServer], healthy_cutoff: datetime) -> bool:
    if server is None:
        return False
    heartbeat_at = server.last_heartbeat_at
    if heartbeat_at is None:
        return False
    if heartbeat_at.tzinfo is None:
        heartbeat_at = heartbeat_at.replace(tzinfo=timezone.utc)
    return heartbeat_at >= healthy_cutoff


def _is_session_active(session: Session, now: datetime) -> bool:
    if session.revoked_at is not None:
        return False
    expires_at = session.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at > now


async def _require_admin_session(
    session_id: str = Query(...),
    db: AsyncSession = Depends(get_db),
) -> Session:
    sess = await get_current_user(db=db, session_id=session_id)
    if not has_admin_access_configured():
        raise HTTPException(status_code=403, detail="admin disabled")
    if not await is_admin_user(db, sess.user_id):
        raise HTTPException(status_code=403, detail="admin only")
    return sess


class AdminUserSummary(BaseModel):
    user_id: str
    display_name: str
    status: str
    created_at: str
    email: Optional[str]
    is_guest: bool
    active_sessions: int
    room_count: int
    match_count: int


class AdminUserListResponse(BaseModel):
    items: list[AdminUserSummary] = Field(default_factory=list)
    total: int
    limit: int
    offset: int


class AdminUserIdentitySummary(BaseModel):
    provider: str
    provider_user_id: str
    verified: bool


class AdminUserSessionSummary(BaseModel):
    session_id: str
    device_id: Optional[str]
    active: bool
    created_at: str
    expires_at: str
    revoked_at: Optional[str]


class AdminUserRecentRoomSummary(BaseModel):
    room_code: str
    status: str
    game_server_id: Optional[str]
    player_count: int
    spectator_count: int
    updated_at: str


class AdminUserRecentMatchSummary(BaseModel):
    match_id: str
    room_code: Optional[str]
    status: str
    role: str
    result: Optional[str]
    created_at: str


class AdminUserDetailResponse(BaseModel):
    user: AdminUserSummary
    identities: list[AdminUserIdentitySummary] = Field(default_factory=list)
    sessions: list[AdminUserSessionSummary] = Field(default_factory=list)
    recent_rooms: list[AdminUserRecentRoomSummary] = Field(default_factory=list)
    recent_matches: list[AdminUserRecentMatchSummary] = Field(default_factory=list)


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
    game_server_id: Optional[str]
    ws_url: Optional[str]
    server_status: Optional[str]
    server_last_heartbeat_at: Optional[str]
    server_online: bool
    player_count: int
    spectator_count: int
    created_at: str
    updated_at: str


class AdminRoomListResponse(BaseModel):
    items: list[AdminRoomSummary] = Field(default_factory=list)
    total: int
    limit: int
    offset: int


class AdminMatchSummary(BaseModel):
    match_id: str
    room_code: Optional[str]
    status: str
    player_count: int
    participant_count: int
    has_replay: bool
    started_at: Optional[str]
    ended_at: Optional[str]
    created_at: str


class AdminMatchListResponse(BaseModel):
    items: list[AdminMatchSummary] = Field(default_factory=list)
    total: int
    limit: int
    offset: int


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
    email_by_user_id: dict[str, Optional[str]],
    has_guest_identity: dict[str, bool],
    active_sessions_by_user_id: dict[str, int],
    room_count_by_user_id: dict[str, int],
    match_count_by_user_id: dict[str, int],
) -> AdminUserSummary:
    return AdminUserSummary(
        user_id=user.user_id,
        display_name=str(user.display_name or ""),
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

    artifacts = (await db.execute(
        select(MatchArtifact).where(MatchArtifact.match_id.in_(existing_match_ids))
    )).scalars().all()
    for artifact in artifacts:
        relative_path = parse_local_artifact_relative_path(artifact.storage_uri)
        if not relative_path:
            continue
        path = get_local_artifact_path(relative_path)
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass

    await db.execute(delete(MatchParticipant).where(MatchParticipant.match_id.in_(existing_match_ids)))
    await db.execute(delete(MatchReplay).where(MatchReplay.match_id.in_(existing_match_ids)))
    await db.execute(delete(MatchArtifact).where(MatchArtifact.match_id.in_(existing_match_ids)))
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
    existing_tombstones = (await db.execute(
        select(RoomTombstone).where(RoomTombstone.room_code.in_(existing_room_codes))
    )).scalars().all()
    tombstone_codes = {str(t.room_code) for t in existing_tombstones}
    for room_code in existing_room_codes:
        if room_code in tombstone_codes:
            continue
        db.add(RoomTombstone(room_code=room_code))
    await db.execute(delete(RoomMember).where(RoomMember.room_id.in_(room_ids)))
    await db.execute(delete(Room).where(Room.room_id.in_(room_ids)))
    return existing_room_codes


async def _mark_room_members_left(
    db: AsyncSession,
    room_ids: list[str],
    now: datetime,
    member_status: str = "ended",
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


@router.get("/users", response_model=AdminUserListResponse)
async def list_users(
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
    status: Optional[str] = None,
    query: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
):
    lim = _normalize_limit(limit)
    off = _normalize_offset(offset)
    conditions = []
    status_text = str(status or "").strip().lower()
    if status_text:
        conditions.append(User.status == status_text)

    query_text = str(query or "").strip()
    if query_text:
        identity_user_ids = [
            str(uid)
            for uid in (await db.execute(
                select(AuthIdentity.user_id).where(
                    AuthIdentity.provider == "email",
                    AuthIdentity.provider_user_id.contains(query_text),
                )
            )).scalars().all()
        ]
        search_terms = [User.user_id.contains(query_text), User.display_name.contains(query_text)]
        if identity_user_ids:
            search_terms.append(User.user_id.in_(identity_user_ids))
        conditions.append(or_(*search_terms))

    stmt = select(User)
    count_stmt = select(func.count()).select_from(User)
    if conditions:
        stmt = stmt.where(*conditions)
        count_stmt = count_stmt.where(*conditions)
    total = int((await db.execute(count_stmt)).scalar_one() or 0)
    stmt = stmt.order_by(User.created_at.desc()).offset(off).limit(lim)
    users = (await db.execute(stmt)).scalars().all()
    if not users:
        return AdminUserListResponse(items=[], total=total, limit=lim, offset=off)

    user_ids = [u.user_id for u in users]
    identity_rows = (await db.execute(
        select(AuthIdentity.user_id, AuthIdentity.provider, AuthIdentity.provider_user_id).where(
            AuthIdentity.user_id.in_(user_ids)
        )
    )).all()
    email_by_user_id: dict[str, Optional[str]] = {}
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

    return AdminUserListResponse(
        items=[
            _build_user_summary(
                u,
                email_by_user_id=email_by_user_id,
                has_guest_identity=has_guest_identity,
                active_sessions_by_user_id=active_sessions_by_user_id,
                room_count_by_user_id=room_count_by_user_id,
                match_count_by_user_id=match_count_by_user_id,
            )
            for u in users
        ],
        total=total,
        limit=lim,
        offset=off,
    )


@router.get("/users/{user_id}", response_model=AdminUserDetailResponse)
async def get_user_detail(
    user_id: str,
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
):
    user = (await db.execute(select(User).where(User.user_id == user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")

    identities = (await db.execute(
        select(AuthIdentity).where(AuthIdentity.user_id == user_id).order_by(AuthIdentity.provider.asc())
    )).scalars().all()
    email_by_user_id: dict[str, Optional[str]] = {}
    has_guest_identity: dict[str, bool] = {}
    for identity in identities:
        if str(identity.provider) == "email" and user_id not in email_by_user_id:
            email_by_user_id[user_id] = str(identity.provider_user_id)
        if str(identity.provider) == "guest":
            has_guest_identity[user_id] = True

    now = datetime.now(timezone.utc)
    active_sessions = int((await db.execute(
        select(func.count()).select_from(Session).where(
            Session.user_id == user_id,
            Session.revoked_at.is_(None),
            Session.expires_at > now,
        )
    )).scalar_one() or 0)
    room_count = int((await db.execute(
        select(func.count()).select_from(Room).where(Room.owner_user_id == user_id)
    )).scalar_one() or 0)
    match_count = int((await db.execute(
        select(func.count(func.distinct(MatchParticipant.match_id))).where(MatchParticipant.user_id == user_id)
    )).scalar_one() or 0)

    sessions = (await db.execute(
        select(Session)
        .where(Session.user_id == user_id)
        .order_by(Session.created_at.desc())
        .limit(20)
    )).scalars().all()

    recent_rooms = (await db.execute(
        select(Room)
        .where(Room.owner_user_id == user_id)
        .order_by(Room.updated_at.desc())
        .limit(10)
    )).scalars().all()
    recent_room_ids = [room.room_id for room in recent_rooms]
    player_count_by_room_id: dict[str, int] = {}
    spectator_count_by_room_id: dict[str, int] = {}
    if recent_room_ids:
        player_rows = (await db.execute(
            select(RoomMember.room_id, func.count())
            .where(
                RoomMember.room_id.in_(recent_room_ids),
                RoomMember.left_at.is_(None),
                RoomMember.seat_index.is_not(None),
            )
            .group_by(RoomMember.room_id)
        )).all()
        player_count_by_room_id = {str(room_id): int(count_val) for room_id, count_val in player_rows}
        spectator_rows = (await db.execute(
            select(RoomMember.room_id, func.count())
            .where(
                RoomMember.room_id.in_(recent_room_ids),
                RoomMember.left_at.is_(None),
                RoomMember.role == "spectator",
            )
            .group_by(RoomMember.room_id)
        )).all()
        spectator_count_by_room_id = {str(room_id): int(count_val) for room_id, count_val in spectator_rows}

    recent_match_rows = (await db.execute(
        select(Match, MatchParticipant)
        .join(MatchParticipant, MatchParticipant.match_id == Match.match_id)
        .where(MatchParticipant.user_id == user_id)
        .order_by(Match.created_at.desc())
        .limit(10)
    )).all()

    return AdminUserDetailResponse(
        user=_build_user_summary(
            user,
            email_by_user_id=email_by_user_id,
            has_guest_identity=has_guest_identity,
            active_sessions_by_user_id={user_id: active_sessions},
            room_count_by_user_id={user_id: room_count},
            match_count_by_user_id={user_id: match_count},
        ),
        identities=[
            AdminUserIdentitySummary(
                provider=str(identity.provider),
                provider_user_id=str(identity.provider_user_id),
                verified=bool(identity.verified),
            )
            for identity in identities
        ],
        sessions=[
            AdminUserSessionSummary(
                session_id=str(session.session_id),
                device_id=str(session.device_id) if session.device_id else None,
                active=_is_session_active(session, now),
                created_at=_to_iso(session.created_at) or "",
                expires_at=_to_iso(session.expires_at) or "",
                revoked_at=_to_iso(session.revoked_at),
            )
            for session in sessions
        ],
        recent_rooms=[
            AdminUserRecentRoomSummary(
                room_code=str(room.room_code),
                status=str(room.status),
                game_server_id=str(room.game_server_id) if room.game_server_id else None,
                player_count=int(player_count_by_room_id.get(room.room_id, 0)),
                spectator_count=int(spectator_count_by_room_id.get(room.room_id, 0)),
                updated_at=_to_iso(room.updated_at) or "",
            )
            for room in recent_rooms
        ],
        recent_matches=[
            AdminUserRecentMatchSummary(
                match_id=str(match.match_id),
                room_code=str(match.room_code) if match.room_code else None,
                status=str(match.status),
                role=str(participant.role),
                result=str(participant.result) if participant.result else None,
                created_at=_to_iso(match.created_at) or "",
            )
            for match, participant in recent_match_rows
        ],
    )


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
        display_name=str(user.display_name or ""),
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


@router.get("/rooms", response_model=AdminRoomListResponse)
async def list_rooms(
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
    status: Optional[str] = None,
    room_code: Optional[str] = None,
    owner_user_id: Optional[str] = None,
    game_server_id: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
):
    lim = _normalize_limit(limit)
    off = _normalize_offset(offset)
    conditions = []
    status_text = str(status or "").strip()
    if status_text:
        conditions.append(Room.status == status_text)
    room_code_text = str(room_code or "").strip().upper()
    if room_code_text:
        conditions.append(Room.room_code.contains(room_code_text))
    owner_user_id_text = str(owner_user_id or "").strip()
    if owner_user_id_text:
        conditions.append(Room.owner_user_id == owner_user_id_text)
    game_server_id_text = str(game_server_id or "").strip()
    if game_server_id_text:
        conditions.append(Room.game_server_id == game_server_id_text)

    stmt = select(Room)
    count_stmt = select(func.count()).select_from(Room)
    if conditions:
        stmt = stmt.where(*conditions)
        count_stmt = count_stmt.where(*conditions)
    total = int((await db.execute(count_stmt)).scalar_one() or 0)
    stmt = stmt.order_by(Room.updated_at.desc()).offset(off).limit(lim)
    rooms = (await db.execute(stmt)).scalars().all()
    if not rooms:
        return AdminRoomListResponse(items=[], total=total, limit=lim, offset=off)

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

    game_server_ids = [
        str(room.game_server_id)
        for room in rooms
        if str(room.game_server_id or "").strip()
    ]
    server_by_id: dict[str, GameServer] = {}
    if game_server_ids:
        servers = (await db.execute(
            select(GameServer).where(GameServer.game_server_id.in_(game_server_ids))
        )).scalars().all()
        server_by_id = {str(server.game_server_id): server for server in servers}

    healthy_cutoff = _healthy_game_server_cutoff()
    return AdminRoomListResponse(
        items=[
            AdminRoomSummary(
                room_code=str(room.room_code),
                status=str(room.status),
                owner_user_id=str(room.owner_user_id),
                join_policy=str(room.join_policy),
                game_server_id=str(room.game_server_id) if room.game_server_id else None,
                ws_url=str(room.ws_url) if room.ws_url else None,
                server_status=str(server_by_id[str(room.game_server_id)].status) if room.game_server_id and str(room.game_server_id) in server_by_id else None,
                server_last_heartbeat_at=_to_iso(server_by_id[str(room.game_server_id)].last_heartbeat_at) if room.game_server_id and str(room.game_server_id) in server_by_id else None,
                server_online=(
                    room.game_server_id is not None
                    and str(room.game_server_id) in server_by_id
                    and _is_game_server_online(server_by_id[str(room.game_server_id)], healthy_cutoff)
                ),
                player_count=int(player_count_by_room_id.get(room.room_id, 0)),
                spectator_count=int(spectator_count_by_room_id.get(room.room_id, 0)),
                created_at=_to_iso(room.created_at) or "",
                updated_at=_to_iso(room.updated_at) or "",
            )
            for room in rooms
        ],
        total=total,
        limit=lim,
        offset=off,
    )


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
    room_ids: list[str] = []
    for room in rooms:
        room.status = "Ended"
        room.updated_at = now
        existing_codes.add(str(room.room_code))
        room_ids.append(str(room.room_id))
    await _mark_room_members_left(db, room_ids, now, "ended")
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
    now = datetime.now(timezone.utc)
    room.status = "Ended"
    room.updated_at = now
    await _mark_room_members_left(db, [str(room.room_id)], now, "ended")
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
    server = None
    if room.game_server_id:
        server = (await db.execute(
            select(GameServer).where(GameServer.game_server_id == str(room.game_server_id))
        )).scalar_one_or_none()
    healthy_cutoff = _healthy_game_server_cutoff()
    return AdminRoomSummary(
        room_code=str(room.room_code),
        status=str(room.status),
        owner_user_id=str(room.owner_user_id),
        join_policy=str(room.join_policy),
        game_server_id=str(room.game_server_id) if room.game_server_id else None,
        ws_url=str(room.ws_url) if room.ws_url else None,
        server_status=str(server.status) if server is not None else None,
        server_last_heartbeat_at=_to_iso(server.last_heartbeat_at) if server is not None else None,
        server_online=_is_game_server_online(server, healthy_cutoff),
        player_count=int(player_count or 0),
        spectator_count=int(spectator_count or 0),
        created_at=_to_iso(room.created_at) or "",
        updated_at=_to_iso(room.updated_at) or "",
    )


@router.get("/matches", response_model=AdminMatchListResponse)
async def list_matches(
    _status: Session = Depends(_require_admin_session),
    db: AsyncSession = Depends(get_db),
    status: Optional[str] = None,
    room_code: Optional[str] = None,
    participant_user_id: Optional[str] = None,
    has_replay: Optional[bool] = None,
    limit: int = 50,
    offset: int = 0,
):
    lim = _normalize_limit(limit)
    off = _normalize_offset(offset)
    stmt = select(Match)
    count_stmt = select(func.count(func.distinct(Match.match_id))).select_from(Match)
    needs_distinct = False

    participant_text = str(participant_user_id or "").strip()
    if participant_text:
        stmt = stmt.join(MatchParticipant, MatchParticipant.match_id == Match.match_id)
        count_stmt = count_stmt.join(MatchParticipant, MatchParticipant.match_id == Match.match_id)
        stmt = stmt.where(MatchParticipant.user_id == participant_text)
        count_stmt = count_stmt.where(MatchParticipant.user_id == participant_text)
        needs_distinct = True

    if has_replay is True:
        stmt = stmt.join(MatchReplay, MatchReplay.match_id == Match.match_id)
        count_stmt = count_stmt.join(MatchReplay, MatchReplay.match_id == Match.match_id)
        needs_distinct = True
    elif has_replay is False:
        stmt = stmt.outerjoin(MatchReplay, MatchReplay.match_id == Match.match_id)
        count_stmt = count_stmt.outerjoin(MatchReplay, MatchReplay.match_id == Match.match_id)
        stmt = stmt.where(MatchReplay.match_id.is_(None))
        count_stmt = count_stmt.where(MatchReplay.match_id.is_(None))
        needs_distinct = True

    status_text = str(status or "").strip()
    if status_text:
        stmt = stmt.where(Match.status == status_text)
        count_stmt = count_stmt.where(Match.status == status_text)
    room_code_text = str(room_code or "").strip().upper()
    if room_code_text:
        stmt = stmt.where(Match.room_code.contains(room_code_text))
        count_stmt = count_stmt.where(Match.room_code.contains(room_code_text))

    total = int((await db.execute(count_stmt)).scalar_one() or 0)
    if needs_distinct:
        stmt = stmt.distinct()
    stmt = stmt.order_by(Match.created_at.desc()).offset(off).limit(lim)
    matches = (await db.execute(stmt)).scalars().all()
    if not matches:
        return AdminMatchListResponse(items=[], total=total, limit=lim, offset=off)

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

    return AdminMatchListResponse(
        items=[
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
        ],
        total=total,
        limit=lim,
        offset=off,
    )


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
