from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, UniqueConstraint, Boolean, Integer, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_id() -> str:
    return uuid.uuid4().hex


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    user_id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    status: Mapped[str] = mapped_column(String, default="active")
    display_name: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


class AuthIdentity(Base):
    __tablename__ = "auth_identities"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    provider: Mapped[str] = mapped_column(String, nullable=False)
    provider_user_id: Mapped[str] = mapped_column(String, nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), nullable=False)
    credential_hash: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)

    __table_args__ = (UniqueConstraint("provider", "provider_user_id"),)


class EmailVerificationToken(Base):
    __tablename__ = "email_verification_tokens"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    auth_identity_id: Mapped[str] = mapped_column(ForeignKey("auth_identities.id"), nullable=False)
    purpose: Mapped[str] = mapped_column(String, nullable=False)
    token_hash: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    last_sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    send_count: Mapped[int] = mapped_column(Integer, default=1)


class Session(Base):
    __tablename__ = "sessions"

    session_id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    device_id: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


def _new_room_code() -> str:
    import random
    chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    return "".join(random.choices(chars, k=6))


class Room(Base):
    __tablename__ = "rooms"

    room_id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    room_code: Mapped[str] = mapped_column(String, unique=True, default=_new_room_code)
    owner_user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), nullable=False)
    game_server_id: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    status: Mapped[str] = mapped_column(String, default="Lobby")
    join_policy: Mapped[str] = mapped_column(String, default="public")
    password_hash: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    config_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    ws_url: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)


class RoomMember(Base):
    __tablename__ = "room_members"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    room_id: Mapped[str] = mapped_column(ForeignKey("rooms.room_id"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), nullable=False)
    role: Mapped[str] = mapped_column(String, nullable=False)
    seat_index: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    left_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


class Match(Base):
    __tablename__ = "matches"

    match_id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    room_id: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    room_code: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    status: Mapped[str] = mapped_column(String, default="completed")
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_sec: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    player_count: Mapped[int] = mapped_column(Integer, default=0)
    seed: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    schema_version: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    game_version: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    final_hash: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    summary_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


class MatchParticipant(Base):
    __tablename__ = "match_participants"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    match_id: Mapped[str] = mapped_column(ForeignKey("matches.match_id"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), nullable=False)
    role: Mapped[str] = mapped_column(String, nullable=False)
    seat_index: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    result: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    score_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)


class MatchReplay(Base):
    __tablename__ = "match_replays"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    match_id: Mapped[str] = mapped_column(ForeignKey("matches.match_id"), nullable=False, unique=True)
    storage_uri: Mapped[str] = mapped_column(String, nullable=False)
    checksum: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    size_bytes: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


class DeviceCode(Base):
    __tablename__ = "device_codes"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_id)
    device_code: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    user_code: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    device_id: Mapped[str] = mapped_column(String, nullable=False)
    user_id: Mapped[Optional[str]] = mapped_column(ForeignKey("users.user_id"), nullable=True)
    status: Mapped[str] = mapped_column(String, default="pending")  # pending | authorized | consumed | expired
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


class GameServer(Base):
    __tablename__ = "game_servers"

    game_server_id: Mapped[str] = mapped_column(String, primary_key=True)
    last_heartbeat_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    status: Mapped[str] = mapped_column(String, default="healthy")
