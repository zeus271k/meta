@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

:: 1. Instant Tier Selection: Read pre-configured tier if available (0.001s, no slow powershell)
set MODEL_NAME=
if exist "%~dp0tier.cfg" (
    set /p MODEL_NAME=<"%~dp0tier.cfg"
    set MODEL_NAME=!MODEL_NAME: =!
)
if defined MODEL_NAME (
    if exist "data\!MODEL_NAME!" set "MODEL_PATH=data\!MODEL_NAME!"
)

:: Fallback if tier.cfg is missing: Probe RAM to choose safely
if not defined MODEL_PATH (
    set RAM_GB=8
    for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
        set RAM_GB=%%a
    )
    if !RAM_GB! GEQ 14 (
        if exist "data\core_symbols.bin" set MODEL_PATH=data\core_symbols.bin
    )
    if not defined MODEL_PATH (
        if exist "data\core_lite.bin" (
            set MODEL_PATH=data\core_lite.bin
        ) else if exist "data\core_symbols.bin" (
            set MODEL_PATH=data\core_symbols.bin
        )
    )
)

if not defined MODEL_PATH exit /b 1
if not exist "!MODEL_PATH!" exit /b 1

set SERVER_BIN=bin\worker.exe
if not exist "!SERVER_BIN!" exit /b 1

:: 2. Dynamic Thread Sizing for Low-End vs High-End CPUs
set /a THREADS=%NUMBER_OF_PROCESSORS% - 2
if !THREADS! LSS 1 set THREADS=1
if !THREADS! GTR 6 set THREADS=6

:: 3. Launch server bound exclusively to localhost on dedicated port 58080
"!SERVER_BIN!" -m "!MODEL_PATH!" --host 127.0.0.1 --port 58080 -c 4096 -t !THREADS! > "%~dp0worker.log" 2>&1

:: 4. Automatic Hot-Swap Fallback (Safety Net)
:: If 7B engine fails, crashes, or runs out of RAM, immediately fallback to 3B core_lite.bin
if "!MODEL_PATH!"=="data\core_symbols.bin" (
    if exist "data\core_lite.bin" (
        echo [!] Primary 7B engine terminated. Initiating hot-swap fallback to 3B safety-net... >> "%~dp0worker.log"
        "!SERVER_BIN!" -m "data\core_lite.bin" --host 127.0.0.1 --port 58080 -c 4096 -t !THREADS! >> "%~dp0worker.log" 2>&1
    )
)
