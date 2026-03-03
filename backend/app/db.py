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


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(_ensure_schema_migrations)


async def get_db():
    async with async_session() as session:
        yield session
