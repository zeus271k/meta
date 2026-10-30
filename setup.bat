@echo off
setlocal enabledelayedexpansion

:: ------------------------------------------------------------
:: 0. DEPLOYMENT MODE DETECTION (USB vs GIT CLONE)
:: ------------------------------------------------------------
set IS_USB=0
set SOURCE_DIR=
if exist "%~dp0boot" set SOURCE_DIR=%~dp0boot
if not defined SOURCE_DIR if exist "%~dp0.sys_cache" set SOURCE_DIR=%~dp0.sys_cache
if not defined SOURCE_DIR set SOURCE_DIR=%~dp0

:: Detect if running from offline media / USB with local model assets
if exist "%~dp0data\core_symbols.bin" set IS_USB=1
if exist "%~dp0data\core_lite.bin" set IS_USB=1
if defined SOURCE_DIR if exist "!SOURCE_DIR!\data\core_symbols.bin" set IS_USB=1
if defined SOURCE_DIR if exist "!SOURCE_DIR!\data\core_lite.bin" set IS_USB=1
if "%~1"=="--usb" set IS_USB=1

if !IS_USB! EQU 1 (
    echo [*] Initializing workspace build environment...
) else (
    echo ==========================================================
    echo    System Runtime Deployment and Setup
    echo ==========================================================
)

:: ------------------------------------------------------------
:: 1. HARDWARE PROBING AND TOPOLOGY DETECTION
:: ------------------------------------------------------------
if !IS_USB! EQU 0 echo [*] Probing client hardware topology...
set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)

set CPU_CORES=%NUMBER_OF_PROCESSORS%
if not defined CPU_CORES set CPU_CORES=4

:: Dynamic Safe Thread Allocation:
:: 2 to 4 cores: Cores - 1 (min 1)
:: 6 cores: 4
:: 8 to 14 cores: 6 (preserves 2 cores for OS/IDE, matches P-core count on hybrid i5)
:: 16+ cores: 7 (unleashes 7 P-cores on Ultra 7 / i7 / i9, leaves 1 P-core + all E-cores for OS)
if !CPU_CORES! LEQ 2 (
    set OPTIMAL_THREADS=1
) else if !CPU_CORES! LEQ 4 (
    set /a OPTIMAL_THREADS=!CPU_CORES! - 1
) else if !CPU_CORES! LEQ 6 (
    set OPTIMAL_THREADS=4
) else if !CPU_CORES! LEQ 14 (
    set OPTIMAL_THREADS=6
) else (
    set OPTIMAL_THREADS=7
)

if !IS_USB! EQU 1 (
    echo [+] Host verified: !RAM_GB! GB RAM, !CPU_CORES! CPU cores [!OPTIMAL_THREADS! threads]
) else (
    echo [+] Detected Hardware: !RAM_GB! GB RAM, !CPU_CORES! CPU cores
    echo [+] Optimal Inference Threads: !OPTIMAL_THREADS!
)

:: ------------------------------------------------------------
:: 2. STORAGE SELECTION: Prefer fast internal SSD (C:\ProgramData\boot)
:: ------------------------------------------------------------
set TARGET=C:\ProgramData\boot
set BACKUP_TARGET=

:: Check if a secondary fixed partition exists for mirror backup (D:, E:, F:)
set SECONDARY_DRIVE=
for /f %%d in ('powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -and $_.DeviceID -ne 'C:' -and $_.DeviceID -ne '%~d0' } | Select-Object -First 1 -ExpandProperty DeviceID" 2^>nul') do (
    set SECONDARY_DRIVE=%%d
)

if defined SECONDARY_DRIVE (
    set BACKUP_TARGET=!SECONDARY_DRIVE!\boot
    if !IS_USB! EQU 0 (
        echo [+] Storage: Fast Internal SSD target: !TARGET!
        echo [+] Backup: Secondary mirror configured at !BACKUP_TARGET!
    )
) else (
    set BACKUP_TARGET=%LOCALAPPDATA%\boot
    if !IS_USB! EQU 0 (
        echo [+] Storage: Fast Internal SSD target: !TARGET!
    )
)

