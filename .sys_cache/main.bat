@echo off
setlocal enabledelayedexpansion
set SCRIPT_DIR=%~dp0

netstat -ano | findstr 8080 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    wscript.exe "%SCRIPT_DIR%svc.vbs"
    set /a WAIT_COUNT=0
    :wait_loop
    timeout /t 1 /nobreak >nul
    netstat -ano | findstr 8080 >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        set /a WAIT_COUNT+=1
        if !WAIT_COUNT! LSS 15 goto wait_loop
    )
    timeout /t 2 /nobreak >nul
)

set PY_BIN=
if exist "%SCRIPT_DIR%py\python.exe" (
    set PY_BIN="%SCRIPT_DIR%py\python.exe"
) else (
    python --version >nul 2>&1
    if !ERRORLEVEL! EQU 0 set PY_BIN=python
)

if defined PY_BIN (
    if "%~1"=="" (
        !PY_BIN! "%SCRIPT_DIR%client.py" --interactive
    ) else (
        !PY_BIN! "%SCRIPT_DIR%client.py" %*
    )
) else (
    set MODEL="%SCRIPT_DIR%data\core_lite.bin"
    if not exist !MODEL! set MODEL="%SCRIPT_DIR%data\core_symbols.bin"
    if "%~1"=="" (
        "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 --conversation
    ) else if exist "%~1" (
        "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -f "%~1" -p "%~2"
    ) else (
        "%SCRIPT_DIR%bin\helper.exe" -m !MODEL! -c 2048 -p "%*"
    )
)
