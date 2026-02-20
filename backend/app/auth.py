import hashlib
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


def _hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    h = hashlib.sha256((salt + password).encode()).hexdigest()
    return f"{salt}${h}"


def _verify_password(password: str, credential_hash: str) -> bool:
    salt, h = credential_hash.split("$", 1)
    return hashlib.sha256((salt + password).encode()).hexdigest() == h


class RegisterRequest(BaseModel):
    email: str
    password: str


class LoginRequest(BaseModel):
    email: str
    password: str


@router.post("/register", response_model=AuthResponse)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    if not req.email or not req.password:
        raise HTTPException(400, "email and password are required")

    exists = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "email",
            AuthIdentity.provider_user_id == req.email,
        )
    )).scalar_one_or_none()
    if exists:
        raise HTTPException(409, "email already registered")

    user = User()
    db.add(user)
    await db.flush()
    db.add(AuthIdentity(
        provider="email",
        provider_user_id=req.email,
        user_id=user.user_id,
        credential_hash=_hash_password(req.password),
        verified=False,
    ))
    sess = _new_session(user.user_id)
    db.add(sess)
    await db.commit()
    return AuthResponse(user_id=user.user_id, session_id=sess.session_id)


@router.post("/login", response_model=AuthResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    identity = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "email",
            AuthIdentity.provider_user_id == req.email,
        )
    )).scalar_one_or_none()
    if not identity or not _verify_password(req.password, identity.credential_hash):
        raise HTTPException(401, "invalid email or password")

    sess = _new_session(identity.user_id)
    db.add(sess)
    await db.commit()
    return AuthResponse(user_id=identity.user_id, session_id=sess.session_id)


class BindRequest(BaseModel):
    session_id: str
    provider: str  # "email"
    email: str
    password: str


@router.post("/bind", response_model=AuthResponse)
async def bind(req: BindRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)

    # Check email not already taken
    exists = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == req.provider,
            AuthIdentity.provider_user_id == req.email,
        )
    )).scalar_one_or_none()
    if exists:
        raise HTTPException(409, "email already registered")

    db.add(AuthIdentity(
        provider=req.provider,
        provider_user_id=req.email,
        user_id=sess.user_id,
        credential_hash=_hash_password(req.password),
        verified=False,
    ))
    await db.commit()
    return AuthResponse(user_id=sess.user_id, session_id=sess.session_id)


class LogoutRequest(BaseModel):
    session_id: str


@router.post("/logout")
async def logout(req: LogoutRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    sess.revoked_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}
