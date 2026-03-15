from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.mailer import send_verification_email
from app.models import AuthIdentity, EmailVerificationToken, Session, User

router = APIRouter(prefix="/v1/auth", tags=["auth"])

_DISPLAY_NAME_MAX_LEN = 24
_GUEST_NAME_PREFIX = "游客#"
_ACCOUNT_NAME_PREFIX = "账号#"
_DEFAULT_NAME_SUFFIX = "0000"
_PENDING_VERIFICATION_STATUS = "pending_verification"
_PURPOSE_REGISTER = "register"
_PURPOSE_BIND = "bind"
_EMAIL_NOT_VERIFIED_CODE = "EMAIL_NOT_VERIFIED"


class GuestRequest(BaseModel):
    device_id: str


class AuthResponse(BaseModel):
    user_id: str
    session_id: str
    display_name: str
    is_guest: bool


class PendingVerificationResponse(BaseModel):
    status: str
    email: str
    resend_after_sec: int


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


class ConfirmVerificationRequest(BaseModel):
    token: str


class ResendVerificationRequest(BaseModel):
    email: Optional[str] = None
    session_id: Optional[str] = None


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


class ChangePasswordRequest(BaseModel):
    session_id: str
    old_password: str
    new_password: str


class LogoutRequest(BaseModel):
    session_id: str


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _ensure_utc(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


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


def _hash_verification_token(token: str) -> str:
    return hashlib.sha256(str(token).encode("utf-8")).hexdigest()


def _verification_expire_at() -> datetime:
    return _utcnow() + timedelta(minutes=settings.email_verify_expire_minutes)


def _verification_url(token: str) -> str:
    base = str(settings.web_origin or "").rstrip("/")
    return f"{base}/verify-email?{urlencode({'token': token})}"


def _seconds_until_resend_allowed(last_sent_at: Optional[datetime]) -> int:
    normalized = _ensure_utc(last_sent_at)
    if normalized is None:
        return 0
    elapsed = int((_utcnow() - normalized).total_seconds())
    remaining = int(settings.email_verify_resend_cooldown_seconds) - elapsed
    return max(remaining, 0)


def _pending_verification_payload(email: str, resend_after_sec: Optional[int] = None) -> dict:
    return {
        "status": _PENDING_VERIFICATION_STATUS,
        "email": email,
        "resend_after_sec": int(
            settings.email_verify_resend_cooldown_seconds if resend_after_sec is None else resend_after_sec
        ),
    }


def _parse_admin_user_ids() -> set[str]:
    raw = str(settings.admin_user_ids or "")
    return {item.strip() for item in raw.split(",") if item.strip()}


def is_admin_user_id(user_id: str) -> bool:
    admin_user_ids = _parse_admin_user_ids()
    if not admin_user_ids:
        return False
    return "*" in admin_user_ids or user_id in admin_user_ids


def _raise_email_not_verified(email: str, resend_after_sec: int) -> None:
    raise HTTPException(403, {
        "code": _EMAIL_NOT_VERIFIED_CODE,
        "message": "email not verified",
        "email": email,
        "resend_after_sec": resend_after_sec,
    })


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


async def _has_guest_identity(db: AsyncSession, user_id: str) -> bool:
    guest_identity = (await db.execute(
        select(AuthIdentity.id).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "guest",
        )
    )).scalar_one_or_none()
    return guest_identity is not None


async def _is_guest_user(db: AsyncSession, user_id: str) -> bool:
    verified_email_identity = (await db.execute(
        select(AuthIdentity.id).where(
            AuthIdentity.user_id == user_id,
            AuthIdentity.provider == "email",
            AuthIdentity.verified.is_(True),
        )
    )).scalar_one_or_none()
    if verified_email_identity is not None:
        return False
    return await _has_guest_identity(db, user_id)


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


async def _get_latest_verification_token(
    db: AsyncSession,
    auth_identity_id: str,
    purpose: str,
) -> Optional[EmailVerificationToken]:
    return (await db.execute(
        select(EmailVerificationToken)
        .where(
            EmailVerificationToken.auth_identity_id == auth_identity_id,
            EmailVerificationToken.purpose == purpose,
        )
        .order_by(EmailVerificationToken.last_sent_at.desc(), EmailVerificationToken.created_at.desc())
    )).scalars().first()


