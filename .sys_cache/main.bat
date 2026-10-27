@echo off
setlocal enabledelayedexpansion
set SCRIPT_DIR=%~dp0

:: 1. Attempt to connect to background worker on port 58080
netstat -ano | findstr 58080 >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :server_ready

if exist "%SCRIPT_DIR%svc.vbs" (
    wscript.exe "%SCRIPT_DIR%svc.vbs"
)

set /a WAIT_COUNT=0
:wait_loop
timeout /t 1 /nobreak >nul
netstat -ano | findstr 58080 >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :server_ready
set /a WAIT_COUNT+=1
if %WAIT_COUNT% LSS 15 goto :wait_loop

:server_ready
timeout /t 1 /nobreak >nul

:: 2. Check for Embedded Python or System Python
set PY_BIN=
if exist "%SCRIPT_DIR%py\python.exe" (
    set PY_BIN="%SCRIPT_DIR%py\python.exe"
) else (
    python --version >nul 2>&1
    if !ERRORLEVEL! EQU 0 set PY_BIN=python
)

:: 3. Primary Execution Path via Python API Client
if defined PY_BIN (
    if "%~1"=="" (
        !PY_BIN! "%SCRIPT_DIR%client.py" --interactive
    ) else (
        !PY_BIN! "%SCRIPT_DIR%client.py" %*
    )
    if !ERRORLEVEL! EQU 0 exit /b 0
)

:: 4. Direct Standalone C++ Binary Fallback (zero Python, zero web service required)
set MODEL=
if exist "%SCRIPT_DIR%data\core_symbols.bin" set MODEL="%SCRIPT_DIR%data\core_symbols.bin"
if not defined MODEL if exist "%SCRIPT_DIR%data\core_lite.bin" set MODEL="%SCRIPT_DIR%data\core_lite.bin"

if not exist !MODEL! (
    echo [!] Error: No model package found in "%SCRIPT_DIR%data".
    echo     Please run setup.bat to download or copy models.
    exit /b 1
)

if not exist "%SCRIPT_DIR%bin\helper.exe" (
    echo [!] Error: Native helper binary is missing from "%SCRIPT_DIR%bin".
    exit /b 1
)

echo [*] Launching direct local engine...
if "%~1"=="" (
    "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -i
) else if exist "%~1" (
    "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -f "%~1" -p "%~2"
) else (
    "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -p "%*"
)
