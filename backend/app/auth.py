import hmac
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
    salt = secrets.token_bytes(16)
    iterations = int(settings.password_hash_iterations)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return f"pbkdf2_sha256${iterations}${salt.hex()}${dk.hex()}"


def _verify_password(password: str, credential_hash: str) -> bool:
    if not credential_hash:
        return False
    parts = credential_hash.split("$")
    if len(parts) == 4 and parts[0] == "pbkdf2_sha256":
        _, iter_s, salt_hex, hash_hex = parts
        if not iter_s.isdigit():
            return False
        try:
            salt = bytes.fromhex(salt_hex)
            expected = bytes.fromhex(hash_hex)
        except ValueError:
            return False
        dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iter_s))
        return hmac.compare_digest(dk, expected)

    # Legacy: sha256(salt + password) in hex, stored as "{salt_hex}${hash_hex}"
    if len(parts) == 2:
        salt, h = parts
        computed = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
        return hmac.compare_digest(computed, h)

    return False


def _is_legacy_password_hash(credential_hash: str) -> bool:
    if not credential_hash:
        return False
    return credential_hash.count("$") == 1 and not credential_hash.startswith("pbkdf2_sha256$")


def _normalize_email(email: str) -> str:
    return str(email).strip().casefold()


def _parse_admin_user_ids() -> set[str]:
    raw = str(settings.admin_user_ids or "")
    return {item.strip() for item in raw.split(",") if item.strip()}


def is_admin_user_id(user_id: str) -> bool:
    admin_user_ids = _parse_admin_user_ids()
    if not admin_user_ids:
        return False
    return "*" in admin_user_ids or user_id in admin_user_ids


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

    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")
    exists = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "email",
            AuthIdentity.provider_user_id == email,
        )
    )).scalar_one_or_none()
    if exists:
        raise HTTPException(409, "email already registered")

    user = User()
    db.add(user)
    await db.flush()
    db.add(AuthIdentity(
        provider="email",
        provider_user_id=email,
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
    email = _normalize_email(req.email)
    identity = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "email",
            AuthIdentity.provider_user_id == email,
        )
    )).scalar_one_or_none()
    if not identity or not _verify_password(req.password, identity.credential_hash):
        raise HTTPException(401, "invalid email or password")

    # Lazy upgrade legacy hashes on successful login
    if identity.credential_hash and _is_legacy_password_hash(identity.credential_hash):
        identity.credential_hash = _hash_password(req.password)

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

    if str(req.provider).strip() != "email":
        raise HTTPException(400, "unsupported provider")
    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")

    # Check email not already taken
    exists = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == req.provider,
            AuthIdentity.provider_user_id == email,
        )
    )).scalar_one_or_none()
    if exists:
        raise HTTPException(409, "email already registered")

    db.add(AuthIdentity(
        provider=req.provider,
        provider_user_id=email,
        user_id=sess.user_id,
        credential_hash=_hash_password(req.password),
        verified=False,
    ))
    await db.commit()
    return AuthResponse(user_id=sess.user_id, session_id=sess.session_id)


class MeResponse(BaseModel):
    user_id: str
    email: str | None
    is_guest: bool
    is_admin: bool
    created_at: str


@router.get("/me", response_model=MeResponse)
async def get_me(session_id: str = "", db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one()

    email_identity = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.user_id == sess.user_id,
            AuthIdentity.provider == "email",
        )
    )).scalar_one_or_none()

    has_guest = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.user_id == sess.user_id,
            AuthIdentity.provider == "guest",
        )
    )).scalar_one_or_none()

    return MeResponse(
        user_id=user.user_id,
        email=email_identity.provider_user_id if email_identity else None,
        is_guest=has_guest is not None and email_identity is None,
        is_admin=is_admin_user_id(user.user_id),
        created_at=user.created_at.isoformat(),
    )


class ChangePasswordRequest(BaseModel):
    session_id: str
    old_password: str
    new_password: str


@router.put("/password")
async def change_password(req: ChangePasswordRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)

    identity = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.user_id == sess.user_id,
            AuthIdentity.provider == "email",
        )
    )).scalar_one_or_none()
    if not identity:
        raise HTTPException(400, "no email identity bound")

    if not _verify_password(req.old_password, identity.credential_hash):
        raise HTTPException(401, "incorrect old password")

    if not req.new_password:
        raise HTTPException(400, "new_password is required")

    identity.credential_hash = _hash_password(req.new_password)
    await db.commit()
    return {"ok": True}


class LogoutRequest(BaseModel):
    session_id: str


@router.post("/logout")
async def logout(req: LogoutRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    sess.revoked_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}