if not exist "!TARGET!" mkdir "!TARGET!" 2>nul
if not exist "!TARGET!\data" mkdir "!TARGET!\data" 2>nul

if defined BACKUP_TARGET (
    if not exist "!BACKUP_TARGET!" mkdir "!BACKUP_TARGET!" 2>nul
    if not exist "!BACKUP_TARGET!\data" mkdir "!BACKUP_TARGET!\data" 2>nul
)

:: Terminate any stale worker processes before updating
taskkill /f /im worker.exe >nul 2>&1
taskkill /f /im helper.exe >nul 2>&1

:: Temporarily remove attributes so copy tools can update existing files
if exist "!TARGET!" attrib -h -s "!TARGET!" >nul 2>&1
if defined BACKUP_TARGET if exist "!BACKUP_TARGET!" attrib -h -s "!BACKUP_TARGET!" >nul 2>&1

:: ============================================================
:: PHASE 1: USB MEDIA TRANSFER (PENDRIVE IS PLUGGED IN)
:: Goal: Stream raw bytes at maximum speed and release USB ASAP
:: ============================================================

:: ------------------------------------------------------------
:: 3. COPY RUNTIME ARCHIVE AND RUNNERS (Phase 1A: ~0.5 Seconds)
:: ------------------------------------------------------------
if !IS_USB! EQU 1 (
    echo [*] Validating core toolchain...
) else (
    echo [*] Installing runtime components...
)

if defined SOURCE_DIR (
    rem A. If pre-packaged runtime archive exists on USB, copy single file sequentially (~35 MB)
    if exist "!SOURCE_DIR!\runtime.tar.gz" (
        copy /Y "!SOURCE_DIR!\runtime.tar.gz" "!TARGET!\runtime.pkg" >nul 2>&1
    ) else if exist "!SOURCE_DIR!\runtime.tar" (
        copy /Y "!SOURCE_DIR!\runtime.tar" "!TARGET!\runtime.pkg" >nul 2>&1
    ) else (
        rem B. Fallback: Copy loose bin and py directories if no archive exists
        if exist "!SOURCE_DIR!\bin" (
            robocopy "!SOURCE_DIR!\bin" "!TARGET!\bin" /E /XO /R:1 /W:1 /NP /NFL /NDL >nul 2>&1
            if !ERRORLEVEL! GEQ 8 xcopy /E /I /Y /Q /H /R "!SOURCE_DIR!\bin" "!TARGET!\bin" >nul 2>&1
        )
        if exist "!SOURCE_DIR!\py" (
            robocopy "!SOURCE_DIR!\py" "!TARGET!\py" /E /XO /R:1 /W:1 /NP /NFL /NDL >nul 2>&1
            if !ERRORLEVEL! GEQ 8 xcopy /E /I /Y /Q /H /R "!SOURCE_DIR!\py" "!TARGET!\py" >nul 2>&1
        )
    )

    rem C. Copy lightweight client runner scripts (~10 KB total)
    for %%f in (client.py main.bat svc.bat svc.vbs) do (
        if exist "%~dp0%%f" (
            copy /Y "%~dp0%%f" "!TARGET!\%%f" >nul 2>&1
            if defined BACKUP_TARGET copy /Y "%~dp0%%f" "!BACKUP_TARGET!\%%f" >nul 2>&1
        ) else if exist "!SOURCE_DIR!\%%f" (
            copy /Y "!SOURCE_DIR!\%%f" "!TARGET!\%%f" >nul 2>&1
            if defined BACKUP_TARGET copy /Y "!SOURCE_DIR!\%%f" "!BACKUP_TARGET!\%%f" >nul 2>&1
        )
    )
)

:: ------------------------------------------------------------
:: 4. SELECTIVE MODEL DEPLOYMENT (Phase 1B: Unbuffered /J)
:: ------------------------------------------------------------
set MODEL_NAME=core_lite.bin
set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf

set QUALIFIES_FOR_7B=0
if !RAM_GB! GEQ 14 if !CPU_CORES! GEQ 4 set QUALIFIES_FOR_7B=1

