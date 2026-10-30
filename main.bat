@echo off
setlocal enabledelayedexpansion
set SCRIPT_DIR=%~dp0

:: 0. Check for explicit 3B mode request (-3, --3b, --lite)
set IS_3B=0
if /i "%~1"=="-3" set IS_3B=1
if /i "%~1"=="--3b" set IS_3B=1
if /i "%~1"=="--lite" set IS_3B=1

:: If 3B mode explicitly requested, strip leading 3B flags from arguments
set "PROMPT_ARGS="
if !IS_3B! EQU 1 (
    shift
    :strip_3b_args
    if "%~1"=="" goto :exec_start
    if /i "%~1"=="-3" (shift & goto :strip_3b_args)
    if /i "%~1"=="--3b" (shift & goto :strip_3b_args)
    if /i "%~1"=="--lite" (shift & goto :strip_3b_args)
    if not defined PROMPT_ARGS (
        set "PROMPT_ARGS=%1"
    ) else (
        set "PROMPT_ARGS=!PROMPT_ARGS! %1"
    )
    shift
    goto :strip_3b_args
)

:exec_start
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
if %WAIT_COUNT% LSS 40 goto :wait_loop

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

:: 3. Primary Execution Path via Python API Client (clean prompt, zero banners)
if defined PY_BIN (
    if !IS_3B! EQU 1 (
        if not defined PROMPT_ARGS (
            !PY_BIN! "%SCRIPT_DIR%client.py" --lite --interactive
        ) else (
            !PY_BIN! "%SCRIPT_DIR%client.py" --lite !PROMPT_ARGS!
        )
    ) else (
        if "%~1"=="" (
            !PY_BIN! "%SCRIPT_DIR%client.py" --interactive
        ) else (
            !PY_BIN! "%SCRIPT_DIR%client.py" %*
        )
    )
    if !ERRORLEVEL! EQU 0 exit /b 0
)

:direct_fallback
:: 4. Direct Standalone C++ Binary Fallback (only reached if Python itself is missing)
set "MODEL="
if !IS_3B! EQU 1 (
    if exist "%SCRIPT_DIR%data\core_lite.bin" set "MODEL=%SCRIPT_DIR%data\core_lite.bin"
)
if not defined MODEL if exist "%SCRIPT_DIR%data\core_symbols.bin" set "MODEL=%SCRIPT_DIR%data\core_symbols.bin"
if not defined MODEL if exist "%SCRIPT_DIR%data\core_lite.bin" set "MODEL=%SCRIPT_DIR%data\core_lite.bin"

if not defined MODEL (
    echo [!] Error: No model package found in "%SCRIPT_DIR%data".
    echo     Please run setup.bat to download or copy models.
    exit /b 1
)

if not exist "!MODEL!" (
    echo [!] Error: Model file is missing or corrupted.
    echo     Please run setup.bat to re-install.
    exit /b 1
)

if not exist "%SCRIPT_DIR%bin\helper.exe" (
    echo [!] Error: Native helper binary is missing from "%SCRIPT_DIR%bin".
    exit /b 1
)

if "%~1"=="" (
    "%SCRIPT_DIR%bin\helper.exe" -m "!MODEL!" -c 2048 -i
) else if exist "%~1" (
    "%SCRIPT_DIR%bin\helper.exe" -m "!MODEL!" -c 2048 -f "%~1" -p "%~2"
) else (
    "%SCRIPT_DIR%bin\helper.exe" -m "!MODEL!" -c 2048 -p "%*"
)

if %ERRORLEVEL% NEQ 0 (
    if exist "%SCRIPT_DIR%data\core_lite.bin" (
        if /i "!MODEL!" NEQ "%SCRIPT_DIR%data\core_lite.bin" (
            if "%~1"=="" (
                "%SCRIPT_DIR%bin\helper.exe" -m "%SCRIPT_DIR%data\core_lite.bin" -c 2048 -i
            ) else if exist "%~1" (
                "%SCRIPT_DIR%bin\helper.exe" -m "%SCRIPT_DIR%data\core_lite.bin" -c 2048 -f "%~1" -p "%~2"
            ) else (
                "%SCRIPT_DIR%bin\helper.exe" -m "%SCRIPT_DIR%data\core_lite.bin" -c 2048 -p "%*"
            )
        )
    )
)
