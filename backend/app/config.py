from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "sqlite+aiosqlite:///./fcm.db"
    hmac_secret: str = "dev-secret-change-in-production"
    internal_api_secret: str = "dev-internal-secret-change-in-production"
    password_hash_iterations: int = 200_000
    session_expire_days: int = 30


settings = Settings()
