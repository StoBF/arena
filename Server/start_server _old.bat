@echo off
REM Переміститися в теку, де лежить .bat та папка app/
cd /d %~dp0

title Game Server Startup
color 0A

set PG_PATH=D:\Games\pgsql
set PG_DATA=%PG_PATH%\data
set PG_PORT=5432
set UVICORN_APP=app.main:app
set PYTHON_PATH=C:\Users\user\AppData\Local\Programs\Python\Python313\python.exe

echo Перевірка чи PostgreSQL вже працює...
netstat -ano | findstr :%PG_PORT% >nul
if %errorlevel%==0 (
    echo PostgreSQL вже запущений.
) else (
    echo Запускаємо PostgreSQL...
    %PG_PATH%\bin\pg_ctl -D "%PG_DATA%" start
    echo Очікуємо запуск PostgreSQL...
    timeout /t 5 >nul
)

echo Перевірка чи uvicorn вже працює...
tasklist | findstr uvicorn.exe >nul
if %errorlevel%==0 (
    echo Uvicorn вже працює. Перезапускаємо...
    taskkill /f /im uvicorn.exe >nul 2>&1
    timeout /t 2 >nul
)

echo Запускаємо Python сервер...
"%PYTHON_PATH%" -m uvicorn app.main:app --host 0.0.0.0 --port 8081 --reload



pause
