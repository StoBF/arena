@echo off
setlocal enabledelayedexpansion

REM Go to project root
cd /d %~dp0

REM --- PostgreSQL process & readiness setup ---
set PG_PATH=%PG_PATH%
if "%PG_PATH%"=="" set PG_PATH=D:\Games\pgsql
set PG_DATA=%PG_DATA%
if "%PG_DATA%"=="" set PG_DATA=%PG_PATH%\data
set PG_PORT=5432

echo [START] Checking PostgreSQL readiness...
"%PG_PATH%\bin\pg_isready.exe" -h 127.0.0.1 -p %PG_PORT% >nul 2>&1
if errorlevel 1 (
	echo [START] PostgreSQL is not ready. Starting instance...
	"%PG_PATH%\bin\pg_ctl.exe" -D "%PG_DATA%" -w -t 120 start
) else (
	echo [START] PostgreSQL is already accepting connections.
)

echo [START] Waiting for PostgreSQL to become ready...
set /a tries=0
:wait_pg
"%PG_PATH%\bin\pg_isready.exe" -h 127.0.0.1 -p %PG_PORT% >nul 2>&1
if not errorlevel 1 goto pg_ready
set /a tries+=1
if !tries! geq 30 (
	echo [ERROR] PostgreSQL did not become ready in time.
	exit /b 1
)
timeout /t 2 >nul
goto wait_pg

:pg_ready
echo [START] PostgreSQL is ready.

REM --- Uvicorn startup (module form is more stable on Windows) ---
if exist ".venv\Scripts\python.exe" (
	set PYTHON_EXE=.venv\Scripts\python.exe
) else (
	set PYTHON_EXE=python
)

echo [START] Starting FastAPI server with reload...
"%PYTHON_EXE%" -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8081 --env-file .env
