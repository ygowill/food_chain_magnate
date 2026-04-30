from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "sqlite+aiosqlite:///./fcm.db"
    hmac_secret: str = "dev-secret-change-in-production"
    internal_api_secret: str = "dev-internal-secret-change-in-production"
    default_ws_url: str = "ws://localhost:7000"
    admin_user_ids: str = ""
    admin_viewer_user_ids: str = ""
    admin_operator_user_ids: str = ""
    admin_superadmin_user_ids: str = ""
    admin_email: str = ""
    admin_password: str = ""
    admin_display_name: str = "Admin"
    replay_storage_dir: str = "./replays"
    password_hash_iterations: int = 200_000
    session_expire_days: int = 30
    web_origin: str = "http://localhost:5173"
    device_code_expire_seconds: int = 600
    device_code_poll_interval: int = 5


settings = Settings()
