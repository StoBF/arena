@echo off
chcp 65001 >nul
setlocal

REM =========================================
REM Game Server Startup with PostgreSQL + Alembic
REM =========================================

cd /d %~dp0

title Game Server Startup
color 0A

REM === Налаштування ===
set "PG_PATH=D:\Games\pgsql"
set "PG_DATA=%PG_PATH%\data"
set "PG_PORT=5432"

REM Використовуємо Python з .venv
set "PYTHON_PATH=%~dp0.venv\Scripts\python.exe"

REM База, яку реально використовує сервер
set "DB_NAME=hero_manager"
set "DB_USER=postgres"

REM API
set "API_HOST=0.0.0.0"
set "API_PORT=8081"

echo =========================================
echo   GAME SERVER STARTUP
echo =========================================
echo.

REM === 1. Перевірка Python у .venv ===
if not exist "%PYTHON_PATH%" (
    echo [ПОМИЛКА] Не знайдено Python у .venv:
    echo %PYTHON_PATH%
    echo.
    echo Спочатку створи або віднови .venv.
    pause
    exit /b 1
)

REM === 2. Перевірка чи PostgreSQL вже працює ===
echo [1/5] Перевірка чи PostgreSQL вже працює...
netstat -ano | findstr :%PG_PORT% >nul
if %errorlevel%==0 (
    echo PostgreSQL вже запущений.
) else (
    echo PostgreSQL не запущений. Запускаємо...
    "%PG_PATH%\bin\pg_ctl.exe" -D "%PG_DATA%" start
    REM НЕ перевіряємо errorlevel тут, бо у твоєму setup pg_ctl може повернути не 0 навіть коли БД реально стартувала
)

echo.

REM === 3. Очікування готовності PostgreSQL ===
echo [2/5] Очікуємо готовність PostgreSQL...
set "DB_READY=0"

for /L %%i in (1,1,20) do (
    "%PG_PATH%\bin\psql.exe" -U %DB_USER% -d %DB_NAME% -c "SELECT 1;" >nul 2>&1
    if not errorlevel 1 (
        set "DB_READY=1"
        goto :db_ready
    )
    timeout /t 2 >nul
)

:db_ready
if "%DB_READY%"=="0" (
    echo [ПОМИЛКА] PostgreSQL не став доступним вчасно.
    echo Перевір:
    echo 1. чи правильний DB_NAME
    echo 2. чи PostgreSQL реально стартує
    echo 3. чи psql може підключитись до %DB_NAME%
    pause
    exit /b 1
)

echo PostgreSQL готовий.
echo.

REM === 4. Зупинка старого uvicorn, якщо працює ===
echo [3/5] Перевірка чи uvicorn вже працює...
tasklist | findstr uvicorn.exe >nul
if %errorlevel%==0 (
    echo Знайдено запущений uvicorn. Зупиняємо...
    taskkill /f /im uvicorn.exe >nul 2>&1
    timeout /t 2 >nul
) else (
    echo Uvicorn не запущений.
)
echo.

REM === 5. Запуск міграцій Alembic ===
echo [4/5] Запускаємо міграції Alembic...
"%PYTHON_PATH%" -m alembic upgrade head
if %errorlevel% neq 0 (
    echo.
    echo [ПОМИЛКА] Міграції не пройшли.
    echo Сервер НЕ буде запущений, щоб не працювати з кривою схемою БД.
    pause
    exit /b 1
)

echo Міграції застосовані успішно.
echo.

REM === 6. Запуск FastAPI/Uvicorn ===
echo [5/5] Запускаємо Python сервер...
"%PYTHON_PATH%" -m uvicorn app.main:app --host %API_HOST% --port %API_PORT% --reload

echo.
echo Сервер завершив роботу.
pause
exit /b 0