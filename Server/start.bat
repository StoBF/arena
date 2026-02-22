@echo off
REM Перехід в корінь проекту (за потреби)
cd /d %~dp0

REM Опціонально можна явно задати змінні (якщо dotenv не спрацює)
REM set DATABASE_URL=postgresql+asyncpg://postgres:password@localhost:5432/hero_manager
REM set JWT_SECRET_KEY=your_jwt_secret_key
REM ...

REM Запуск Uvicorn з автозавантаженням
uvicorn app.main:app --reload --port 8081 --env-file .env
