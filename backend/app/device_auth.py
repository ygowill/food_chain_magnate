import secrets
import string
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.models import DeviceCode, Session
from app.auth import get_current_user, _new_session

router = APIRouter(prefix="/v1/auth/device", tags=["device-auth"])


def _new_device_code() -> str:
    return secrets.token_urlsafe(32)


def _new_user_code() -> str:
    chars = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(chars) for _ in range(8))


class DeviceCodeRequest(BaseModel):
    device_id: str


class DeviceCodeResponse(BaseModel):
    device_code: str
    user_code: str
    verification_uri: str
    expires_in: int
    interval: int


class AuthorizeRequest(BaseModel):
    user_code: str
    session_id: str


class TokenRequest(BaseModel):
    device_code: str
    device_id: str


@router.post("/code", response_model=DeviceCodeResponse)
async def request_device_code(req: DeviceCodeRequest, db: AsyncSession = Depends(get_db)):
    if not req.device_id:
        raise HTTPException(400, "device_id is required")

    dc = DeviceCode(
        device_code=_new_device_code(),
        user_code=_new_user_code(),
        device_id=req.device_id,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.device_code_expire_seconds),
    )
    db.add(dc)
    await db.commit()

    return DeviceCodeResponse(
        device_code=dc.device_code,
        user_code=dc.user_code,
        verification_uri=f"{settings.web_origin}/device?code={dc.user_code}",
        expires_in=settings.device_code_expire_seconds,
        interval=settings.device_code_poll_interval,
    )


@router.post("/authorize")
async def authorize_device(req: AuthorizeRequest, db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=req.session_id)

    stmt = select(DeviceCode).where(
        DeviceCode.user_code == req.user_code,
        DeviceCode.status == "pending",
        DeviceCode.expires_at > datetime.now(timezone.utc),
    )
    dc = (await db.execute(stmt)).scalar_one_or_none()
    if not dc:
        raise HTTPException(404, "invalid or expired user_code")

    dc.user_id = sess.user_id
    dc.status = "authorized"
    await db.commit()
    return {"ok": True}


@router.post("/token")
async def poll_device_token(req: TokenRequest, db: AsyncSession = Depends(get_db)):
    stmt = select(DeviceCode).where(
        DeviceCode.device_code == req.device_code,
        DeviceCode.device_id == req.device_id,
    )
    dc = (await db.execute(stmt)).scalar_one_or_none()
    if not dc:
        raise HTTPException(404, "device_code not found")

    if dc.expires_at <= datetime.now(timezone.utc):
        dc.status = "expired"
        await db.commit()
        raise HTTPException(410, "device_code expired")

    if dc.status == "pending":
        raise HTTPException(428, "authorization_pending")

    if dc.status in ("consumed", "expired"):
        raise HTTPException(410, "device_code already used or expired")

    # status == "authorized"
    dc.status = "consumed"
    sess = _new_session(dc.user_id, dc.device_id)
    db.add(sess)
    await db.commit()
    return {"user_id": dc.user_id, "session_id": sess.session_id}
