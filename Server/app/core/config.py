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
