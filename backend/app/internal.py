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
from app.models import GameServer, Room, Match, MatchParticipant, MatchReplay
from app.replay_storage import save_local_replay_archive

router = APIRouter(prefix="/internal", tags=["internal"])

def _require_internal_secret(x_internal_secret: Optional[str] = Header(default=None, alias="X-Internal-Secret")) -> None:
    expected = str(settings.internal_api_secret).strip()
    if expected == "":
        raise HTTPException(status_code=500, detail="internal_api_secret not configured")
    provided = str(x_internal_secret or "").strip()
    if not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unauthorized")


class HeartbeatRequest(BaseModel):
    game_server_id: str
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
    else:
        db.add(GameServer(game_server_id=req.game_server_id, last_heartbeat_at=now))

    # Mark alive rooms (refresh updated_at, claim ownership).
    if req.room_codes:
        rooms = (await db.execute(select(Room).where(Room.room_code.in_(req.room_codes)))).scalars().all()
        for r in rooms:
            r.game_server_id = req.game_server_id
            # Allow revival if the room became active again.
            if r.status == "Ended":
                r.status = "Lobby"
            r.updated_at = now

    # GC: rooms previously on this game server but no longer present -> Ended.
    stmt = select(Room).where(Room.game_server_id == req.game_server_id, Room.status != "Ended")
    if req.room_codes:
        stmt = stmt.where(~Room.room_code.in_(req.room_codes))
    stale = (await db.execute(stmt)).scalars().all()
    for r in stale:
        r.status = "Ended"
        r.updated_at = now

    await db.commit()
    return {"ok": True}


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
