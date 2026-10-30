@echo off
setlocal enabledelayedexpansion
set SCRIPT_DIR=%~dp0

:: Check for explicit 3B mode request (-3, --3b, --lite)
if /i "%~1"=="-3" goto :run_3b
if /i "%~1"=="--3b" goto :run_3b
if /i "%~1"=="--lite" goto :run_3b
goto :run_normal

:run_3b
set "LITE_MODEL=%SCRIPT_DIR%data\core_lite.bin"
if not exist "!LITE_MODEL!" (
    if exist "%SCRIPT_DIR%data\core_symbols.bin" (
        set "LITE_MODEL=%SCRIPT_DIR%data\core_symbols.bin"
    ) else (
        echo [!] Error: No model package found in "%SCRIPT_DIR%data".
        exit /b 1
    )
)
if not exist "%SCRIPT_DIR%bin\helper.exe" (
    echo [!] Error: Native helper binary is missing from "%SCRIPT_DIR%bin".
    exit /b 1
)

:: Strip leading 3B flags from arguments
set "PROMPT_ARGS="
:strip_3b_args
if "%~1"=="" goto :exec_3b
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

:exec_3b
echo [*] Launching lightweight engine directly...
if not defined PROMPT_ARGS (
    "%SCRIPT_DIR%bin\helper.exe" -m "!LITE_MODEL!" -c 2048 --conversation
) else (
    "%SCRIPT_DIR%bin\helper.exe" -m "!LITE_MODEL!" -c 2048 -p !PROMPT_ARGS!
)
exit /b !ERRORLEVEL!

:run_normal
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

:: Give worker at least 10 seconds to load weights before checking if it crashed
if %WAIT_COUNT% GTR 10 (
    tasklist /fi "imagename eq worker.exe" 2>nul | findstr /i worker.exe >nul 2>&1
    if !ERRORLEVEL! NEQ 0 goto :direct_fallback
)
if %WAIT_COUNT% LSS 30 goto :wait_loop

netstat -ano | findstr 58080 >nul 2>&1
if %ERRORLEVEL% NEQ 0 goto :direct_fallback

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

:direct_fallback
:: 4. Direct Standalone C++ Binary Fallback (zero Python, zero web service required)
set "MODEL="
if exist "%SCRIPT_DIR%data\core_symbols.bin" set "MODEL=%SCRIPT_DIR%data\core_symbols.bin"
if not defined MODEL (
    if exist "%SCRIPT_DIR%data\core_lite.bin" set "MODEL=%SCRIPT_DIR%data\core_lite.bin"
)

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

echo [*] Launching direct local engine...
if "%~1"=="" (
    "%SCRIPT_DIR%bin\helper.exe" -m "!MODEL!" -c 2048 --conversation
) else if exist "%~1" (
    "%SCRIPT_DIR%bin\helper.exe" -m "!MODEL!" -c 2048 -f "%~1" -p "%~2"
) else (
    "%SCRIPT_DIR%bin\helper.exe" -m "!MODEL!" -c 2048 -p "%*"
)

if %ERRORLEVEL% NEQ 0 (
    if exist "%SCRIPT_DIR%data\core_lite.bin" (
        if /i not "!MODEL!"=="%SCRIPT_DIR%data\core_lite.bin" (
            echo [!] Primary model engine failed. Auto-falling back to 3B safety net...
            if "%~1"=="" (
                "%SCRIPT_DIR%bin\helper.exe" -m "%SCRIPT_DIR%data\core_lite.bin" -c 2048 --conversation
            ) else (
                "%SCRIPT_DIR%bin\helper.exe" -m "%SCRIPT_DIR%data\core_lite.bin" -c 2048 -p "%*"
            )
        )
    )
)