async def _ensure_verification_email_sent(
    db: AsyncSession,
    identity: AuthIdentity,
    purpose: str,
) -> int:
    existing = await _get_latest_verification_token(db, identity.id, purpose)
    if existing is not None and existing.consumed_at is None:
        remaining = _seconds_until_resend_allowed(existing.last_sent_at)
        if remaining > 0 and _ensure_utc(existing.expires_at) > _utcnow():
            return remaining

    raw_token = secrets.token_urlsafe(32)
    token_hash = _hash_verification_token(raw_token)
    now = _utcnow()
    verification_row = existing
    if verification_row is None:
        verification_row = EmailVerificationToken(
            auth_identity_id=identity.id,
            purpose=purpose,
            token_hash=token_hash,
            expires_at=_verification_expire_at(),
            last_sent_at=now,
            send_count=1,
        )
        db.add(verification_row)
    else:
        verification_row.token_hash = token_hash
        verification_row.expires_at = _verification_expire_at()
        verification_row.consumed_at = None
        verification_row.last_sent_at = now
        verification_row.send_count = int(verification_row.send_count or 0) + 1
    await db.flush()
    await send_verification_email(identity.provider_user_id, _verification_url(raw_token), purpose)
    return int(settings.email_verify_resend_cooldown_seconds)


async def _consume_all_verification_tokens(
    db: AsyncSession,
    auth_identity_id: str,
    consumed_at: datetime,
) -> None:
    rows = (await db.execute(
        select(EmailVerificationToken).where(
            EmailVerificationToken.auth_identity_id == auth_identity_id,
            EmailVerificationToken.consumed_at.is_(None),
        )
    )).scalars().all()
    for row in rows:
        row.consumed_at = consumed_at


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


@router.post("/register", response_model=PendingVerificationResponse, status_code=202)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    if not req.email or not req.password:
        raise HTTPException(400, "email and password are required")

    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")

    normalized_display_name = _normalize_display_name(req.display_name) if req.display_name is not None else None
    identity = await _get_email_identity_by_email(db, email)
    if identity is not None:
        if identity.verified:
            raise HTTPException(409, "email already registered")
        if await _is_guest_user(db, identity.user_id):
            raise HTTPException(409, "email pending verification")
        user = await _get_user_by_id(db, identity.user_id)
        if user is None:
            user = User(user_id=identity.user_id)
            db.add(user)
            await db.flush()
        identity.credential_hash = _hash_password(req.password)
        if normalized_display_name is not None:
            user.display_name = normalized_display_name
        resend_after_sec = await _ensure_verification_email_sent(db, identity, _PURPOSE_REGISTER)
        await db.commit()
        return PendingVerificationResponse(**_pending_verification_payload(email, resend_after_sec))

    user = User()
    db.add(user)
    await db.flush()
    user.display_name = normalized_display_name if normalized_display_name else _default_display_name(user.user_id, False)
    identity = AuthIdentity(
        provider="email",
        provider_user_id=email,
        user_id=user.user_id,
        credential_hash=_hash_password(req.password),
        verified=False,
    )
    db.add(identity)
    await db.flush()
    resend_after_sec = await _ensure_verification_email_sent(db, identity, _PURPOSE_REGISTER)
    await db.commit()
    return PendingVerificationResponse(**_pending_verification_payload(email, resend_after_sec))


