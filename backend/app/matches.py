from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.db import get_db
from app.models import Match, MatchParticipant, MatchReplay

router = APIRouter(prefix="/v1/matches", tags=["matches"])


class MatchSummary(BaseModel):
    match_id: str
    room_code: str | None
    status: str
    player_count: int
    started_at: str | None
    ended_at: str | None


class MatchDetail(MatchSummary):
    duration_sec: int | None
    seed: str | None
    schema_version: str | None
    game_version: str | None
    final_hash: str | None
    summary_json: str | None


class ReplayInfo(BaseModel):
    match_id: str
    storage_uri: str
    checksum: str | None
    size_bytes: int | None


@router.get("", response_model=list[MatchSummary])
async def list_matches(
    session_id: str = Query(...),
    db: AsyncSession = Depends(get_db),
):
    sess = await get_current_user(db=db, session_id=session_id)
    stmt = (
        select(Match)
        .join(MatchParticipant, MatchParticipant.match_id == Match.match_id)
        .where(MatchParticipant.user_id == sess.user_id)
        .order_by(Match.created_at.desc())
    )
    rows = (await db.execute(stmt)).scalars().all()
    return [
        MatchSummary(
            match_id=m.match_id, room_code=m.room_code, status=m.status,
            player_count=m.player_count,
            started_at=m.started_at.isoformat() if m.started_at else None,
            ended_at=m.ended_at.isoformat() if m.ended_at else None,
        ) for m in rows
    ]


@router.get("/{match_id}", response_model=MatchDetail)
async def get_match(match_id: str, session_id: str = Query(...), db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    # Check participant
    part = (await db.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == match_id, MatchParticipant.user_id == sess.user_id)
    )).scalar_one_or_none()
    if not part:
        raise HTTPException(403, "not a participant")
    match = (await db.execute(select(Match).where(Match.match_id == match_id))).scalar_one_or_none()
    if not match:
        raise HTTPException(404, "match not found")
    return MatchDetail(
        match_id=match.match_id, room_code=match.room_code, status=match.status,
        player_count=match.player_count,
        started_at=match.started_at.isoformat() if match.started_at else None,
        ended_at=match.ended_at.isoformat() if match.ended_at else None,
        duration_sec=match.duration_sec, seed=match.seed,
        schema_version=match.schema_version, game_version=match.game_version,
        final_hash=match.final_hash, summary_json=match.summary_json,
    )


@router.get("/{match_id}/replay", response_model=ReplayInfo)
async def get_replay(match_id: str, session_id: str = Query(...), db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    part = (await db.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == match_id, MatchParticipant.user_id == sess.user_id)
    )).scalar_one_or_none()
    if not part:
        raise HTTPException(403, "not a participant")
    replay = (await db.execute(
        select(MatchReplay).where(MatchReplay.match_id == match_id)
    )).scalar_one_or_none()
    if not replay:
        raise HTTPException(404, "replay not found")
    return ReplayInfo(
        match_id=replay.match_id, storage_uri=replay.storage_uri,
        checksum=replay.checksum, size_bytes=replay.size_bytes,
    )
