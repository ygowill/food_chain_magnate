import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.guest_identity_cleanup import cleanup_upgraded_guest_identities
from app.models import AuthIdentity, User


@pytest.mark.asyncio
async def test_guest_identity_cleanup_dry_run_keeps_records(db_session: AsyncSession):
    user = User(user_id="user_cleanup_dry")
    db_session.add(user)
    db_session.add(AuthIdentity(
        provider="email",
        provider_user_id="cleanup-dry@b.com",
        user_id=user.user_id,
        verified=True,
    ))
    db_session.add(AuthIdentity(
        provider="guest",
        provider_user_id="device-cleanup-dry",
        user_id=user.user_id,
    ))
    await db_session.commit()

    report = await cleanup_upgraded_guest_identities(db_session, dry_run=True)

    assert report.dry_run is True
    assert report.affected_users == 1
    assert report.removed_identities == 0
    assert len(report.candidates) == 1

    guest_identity = (await db_session.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "guest",
            AuthIdentity.user_id == user.user_id,
        )
    )).scalar_one_or_none()
    assert guest_identity is not None


@pytest.mark.asyncio
async def test_guest_identity_cleanup_apply_removes_only_guest_identity(db_session: AsyncSession):
    upgraded = User(user_id="user_cleanup_apply")
    untouched = User(user_id="user_cleanup_guest_only")
    db_session.add_all([upgraded, untouched])
    db_session.add(AuthIdentity(
        provider="email",
        provider_user_id="cleanup-apply@b.com",
        user_id=upgraded.user_id,
        verified=True,
    ))
    db_session.add(AuthIdentity(
        provider="guest",
        provider_user_id="device-cleanup-apply",
        user_id=upgraded.user_id,
    ))
    db_session.add(AuthIdentity(
        provider="guest",
        provider_user_id="device-guest-only",
        user_id=untouched.user_id,
    ))
    await db_session.commit()

    report = await cleanup_upgraded_guest_identities(db_session, dry_run=False)

    assert report.dry_run is False
    assert report.affected_users == 1
    assert report.removed_identities == 1

    upgraded_guest = (await db_session.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "guest",
            AuthIdentity.user_id == upgraded.user_id,
        )
    )).scalar_one_or_none()
    assert upgraded_guest is None

    upgraded_email = (await db_session.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "email",
            AuthIdentity.user_id == upgraded.user_id,
        )
    )).scalar_one_or_none()
    assert upgraded_email is not None

    untouched_guest = (await db_session.execute(
        select(AuthIdentity).where(
            AuthIdentity.provider == "guest",
            AuthIdentity.user_id == untouched.user_id,
        )
    )).scalar_one_or_none()
    assert untouched_guest is not None