@router.post("/login", response_model=AuthResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    email = _normalize_email(req.email)
    identity = await _get_email_identity_by_email(db, email)
    if not identity or not _verify_password(req.password, identity.credential_hash):
        raise HTTPException(401, "invalid email or password")

    if identity.credential_hash and _is_legacy_password_hash(identity.credential_hash):
        identity.credential_hash = _hash_password(req.password)

    if not identity.verified:
        latest_token = await _get_latest_verification_token(db, identity.id, _PURPOSE_REGISTER)
        resend_after_sec = _seconds_until_resend_allowed(latest_token.last_sent_at) if latest_token else 0
        _raise_email_not_verified(email, resend_after_sec)

    user = await _get_user_by_id(db, identity.user_id)
    if user is None:
        raise HTTPException(404, "user not found")
    sess = _new_session(identity.user_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


@router.post("/bind", response_model=PendingVerificationResponse, status_code=202)
async def bind(req: BindRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    if str(req.provider).strip() != "email":
        raise HTTPException(400, "unsupported provider")
    if not req.password:
        raise HTTPException(400, "password is required")

    email = _normalize_email(req.email)
    if not email:
        raise HTTPException(400, "email is required")

    user = await _get_user_by_id(db, sess.user_id)
    if user is None:
        raise HTTPException(404, "user not found")

    current_identity = await _get_email_identity_by_user(db, sess.user_id)
    target_identity = await _get_email_identity_by_email(db, email)

    if target_identity is not None and target_identity.user_id != sess.user_id:
        if target_identity.verified:
            raise HTTPException(409, "email already registered")
        raise HTTPException(409, "email pending verification")

    identity = current_identity
    if identity is not None and identity.verified and identity.provider_user_id != email:
        raise HTTPException(409, "email already registered")

    if identity is None:
        identity = AuthIdentity(
            provider="email",
            provider_user_id=email,
            user_id=sess.user_id,
            verified=False,
        )
        db.add(identity)
        await db.flush()
    else:
        identity.provider_user_id = email

    identity.credential_hash = _hash_password(req.password)
    identity.verified = False
    resend_after_sec = await _ensure_verification_email_sent(db, identity, _PURPOSE_BIND)
    await db.commit()
    return PendingVerificationResponse(**_pending_verification_payload(email, resend_after_sec))


@router.post("/email-verification/confirm", response_model=AuthResponse)
async def confirm_email_verification(req: ConfirmVerificationRequest, db: AsyncSession = Depends(get_db)):
    token = str(req.token or "").strip()
    if not token:
        raise HTTPException(400, "token is required")

    verification_row = (await db.execute(
        select(EmailVerificationToken).where(
            EmailVerificationToken.token_hash == _hash_verification_token(token),
        )
    )).scalar_one_or_none()
    if verification_row is None or verification_row.consumed_at is not None:
        raise HTTPException(400, "invalid verification token")
    if _ensure_utc(verification_row.expires_at) <= _utcnow():
        raise HTTPException(410, "verification token expired")

    identity = (await db.execute(
        select(AuthIdentity).where(AuthIdentity.id == verification_row.auth_identity_id)
    )).scalar_one_or_none()
    if identity is None:
        raise HTTPException(404, "auth identity not found")

    consumed_at = _utcnow()
    identity.verified = True
    verification_row.consumed_at = consumed_at
    await _consume_all_verification_tokens(db, identity.id, consumed_at)

    user = await _get_user_by_id(db, identity.user_id)
    if user is None:
        raise HTTPException(404, "user not found")

    sess = _new_session(identity.user_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


@router.post("/email-verification/resend", response_model=PendingVerificationResponse, status_code=202)
async def resend_email_verification(req: ResendVerificationRequest, db: AsyncSession = Depends(get_db)):
    email = _normalize_email(req.email or "")
    session_id = str(req.session_id or "").strip()
    if email and session_id:
        raise HTTPException(400, "provide either email or session_id")
    if not email and not session_id:
        raise HTTPException(400, "email or session_id is required")

    identity: Optional[AuthIdentity] = None
    purpose = _PURPOSE_REGISTER
    if session_id:
        sess = await get_current_user(db=db, session_id=session_id)
        identity = await _get_email_identity_by_user(db, sess.user_id)
        if identity is None:
            raise HTTPException(400, "no email identity bound")
        purpose = _PURPOSE_BIND if await _is_guest_user(db, sess.user_id) else _PURPOSE_REGISTER
        email = identity.provider_user_id
    else:
        identity = await _get_email_identity_by_email(db, email)
        if identity is None:
            raise HTTPException(404, "email not found")
        purpose = _PURPOSE_BIND if await _is_guest_user(db, identity.user_id) else _PURPOSE_REGISTER

    if identity.verified:
        raise HTTPException(400, "email already verified")

    resend_after_sec = await _ensure_verification_email_sent(db, identity, purpose)
    await db.commit()
    return PendingVerificationResponse(**_pending_verification_payload(email, resend_after_sec))


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

    email_verified = None if email_identity is None else bool(email_identity.verified)
    return MeResponse(
        user_id=user.user_id,
        display_name=display_name,
        email=email_identity.provider_user_id if email_identity else None,
        email_verified=email_verified,
        email_verification_pending=email_identity is not None and not bool(email_identity.verified),
        is_guest=is_guest,
        is_admin=is_admin_user_id(user.user_id),
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
    user.display_name = _normalize_display_name(req.display_name)
    await db.commit()
    return UpdateProfileResponse(
        user_id=user.user_id,
        display_name=str(user.display_name),
        is_guest=is_guest,
    )


@router.put("/password")
async def change_password(req: ChangePasswordRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    identity = await _get_email_identity_by_user(db, sess.user_id)
    if not identity or not identity.verified:
        raise HTTPException(400, "no verified email identity bound")
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
