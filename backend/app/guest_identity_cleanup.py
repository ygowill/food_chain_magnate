from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AuthIdentity


@dataclass
class GuestIdentityCleanupCandidate:
    identity_id: str
    user_id: str
    device_id: str


@dataclass
class GuestIdentityCleanupReport:
    dry_run: bool
    affected_users: int
    removed_identities: int
    candidates: list[GuestIdentityCleanupCandidate]


async def find_upgraded_guest_identity_candidates(db: AsyncSession) -> list[GuestIdentityCleanupCandidate]:
    email_user_ids = select(AuthIdentity.user_id).where(AuthIdentity.provider == "email")
    rows = (await db.execute(
        select(
            AuthIdentity.id,
            AuthIdentity.user_id,
            AuthIdentity.provider_user_id,
        ).where(
            AuthIdentity.provider == "guest",
            AuthIdentity.user_id.in_(email_user_ids),
        ).order_by(AuthIdentity.user_id.asc(), AuthIdentity.provider_user_id.asc())
    )).all()
    return [
        GuestIdentityCleanupCandidate(
            identity_id=str(row.id),
            user_id=str(row.user_id),
            device_id=str(row.provider_user_id),
        )
        for row in rows
    ]


async def cleanup_upgraded_guest_identities(db: AsyncSession, dry_run: bool = True) -> GuestIdentityCleanupReport:
    candidates = await find_upgraded_guest_identity_candidates(db)
    if not dry_run:
        for candidate in candidates:
            identity = await db.get(AuthIdentity, candidate.identity_id)
            if identity is not None:
                await db.delete(identity)
        await db.commit()

    affected_users = len({candidate.user_id for candidate in candidates})
    return GuestIdentityCleanupReport(
        dry_run=dry_run,
        affected_users=affected_users,
        removed_identities=0 if dry_run else len(candidates),
        candidates=candidates,
    )
