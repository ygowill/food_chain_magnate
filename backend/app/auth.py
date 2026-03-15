from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.models import AuthIdentity, Session, User

router = APIRouter(prefix="/v1/auth", tags=["auth"])

_DISPLAY_NAME_MAX_LEN = 24
_GUEST_NAME_PREFIX = "游客#"
_ACCOUNT_NAME_PREFIX = "账号#"
_DEFAULT_NAME_SUFFIX = "0000"


class GuestRequest(BaseModel):
    device_id: str


class AuthResponse(BaseModel):
    user_id: str
    session_id: str
    display_name: str
    is_guest: bool


class RegisterRequest(BaseModel):
    email: str
    password: str
    display_name: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str


class BindRequest(BaseModel):
    session_id: str
    provider: str  # "email"
    email: str
    password: str


class MeResponse(BaseModel):
    user_id: str
    display_name: str
    email: Optional[str]
    email_verified: Optional[bool]
    email_verification_pending: bool
    is_guest: bool
    is_admin: bool
    created_at: str


class UpdateProfileRequest(BaseModel):
    session_id: str
    display_name: str


class UpdateProfileResponse(BaseModel):
    user_id: str
    display_name: str
    is_guest: bool


class UpdateEmailRequest(BaseModel):
    session_id: str
    email: str
    password: str


class UpdateEmailResponse(BaseModel):
    user_id: str
    email: str
    is_guest: bool


class ChangePasswordRequest(BaseModel):
    session_id: str
    old_password: str
    new_password: str


class LogoutRequest(BaseModel):
    session_id: str


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_session(user_id: str, device_id: Optional[str] = None) -> Session:
    return Session(
        session_id=secrets.token_urlsafe(32),
        user_id=user_id,
        expires_at=_utcnow() + timedelta(days=settings.session_expire_days),
        device_id=device_id,
    )


def _name_suffix_from_user_id(user_id: str) -> str:
    uid = str(user_id or "").strip()
    if not uid:
        return _DEFAULT_NAME_SUFFIX
    if len(uid) >= 4:
        return uid[-4:]
    return uid.rjust(4, "0")


def _default_display_name(user_id: str, is_guest: bool) -> str:
    prefix = _GUEST_NAME_PREFIX if is_guest else _ACCOUNT_NAME_PREFIX
    return f"{prefix}{_name_suffix_from_user_id(user_id)}"


def _normalize_display_name(display_name: str) -> str:
    name = str(display_name or "").strip()
    if not name:
        raise HTTPException(400, "display_name is required")
    if len(name) > _DISPLAY_NAME_MAX_LEN:
        raise HTTPException(400, f"display_name too long (max {_DISPLAY_NAME_MAX_LEN})")
    return name


def _display_name_key(display_name: str) -> str:
    return _normalize_display_name(display_name).casefold()


def _normalize_email(email: str) -> str:
    return str(email).strip().casefold()


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

    if len(parts) == 2:
        salt, h = parts
        computed = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
        return hmac.compare_digest(computed, h)

    return False


def _is_legacy_password_hash(credential_hash: str) -> bool:
    if not credential_hash:
        return False
    return credential_hash.count("$") == 1 and not credential_hash.startswith("pbkdf2_sha256$")


def _parse_admin_user_ids() -> set[str]:
    raw = str(settings.admin_user_ids or "")
    return {item.strip() for item in raw.split(",") if item.strip()}


def _configured_admin_email() -> str:
    return _normalize_email(str(settings.admin_email or ""))


def _configured_admin_password() -> str:
    return str(settings.admin_password or "")


def has_admin_access_configured() -> bool:
    if _parse_admin_user_ids():
        return True
    return _configured_admin_email() != "" and _configured_admin_password().strip() != ""


def is_admin_user_id(user_id: str) -> bool:
    admin_user_ids = _parse_admin_user_ids()
    if not admin_user_ids:
        return False
    return "*" in admin_user_ids or user_id in admin_user_ids


async def _get_user_by_id(db: AsyncSession, user_id: str) -> Optional[User]:
    return (await db.execute(select(User).where(User.user_id == user_id))).scalar_one_or_none()


async def _get_email_identity_by_email(db: AsyncSession, email: str) -> Optional[AuthIdentity]:
    return (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "email",
            AuthIdentity.provider_user_id == email,
        )
    )).scalar_one_or_none()


async def _get_email_identity_by_user(db: AsyncSession, user_id: str) -> Optional[AuthIdentity]:
    return (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "email",
        )
    )).scalar_one_or_none()


