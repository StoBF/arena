from typing import List
import os

class Settings:
    # Reads DATABASE_URL from environment; falls back to in-memory SQLite for testing
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
    JWT_SECRET_KEY: str = "supersecretkey"
    JWT_ALGORITHM: str = "HS256"
    
    # Token expiration times (separate for access and refresh)
    JWT_ACCESS_TOKEN_MINUTES: int = 20  # Short-lived access token
    JWT_REFRESH_TOKEN_DAYS: int = 7    # Long-lived refresh token
    JWT_EXPIRATION_MINUTES: int = 20   # Kept for backwards compatibility
    
    # Token rotation
    TOKEN_ROTATION_ENABLED: bool = True  # Enable token rotation for security
    
    ALLOWED_ORIGINS: str = "*"
    REDIS_URL: str = os.getenv("REDIS_URL", "")
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", os.getenv("APP_PORT", "8081")))
    APP_ENV: str = os.getenv("APP_ENV", "development")

    # Cookie/auth behavior
    COOKIE_SECURE: bool = os.getenv("COOKIE_SECURE", "false").lower() in ("1", "true", "yes")
    COOKIE_SAMESITE: str = os.getenv("COOKIE_SAMESITE", "lax")

    # Startup DB readiness retries (helps when PostgreSQL is recovering after unclean shutdown)
    DB_CONNECT_RETRIES: int = int(os.getenv("DB_CONNECT_RETRIES", "30"))
    DB_CONNECT_RETRY_DELAY_SECONDS: float = float(os.getenv("DB_CONNECT_RETRY_DELAY_SECONDS", "2"))

    EMAIL_HOST: str = "smtp.example.com"
    EMAIL_PORT: int = 587
    EMAIL_FROM: str = "noreply@example.com"
    EMAIL_HOST_USER: str = ""
    EMAIL_HOST_PASSWORD: str = ""
    EMAIL_USE_TLS: bool = True

    @property
    def allowed_origins_list(self) -> List[str]:
        if self.ALLOWED_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

settings = Settings()
