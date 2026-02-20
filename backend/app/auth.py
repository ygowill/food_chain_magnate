import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.models import User, AuthIdentity, Session

router = APIRouter(prefix="/v1/auth", tags=["auth"])


class GuestRequest(BaseModel):
    device_id: str


class AuthResponse(BaseModel):
    user_id: str
    session_id: str


def _new_session(user_id: str, device_id: str | None = None) -> Session:
    return Session(
        session_id=secrets.token_urlsafe(32),
        user_id=user_id,
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.session_expire_days),
        device_id=device_id,
    )


async def get_current_user(
    db: AsyncSession = Depends(get_db),
    session_id: str = "",
) -> Session:
    if not session_id:
        raise HTTPException(401, "missing session_id")
    stmt = select(Session).where(
        Session.session_id == session_id,
        Session.revoked_at.is_(None),
        Session.expires_at > datetime.now(timezone.utc),
    )
    sess = (await db.execute(stmt)).scalar_one_or_none()
    if not sess:
        raise HTTPException(401, "invalid or expired session")
    return sess


@router.post("/guest", response_model=AuthResponse)
async def guest_login(req: GuestRequest, db: AsyncSession = Depends(get_db)):
    if not req.device_id:
        raise HTTPException(400, "device_id is required")

    stmt = select(AuthIdentity).where(
        AuthIdentity.provider == "guest",
        AuthIdentity.provider_user_id == req.device_id,
    )
    identity = (await db.execute(stmt)).scalar_one_or_none()

    if identity:
        user_id = identity.user_id
    else:
        user = User()
        db.add(user)
        await db.flush()
        db.add(AuthIdentity(provider="guest", provider_user_id=req.device_id, user_id=user.user_id))
        user_id = user.user_id

    sess = _new_session(user_id, req.device_id)
    db.add(sess)
    await db.commit()
    return AuthResponse(user_id=user_id, session_id=sess.session_id)
