@echo off
setlocal enabledelayedexpansion
set SCRIPT_DIR=%~dp0

:: 1. Attempt to connect to background worker on port 8080
netstat -ano | findstr 8080 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%SCRIPT_DIR%svc.vbs" (
        wscript.exe "%SCRIPT_DIR%svc.vbs"
        set /a WAIT_COUNT=0
        :wait_loop
        timeout /t 1 /nobreak >nul
        netstat -ano | findstr 8080 >nul 2>&1
        if %ERRORLEVEL% NEQ 0 (
            set /a WAIT_COUNT+=1
            if !WAIT_COUNT! LSS 10 goto wait_loop
        )
        timeout /t 1 /nobreak >nul
    )
)

:: 2. Check for Embedded Python or System Python
set PY_BIN=
if exist "%SCRIPT_DIR%py\python.exe" (
    set PY_BIN="%SCRIPT_DIR%py\python.exe"
) else (
    python --version >nul 2>&1
    if !ERRORLEVEL! EQU 0 set PY_BIN=python
)

:: 3. Primary Execution Path (Python API Client)
if defined PY_BIN (
    if "%~1"=="" (
        !PY_BIN! "%SCRIPT_DIR%client.py" --interactive
    ) else (
        !PY_BIN! "%SCRIPT_DIR%client.py" %*
    )
    if !ERRORLEVEL! EQU 0 exit /b 0
    echo [!] Python service query failed or timed out.
    echo [*] Falling back to standalone native engine (zero-dependency)...
)

:: 4. Fallback Execution Path (Native C++ helper.exe - No Python, No Web Service)
set MODEL="%SCRIPT_DIR%data\core_symbols.bin"
if not exist !MODEL! set MODEL="%SCRIPT_DIR%data\core_lite.bin"

if not exist !MODEL! (
    echo [!] Error: No model files found in "%SCRIPT_DIR%data".
    echo     Please run setup.bat to download or copy models.
    exit /b 1
)

if not exist "%SCRIPT_DIR%bin\helper.exe" (
    echo [!] Error: Native helper.exe binary missing.
    exit /b 1
)

if "%~1"=="" (
    "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 --conversation
) else if exist "%~1" (
    "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -f "%~1" -p "%~2"
) else (
    "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -p "%*"
)
