@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

:: 1. Detect RAM with 8 GB Safe Default
set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)

:: 2. Tier Selection: 7B Model for >= 14GB RAM, 3B Model for 8GB RAM
if %RAM_GB% GEQ 14 (
    set MODEL_PATH=data\core_symbols.bin
) else (
    set MODEL_PATH=data\core_lite.bin
)

:: Model Existence Fallback (if chosen tier is missing, use whatever is present)
if not exist "!MODEL_PATH!" (
    if exist "data\core_symbols.bin" set MODEL_PATH=data\core_symbols.bin
    if exist "data\core_lite.bin" set MODEL_PATH=data\core_lite.bin
)

if not exist "!MODEL_PATH!" exit /b 1

set SERVER_BIN=bin\worker.exe
if not exist "!SERVER_BIN!" exit /b 1

:: 3. Dynamic Thread Sizing for Low-End vs High-End CPUs
:: Reserve 1-2 cores for OS/IDE, bounded between 1 and 6 threads
set /a THREADS=%NUMBER_OF_PROCESSORS% - 2
if !THREADS! LSS 1 set THREADS=1
if !THREADS! GTR 6 set THREADS=6

"!SERVER_BIN!" -m "!MODEL_PATH!" --port 8080 -c 2048 -t !THREADS! >nul 2>&1
