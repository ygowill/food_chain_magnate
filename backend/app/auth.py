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


def _new_session(user_id: str, device_id: str | None = None) -> Session:
    return Session(
        session_id=secrets.token_urlsafe(32),
        user_id=user_id,
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.session_expire_days),
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


def _resolve_display_name(user: User, is_guest: bool) -> tuple[str, bool]:
    existing = str(user.display_name or "").strip()
    guest_default = _default_display_name(user.user_id, True)
    if existing:
        # 已升级账号若仍是旧游客默认名，自动切换为账号默认名。
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
        user = (await db.execute(select(User).where(User.user_id == identity.user_id))).scalar_one_or_none()
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
    display_name: str | None = None


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

    normalized_display_name = _normalize_display_name(req.display_name) if req.display_name is not None else None
    user = User()
    db.add(user)
    await db.flush()
    user.display_name = normalized_display_name if normalized_display_name else _default_display_name(user.user_id, False)
    db.add(AuthIdentity(
        provider="email",
        provider_user_id=email,
        user_id=user.user_id,
        credential_hash=_hash_password(req.password),
        verified=False,
    ))
    sess = _new_session(user.user_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


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

    user = (await db.execute(select(User).where(User.user_id == identity.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    sess = _new_session(identity.user_id)
    db.add(sess)
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


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
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    payload = await _build_auth_payload(db, user, sess.session_id)
    await db.commit()
    return AuthResponse(**payload)


class MeResponse(BaseModel):
    user_id: str
    display_name: str
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
    is_guest = has_guest is not None and email_identity is None
    old_display_name = str(user.display_name or "").strip()
    display_name, changed = _resolve_display_name(user, is_guest)
    if changed and display_name != old_display_name:
        await db.commit()

    return MeResponse(
        user_id=user.user_id,
        display_name=display_name,
        email=email_identity.provider_user_id if email_identity else None,
        is_guest=is_guest,
        is_admin=is_admin_user_id(user.user_id),
        created_at=user.created_at.isoformat(),
    )


class UpdateProfileRequest(BaseModel):
    session_id: str
    display_name: str


class UpdateProfileResponse(BaseModel):
    user_id: str
    display_name: str
    is_guest: bool


@router.put("/profile", response_model=UpdateProfileResponse)
async def update_profile(req: UpdateProfileRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)
    is_guest = await _is_guest_user(db, sess.user_id)
    if is_guest:
        raise HTTPException(403, "guest profile is read-only")
    user = (await db.execute(select(User).where(User.user_id == sess.user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "user not found")
    user.display_name = _normalize_display_name(req.display_name)
    await db.commit()
    return UpdateProfileResponse(
        user_id=user.user_id,
        display_name=str(user.display_name),
        is_guest=is_guest,
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
