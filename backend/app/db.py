from sqlalchemy import inspect, text
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.config import settings
from app.models import Base

engine = create_async_engine(settings.database_url)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


def _ensure_schema_migrations(sync_conn) -> None:
    inspector = inspect(sync_conn)
    user_columns = {str(col.get("name", "")).strip() for col in inspector.get_columns("users")}
    if "display_name" not in user_columns:
        sync_conn.execute(text("ALTER TABLE users ADD COLUMN display_name VARCHAR"))

    room_member_columns = {str(col.get("name", "")).strip() for col in inspector.get_columns("room_members")}
    if "member_status" not in room_member_columns:
        sync_conn.execute(text("ALTER TABLE room_members ADD COLUMN member_status VARCHAR DEFAULT 'active'"))
        sync_conn.execute(text("UPDATE room_members SET member_status = 'active' WHERE member_status IS NULL"))

    room_member_indexes = {str(idx.get("name", "")).strip() for idx in inspector.get_indexes("room_members")}
    if "ix_room_members_active_user_unique" not in room_member_indexes:
        sync_conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_room_members_active_user_unique "
            "ON room_members (room_id, user_id) WHERE left_at IS NULL"
        ))
    if "ix_room_members_active_seat_unique" not in room_member_indexes:
        sync_conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_room_members_active_seat_unique "
            "ON room_members (room_id, seat_index) "
            "WHERE left_at IS NULL AND seat_index IS NOT NULL"
        ))


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(_ensure_schema_migrations)


async def get_db():
    async with async_session() as session:
        yield session