async def _ensure_configured_admin_account(db: AsyncSession, email: str) -> tuple[Optional[User], Optional[AuthIdentity]]:
    normalized_email = _normalize_email(email)
    configured_email = _configured_admin_email()
    configured_password = _configured_admin_password()
    if configured_email == "" or configured_password.strip() == "" or normalized_email != configured_email:
        return None, None

    identity = await _get_email_identity_by_email(db, configured_email)
    user: Optional[User] = None
    if identity is not None:
        user = await _get_user_by_id(db, identity.user_id)
        if user is None:
            user = User(user_id=identity.user_id)
            db.add(user)
            await db.flush()
    else:
        user = User()
        db.add(user)
        await db.flush()
        identity = AuthIdentity(
            provider="email",
            provider_user_id=configured_email,
            user_id=user.user_id,
            verified=True,
        )
        db.add(identity)

    identity.credential_hash = _hash_password(configured_password)
    identity.verified = True

    configured_name = str(settings.admin_display_name or "").strip()
    if configured_name:
        user.display_name = configured_name
    elif str(user.display_name or "").strip() == "":
        user.display_name = _default_display_name(user.user_id, False)

    await db.flush()
    return user, identity


async def _is_guest_user(db: AsyncSession, user_id: str) -> bool:
    email_identity = (await db.execute(
        select(AuthIdentity.id).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "email",
        )
    )).scalar_one_or_none()
    if email_identity is not None:
        return False
    guest_identity = (await db.execute(
        select(AuthIdentity.id).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "guest",
        )
    )).scalar_one_or_none()
    return guest_identity is not None


async def _ensure_display_name_available(
    db: AsyncSession,
    display_name: str,
    exclude_user_id: str = "",
) -> None:
    normalized = _display_name_key(display_name)
    stmt = select(User.user_id).where(
        User.display_name.is_not(None),
        func.lower(User.display_name) == normalized,
    )
    if str(exclude_user_id).strip():
        stmt = stmt.where(User.user_id != str(exclude_user_id).strip())
    exists = (await db.execute(stmt)).scalar_one_or_none()
    if exists is not None:
        raise HTTPException(409, "display_name already taken")


async def is_admin_user(db: AsyncSession, user_id: str) -> bool:
    if is_admin_user_id(user_id):
        return True
    configured_email = _configured_admin_email()
    if configured_email == "":
        return False
    email_identity = await _get_email_identity_by_user(db, user_id)
    if email_identity is None:
        return False
    return str(email_identity.provider_user_id) == configured_email


def _is_reserved_admin_email(email: str) -> bool:
    configured_email = _configured_admin_email()
    return configured_email != "" and _normalize_email(email) == configured_email


def _resolve_display_name(user: User, is_guest: bool) -> tuple[str, bool]:
    existing = str(user.display_name or "").strip()
    guest_default = _default_display_name(user.user_id, True)
    if existing:
        if not is_guest and existing == guest_default:
            upgraded = _default_display_name(user.user_id, False)
            if upgraded != existing:
                user.display_name = upgraded
                return upgraded, True
        return existing, False
    default_name = _default_display_name(user.user_id, is_guest)
    user.display_name = default_name
    return default_name, True


async def _build_auth_payload(db: AsyncSession, user: User, session_id: str) -> dict:
    is_guest = await _is_guest_user(db, user.user_id)
    display_name, _ = _resolve_display_name(user, is_guest)
    return {
        "user_id": user.user_id,
        "session_id": session_id,
        "display_name": display_name,
        "is_guest": is_guest,
    }


async def get_current_user(
    db: AsyncSession = Depends(get_db),
    session_id: str = "",
) -> Session:
    if not session_id:
        raise HTTPException(401, "missing session_id")
    stmt = select(Session).where(
        Session.session_id == session_id,
        Session.revoked_at.is_(None),
        Session.expires_at > _utcnow(),
    )
    sess = (await db.execute(stmt)).scalar_one_or_none()
    if not sess:
        raise HTTPException(401, "invalid or expired session")
    return sess