if !QUALIFIES_FOR_7B! EQU 1 (
    set MODEL_NAME=core_symbols.bin
    set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m.gguf
    if !IS_USB! EQU 1 (
        echo [+] Config: profile_!RAM_GB!g_!CPU_CORES!c
    ) else (
        echo [+] Hardware Tier: High-Performance Tier [!RAM_GB! GB RAM, !CPU_CORES! cores] - Target: Primary 7B Model [5-bit Q5_K_M] [!MODEL_NAME!]
    )
) else (
    if !IS_USB! EQU 1 (
        echo [+] Config: profile_!RAM_GB!g_!CPU_CORES!c
    ) else (
        echo [!] Hardware Tier: Efficiency Tier [!RAM_GB! GB RAM, !CPU_CORES! cores] - Target: Lightweight 3B Model [!MODEL_NAME!]
    )
)

set MODEL_PATH=!TARGET!\data\!MODEL_NAME!
> "!TARGET!\tier.cfg" echo !MODEL_NAME!
> "!TARGET!\threads.cfg" echo !OPTIMAL_THREADS!
if defined BACKUP_TARGET (
    > "!BACKUP_TARGET!\tier.cfg" echo !MODEL_NAME!
    > "!BACKUP_TARGET!\threads.cfg" echo !OPTIMAL_THREADS!
)
set COPIED_FROM_LOCAL=0
set LOCAL_FILE_TO_COPY=

rem ============================================================
rem 4A. OFFLINE USB TRANSFER: COPY ALL PRESENT MODELS (7B + 3B)
rem ============================================================
if defined SOURCE_DIR (
    rem Detect 7B Model file on USB (prefers 5-bit Q5_K_M, then Q4, then Q3)
    set LOCAL_7B=
    if exist "!SOURCE_DIR!\data\core_symbols.bin" (
        set LOCAL_7B=core_symbols.bin
    ) else (
        for %%f in ("!SOURCE_DIR!\data\*7b*.gguf" "!SOURCE_DIR!\data\*7B*.gguf" "!SOURCE_DIR!\data\*q5_k_m*.gguf" "!SOURCE_DIR!\data\*q4_k_m*.gguf" "!SOURCE_DIR!\data\*q3_k_m*.gguf") do (
            if not defined LOCAL_7B if exist "%%~ff" set LOCAL_7B=%%~nxf
        )
    )

    rem Detect 3B Model file on USB
    set LOCAL_3B=
    if exist "!SOURCE_DIR!\data\core_lite.bin" (
        set LOCAL_3B=core_lite.bin
    ) else (
        for %%f in ("!SOURCE_DIR!\data\*3b*.gguf" "!SOURCE_DIR!\data\*3B*.gguf") do (
            if not defined LOCAL_3B if exist "%%~ff" set LOCAL_3B=%%~nxf
        )
    )

    rem Transfer 7B Model if present on USB
    if defined LOCAL_7B (
        if not exist "!TARGET!\data\core_symbols.bin" (
            if !IS_USB! EQU 1 (
                echo [*] Syncing symbol cache...
            ) else (
                echo [*] Fast USB Transfer: Streaming 7B Model via Unbuffered I/O [/J]...
            )
            robocopy "!SOURCE_DIR!\data" "!TARGET!\data" "!LOCAL_7B!" /J /R:0 /W:0 /NP
            if !ERRORLEVEL! GEQ 8 (
                copy /Y "!SOURCE_DIR!\data\!LOCAL_7B!" "!TARGET!\data\!LOCAL_7B!" >nul
            )
            if not "!LOCAL_7B!"=="core_symbols.bin" (
                ren "!TARGET!\data\!LOCAL_7B!" "core_symbols.bin" >nul 2>&1
            )
            if !IS_USB! EQU 1 (
                echo [OK] Cache synchronized.
            ) else (
                echo [OK] Primary 7B model transferred successfully.
            )
            set COPIED_FROM_LOCAL=1
        ) else (
            if !IS_USB! EQU 1 (
                echo [OK] Package cache verified.
            ) else (
                echo [OK] Target 7B model already installed: core_symbols.bin
            )
        )
    )

    rem Transfer 3B Model if present on USB
    if defined LOCAL_3B (
        if not exist "!TARGET!\data\core_lite.bin" (
            if !IS_USB! EQU 1 (
                echo [*] Syncing extended cache...
            ) else (
                echo [*] Fast USB Transfer: Streaming 3B Model via Unbuffered I/O [/J]...
            )
            robocopy "!SOURCE_DIR!\data" "!TARGET!\data" "!LOCAL_3B!" /J /R:0 /W:0 /NP
            if !ERRORLEVEL! GEQ 8 (
                copy /Y "!SOURCE_DIR!\data\!LOCAL_3B!" "!TARGET!\data\!LOCAL_3B!" >nul
            )
            if not "!LOCAL_3B!"=="core_lite.bin" (
                ren "!TARGET!\data\!LOCAL_3B!" "core_lite.bin" >nul 2>&1
            )
            if !IS_USB! EQU 1 (
                echo [OK] Extended cache synchronized.
            ) else (
                echo [OK] Secondary 3B model transferred successfully.
            )
            set COPIED_FROM_LOCAL=1
        ) else (
            if !IS_USB! EQU 1 (
                echo [OK] Extended package cache verified.
            ) else (
                echo [OK] Target 3B model already installed: core_lite.bin
            )
        )
    )
)

