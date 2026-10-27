@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)

if %RAM_GB% GEQ 14 (
    set MODEL_PATH=data\core_symbols.bin
) else (
    set MODEL_PATH=data\core_lite.bin
)

if not exist "!MODEL_PATH!" (
    if exist "data\core_lite.bin" set MODEL_PATH=data\core_lite.bin
    if exist "data\core_symbols.bin" set MODEL_PATH=data\core_symbols.bin
)

set SERVER_BIN=bin\worker.exe
if not exist "!SERVER_BIN!" exit /b 1

set THREADS=4
if %NUMBER_OF_PROCESSORS% GTR 6 set THREADS=6

"!SERVER_BIN!" -m "!MODEL_PATH!" --port 8080 -c 2048 -t %THREADS% >nul 2>&1