@router.post("/guest", response_model=AuthResponse)
async def guest_login(req: GuestRequest, db: AsyncSession = Depends(get_db)):
    if not req.device_id:
        raise HTTPException(400, "device_id is required")

    identity = (await db.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "guest",
            AuthIdentity.provider_user_id == req.device_id,
        )
    )).scalar_one_or_none()

    if identity:
        user = await _get_user_by_id(db, identity.user_id)
        if user is None:
            user = User(user_id=identity.user_id)
            db.add(user)
            await db.flush()
    else:
        user = User()
        db.add(user)
        await db.flush()
        db.add(AuthIdentity(provider="guest", provider_user_id=req.device_id, user_id=user.user_id))

    sess = _new_session(user.user_id, req.device_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


@router.post("/register", response_model=AuthResponse)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    if not req.email or not req.password:
        raise HTTPException(400, "email and password are required")

    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")
    if _is_reserved_admin_email(email):
        raise HTTPException(409, "email already registered")
    exists = await _get_email_identity_by_email(db, email)
    if exists:
        raise HTTPException(409, "email already registered")

    normalized_display_name = _normalize_display_name(req.display_name) if req.display_name is not None else None
    if normalized_display_name is not None:
        await _ensure_display_name_available(db, normalized_display_name)

    user = User()
    db.add(user)
    await db.flush()
    user.display_name = normalized_display_name if normalized_display_name else _default_display_name(user.user_id, False)
    db.add(AuthIdentity(
        provider="email",
        provider_user_id=email,
        user_id=user.user_id,
        credential_hash=_hash_password(req.password),
        verified=True,
    ))
    sess = _new_session(user.user_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


@router.post("/login", response_model=AuthResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    email = _normalize_email(req.email)
    if _is_reserved_admin_email(email) and req.password == _configured_admin_password():
        user, identity = await _ensure_configured_admin_account(db, email)
        if user is None or identity is None:
            raise HTTPException(401, "invalid email or password")
        sess = _new_session(identity.user_id)
        db.add(sess)
        payload = await _build_auth_payload(db, user, sess.session_id)
        await db.commit()
        return AuthResponse(**payload)

    identity = await _get_email_identity_by_email(db, email)
    if not identity or not _verify_password(req.password, identity.credential_hash):
        raise HTTPException(401, "invalid email or password")

    if identity.credential_hash and _is_legacy_password_hash(identity.credential_hash):
        identity.credential_hash = _hash_password(req.password)

    user = await _get_user_by_id(db, identity.user_id)
    if user is None:
        raise HTTPException(404, "user not found")
    sess = _new_session(identity.user_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


@router.post("/bind", response_model=AuthResponse)
async def bind(req: BindRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    if str(req.provider).strip() != "email":
        raise HTTPException(400, "unsupported provider")
    if not req.password:
        raise HTTPException(400, "password is required")

    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")
    if _is_reserved_admin_email(email):
        raise HTTPException(409, "email already registered")

    identity = await _get_email_identity_by_user(db, sess.user_id)
    existing = await _get_email_identity_by_email(db, email)
    if existing is not None and existing.user_id != sess.user_id:
        raise HTTPException(409, "email already registered")

    if identity is None:
        identity = AuthIdentity(
            provider="email",
            provider_user_id=email,
            user_id=sess.user_id,
            verified=True,
        )
        db.add(identity)
    else:
        identity.provider_user_id = email
        identity.verified = True
    identity.credential_hash = _hash_password(req.password)

    user = await _get_user_by_id(db, sess.user_id)
    if user is None:
        raise HTTPException(404, "user not found")
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


@router.get("/me", response_model=MeResponse)
async def get_me(session_id: str = "", db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one()
    email_identity = await _get_email_identity_by_user(db, sess.user_id)
    is_guest = await _is_guest_user(db, sess.user_id)

    old_display_name = str(user.display_name or "").strip()
    display_name, changed = _resolve_display_name(user, is_guest)
    if changed and display_name != old_display_name:
        await db.commit()

    return MeResponse(
        user_id=user.user_id,
        display_name=display_name,
        email=email_identity.provider_user_id if email_identity else None,
        email_verified=(True if email_identity else None),
        email_verification_pending=False,
        is_guest=is_guest,
        is_admin=await is_admin_user(db, user.user_id),
        created_at=user.created_at.isoformat(),
    )


@router.put("/profile", response_model=UpdateProfileResponse)
async def update_profile(req: UpdateProfileRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    is_guest = await _is_guest_user(db, sess.user_id)
    if is_guest:
        raise HTTPException(403, "guest profile is read-only")
    user = await _get_user_by_id(db, sess.user_id)
    if user is None:
        raise HTTPException(404, "user not found")
    target_name = _normalize_display_name(req.display_name)
    await _ensure_display_name_available(db, target_name, exclude_user_id=user.user_id)
    user.display_name = target_name
    await db.commit()
    return UpdateProfileResponse(
        user_id=user.user_id,
        display_name=str(user.display_name),
        is_guest=is_guest,
    )


@router.put("/email", response_model=UpdateEmailResponse)
async def update_email(req: UpdateEmailRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    identity = await _get_email_identity_by_user(db, sess.user_id)
    if not identity:
        raise HTTPException(400, "no email identity bound")
    if not _verify_password(req.password, identity.credential_hash):
        raise HTTPException(401, "incorrect password")

    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")
    if _is_reserved_admin_email(email) and str(identity.provider_user_id) != _configured_admin_email():
        raise HTTPException(409, "email already registered")
    existing = await _get_email_identity_by_email(db, email)
    if existing is not None and existing.user_id != sess.user_id:
        raise HTTPException(409, "email already registered")

    identity.provider_user_id = email
    identity.verified = True
    await db.commit()
    return UpdateEmailResponse(
        user_id=sess.user_id,
        email=email,
        is_guest=await _is_guest_user(db, sess.user_id),
    )


@router.put("/password")
async def change_password(req: ChangePasswordRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    identity = await _get_email_identity_by_user(db, sess.user_id)
    if not identity:
        raise HTTPException(400, "no email identity bound")

    if not _verify_password(req.old_password, identity.credential_hash):
        raise HTTPException(401, "incorrect old password")
    if not req.new_password:
        raise HTTPException(400, "new_password is required")

    identity.credential_hash = _hash_password(req.new_password)
    await db.commit()
    return {"ok": True}


@router.post("/logout")
async def logout(req: LogoutRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    sess.revoked_at = _utcnow()
    await db.commit()
    return {"ok": True}