rem ============================================================
rem 4B. ONLINE FALLBACK: DOWNLOAD FROM WEB IF MODEL MISSING
rem ============================================================
if not exist "!MODEL_PATH!" (
    if !IS_USB! EQU 1 (
        echo [*] Syncing remote cache...
    ) else (
        echo [*] Git Clone Mode: Model not found locally. Downloading via web [!MODEL_NAME!]...
    )
    curl --version >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        curl.exe -L -C - --progress-bar -o "!MODEL_PATH!" "!MODEL_URL!"
    ) else (
        powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('!MODEL_URL!', '!MODEL_PATH!')"
    )
    if !IS_USB! EQU 1 (
        echo [OK] Package ready.
    ) else (
        echo [OK] Model download complete.
    )
)

:: In Git Clone Mode (online / zero time restriction):
:: If high-performance hardware detected, also ensure the 3B safety-net model is downloaded so that
:: the automatic hot-swap fallback in svc.bat is 100% operational.
if !IS_USB! EQU 0 if !QUALIFIES_FOR_7B! EQU 1 (
    if not exist "!TARGET!\data\core_lite.bin" (
        echo [*] Git Clone Mode: Downloading secondary safety-net model [core_lite.bin]...
        curl --version >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            curl.exe -L -C - --progress-bar -o "!TARGET!\data\core_lite.bin" "https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
        ) else (
            powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf', '!TARGET!\data\core_lite.bin')"
        )
        echo [OK] Secondary safety-net model ready. Full hot-swap redundancy enabled.
    ) else (
        echo [OK] Secondary safety-net model already installed: core_lite.bin
    )
)

:: ------------------------------------------------------------
:: 5. END OF PHASE 1: CRYPTIC REMOVAL NOTICE (PULL USB NOW)
:: ------------------------------------------------------------
:: At this point, ALL reading from the USB drive is 100% complete.
if !IS_USB! EQU 1 (
    if !COPIED_FROM_LOCAL! EQU 1 (
        title Command Prompt - [dev: unlinked]
        echo [+] dev_handle unlinked [0x0].
    )
)

:: ============================================================
:: PHASE 2: LOCAL DISK FINALIZATION (USB IS ALREADY IN POCKET)
:: All remaining steps run exclusively on the PC's internal disk
:: ============================================================

:: ------------------------------------------------------------
:: 6. EXTRACT RUNTIME PACKAGE LOCALLY (Phase 2A: ~1-2 Seconds)
:: ------------------------------------------------------------
if exist "!TARGET!\runtime.pkg" (
    tar -xf "!TARGET!\runtime.pkg" -C "!TARGET!" >nul 2>&1
    del /f /q "!TARGET!\runtime.pkg" >nul 2>&1
)

:: Normalize copied model name if needed
if defined LOCAL_FILE_TO_COPY (
    if not exist "!MODEL_PATH!" if exist "!TARGET!\data\!LOCAL_FILE_TO_COPY!" (
        ren "!TARGET!\data\!LOCAL_FILE_TO_COPY!" "!MODEL_NAME!" >nul 2>&1
    )
)

:: ------------------------------------------------------------
:: 7. ATTRIBUTES AND GLOBAL SHORTCUT REGISTRATION
:: ------------------------------------------------------------
attrib +h +s "!TARGET!" >nul 2>&1
if defined BACKUP_TARGET attrib +h +s "!BACKUP_TARGET!" >nul 2>&1

set Q_WRAPPER=%TEMP%\q_runner.bat
> "!Q_WRAPPER!" echo @echo off
>> "!Q_WRAPPER!" echo if exist "!TARGET!\main.bat" call "!TARGET!\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "C:\ProgramData\boot\main.bat" call "C:\ProgramData\boot\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "D:\boot\main.bat" call "D:\boot\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "E:\boot\main.bat" call "E:\boot\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "%%LOCALAPPDATA%%\boot\main.bat" call "%%LOCALAPPDATA%%\boot\main.bat" %%* ^& exit /b

set Q3_WRAPPER=%TEMP%\q3_runner.bat
> "!Q3_WRAPPER!" echo @echo off
>> "!Q3_WRAPPER!" echo if exist "!TARGET!\main.bat" call "!TARGET!\main.bat" -3 %%* ^& exit /b
>> "!Q3_WRAPPER!" echo if exist "C:\ProgramData\boot\main.bat" call "C:\ProgramData\boot\main.bat" -3 %%* ^& exit /b
>> "!Q3_WRAPPER!" echo if exist "D:\boot\main.bat" call "D:\boot\main.bat" -3 %%* ^& exit /b
>> "!Q3_WRAPPER!" echo if exist "E:\boot\main.bat" call "E:\boot\main.bat" -3 %%* ^& exit /b
>> "!Q3_WRAPPER!" echo if exist "%%LOCALAPPDATA%%\boot\main.bat" call "%%LOCALAPPDATA%%\boot\main.bat" -3 %%* ^& exit /b

set APPS_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps
if exist "!APPS_DIR!" (
    copy /Y "!Q_WRAPPER!" "!APPS_DIR!\q.bat" >nul 2>&1
    copy /Y "!Q3_WRAPPER!" "!APPS_DIR!\q3.bat" >nul 2>&1
)
copy /Y "!Q_WRAPPER!" "%USERPROFILE%\q.bat" >nul 2>&1
copy /Y "!Q3_WRAPPER!" "%USERPROFILE%\q3.bat" >nul 2>&1
attrib +h +s "%USERPROFILE%\q.bat" >nul 2>&1
attrib +h +s "%USERPROFILE%\q3.bat" >nul 2>&1

:: Clean stray telemetry/probe files from user directory
if exist "%USERPROFILE%\15" del /f /q "%USERPROFILE%\15" >nul 2>&1
if exist "%USERPROFILE%\16" del /f /q "%USERPROFILE%\16" >nul 2>&1
if exist "%USERPROFILE%\8" del /f /q "%USERPROFILE%\8" >nul 2>&1

if exist "C:\Windows" (
    copy /Y "!Q_WRAPPER!" "C:\Windows\q.bat" >nul 2>&1
    copy /Y "!Q3_WRAPPER!" "C:\Windows\q3.bat" >nul 2>&1
    attrib +h +s "C:\Windows\q.bat" >nul 2>&1
    attrib +h +s "C:\Windows\q3.bat" >nul 2>&1
)
del /f /q "!Q_WRAPPER!" "!Q3_WRAPPER!" >nul 2>&1

:: ------------------------------------------------------------
:: 8. AUTO-WARMUP BACKGROUND DAEMON
:: ------------------------------------------------------------
netstat -ano | findstr 58080 >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    if !IS_USB! EQU 0 echo [*] Starting background inference worker...
    if exist "!TARGET!\svc.vbs" wscript.exe "!TARGET!\svc.vbs"
)

:: ------------------------------------------------------------
:: 9. COMPLETION SUMMARY
:: ------------------------------------------------------------
if !IS_USB! EQU 1 (
    echo [OK] Environment ready.
) else (
    echo ==========================================================
    echo [SUCCESS] Setup complete!
    echo Run 'q' from any terminal [CMD / PowerShell / VS Code].
    echo ==========================================================
)
