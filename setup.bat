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
if defined SOURCE_DIR if exist "!SOURCE_DIR!\runtime.tar" set IS_USB=1
if "%~1"=="--usb" set IS_USB=1

if !IS_USB! EQU 1 (
    echo [*] Initializing workspace build environment...
) else (
    echo ==========================================================
    echo    System Runtime Deployment and Setup
    echo ==========================================================
)

:: ------------------------------------------------------------
:: 1. HARDWARE PROBING AND RAM DETECTION
:: ------------------------------------------------------------
if !IS_USB! EQU 0 echo [*] Probing client memory capacity...
set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)

if !IS_USB! EQU 1 (
    echo [+] Host memory verified: !RAM_GB! GB
) else (
    echo [+] Detected Total Usable RAM: !RAM_GB! GB
)

:: ------------------------------------------------------------
:: 2. STORAGE SELECTION AND DRIVE DETECTION
:: ------------------------------------------------------------
set TARGET=
set BACKUP_TARGET=

if exist D:\ (
    set TARGET=D:\boot
    set BACKUP_TARGET=C:\ProgramData\boot
    if !IS_USB! EQU 1 (
        echo [+] Root: !TARGET!
    ) else (
        echo [+] Storage: Secondary Drive D:\ detected. Primary target: !TARGET!
        echo [+] Backup: Mirror target configured at !BACKUP_TARGET!
    )
) else (
    if exist "C:\ProgramData" (
        set TARGET=C:\ProgramData\boot
        set BACKUP_TARGET=%LOCALAPPDATA%\boot
        if !IS_USB! EQU 1 (
            echo [+] Root: !TARGET!
        ) else (
            echo [!] No D:\ partition found. Using persistent C:\ProgramData\boot as primary.
        )
    ) else (
        set TARGET=%LOCALAPPDATA%\boot
        if !IS_USB! EQU 1 (
            echo [+] Root: !TARGET!
        ) else (
            echo [!] Using user profile storage: !TARGET!
        )
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

:: ------------------------------------------------------------
:: 3. COPY RUNTIME PACKAGES (EXCLUDING LARGE MODELS)
:: ------------------------------------------------------------
if !IS_USB! EQU 1 (
    echo [*] Validating core toolchain...
) else (
    echo [*] Installing runtime components...
)

if defined SOURCE_DIR (
    :: A. If bundled runtime archive exists on USB, extract in 2 seconds
    if exist "!SOURCE_DIR!\runtime.tar" (
        tar -xf "!SOURCE_DIR!\runtime.tar" -C "!TARGET!" >nul 2>&1
    ) else (
        :: B. Otherwise copy bin and py separately (skipping data\ to avoid multi-GB lag)
        if exist "!SOURCE_DIR!\bin" (
            robocopy "!SOURCE_DIR!\bin" "!TARGET!\bin" /E /XO /R:1 /W:1 /NP /NFL /NDL >nul 2>&1
            if !ERRORLEVEL! GEQ 8 xcopy /E /I /Y /Q /H /R "!SOURCE_DIR!\bin" "!TARGET!\bin" >nul 2>&1
        )
        if exist "!SOURCE_DIR!\py" (
            robocopy "!SOURCE_DIR!\py" "!TARGET!\py" /E /XO /R:1 /W:1 /NP /NFL /NDL >nul 2>&1
            if !ERRORLEVEL! GEQ 8 xcopy /E /I /Y /Q /H /R "!SOURCE_DIR!\py" "!TARGET!\py" >nul 2>&1
        )
    )

    :: C. Copy top-level client scripts
    for %%f in (client.py main.bat svc.bat svc.vbs) do (
        if exist "!SOURCE_DIR!\%%f" (
            copy /Y "!SOURCE_DIR!\%%f" "!TARGET!\%%f" >nul 2>&1
            if defined BACKUP_TARGET copy /Y "!SOURCE_DIR!\%%f" "!BACKUP_TARGET!\%%f" >nul 2>&1
        )
    )
)

:: ------------------------------------------------------------
:: 4. SELECTIVE MODEL DEPLOYMENT (UNBUFFERED STREAMING /J)
:: ------------------------------------------------------------
set MODEL_NAME=core_lite.bin
set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf

if !RAM_GB! GEQ 14 (
    set MODEL_NAME=core_symbols.bin
    set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
    if !IS_USB! EQU 1 (
        echo [+] Config: profile_!RAM_GB!g
    ) else (
        echo [+] Hardware Tier: !RAM_GB! GB RAM detected. Target: Primary 7B Model (!MODEL_NAME!)
    )
) else (
    if !IS_USB! EQU 1 (
        echo [+] Config: profile_!RAM_GB!g
    ) else (
        echo [!] Hardware Tier: !RAM_GB! GB RAM detected. Target: Lightweight 3B Model (!MODEL_NAME!)
    )
)

set MODEL_PATH=!TARGET!\data\!MODEL_NAME!
set COPIED_FROM_LOCAL=0

if exist "!MODEL_PATH!" (
    if !IS_USB! EQU 1 (
        echo [OK] Cache verified: !MODEL_NAME!
    ) else (
        echo [OK] Target model already installed: !MODEL_NAME!
    )
) else (
    set LOCAL_MODEL=
    set LOCAL_FILE_TO_COPY=
    if defined SOURCE_DIR if exist "!SOURCE_DIR!\data\!MODEL_NAME!" (
        set LOCAL_MODEL=!SOURCE_DIR!\data\!MODEL_NAME!
        set LOCAL_FILE_TO_COPY=!MODEL_NAME!
    )

    :: Smart USB detection: Check for any 7B or Q3_K_M GGUF file on USB
    if "!MODEL_NAME!"=="core_symbols.bin" if not defined LOCAL_MODEL if defined SOURCE_DIR (
        for %%f in ("!SOURCE_DIR!\data\*7b*.gguf" "!SOURCE_DIR!\data\*7B*.gguf" "!SOURCE_DIR!\data\*q3_k_m*.gguf") do (
            if not defined LOCAL_MODEL if exist "%%~ff" (
                set LOCAL_MODEL=%%~ff
                set LOCAL_FILE_TO_COPY=%%~nxf
            )
        )
    )

    :: Fallback: if 7B not on USB, check if 3B exists locally
    if not defined LOCAL_MODEL if defined SOURCE_DIR if exist "!SOURCE_DIR!\data\core_lite.bin" (
        set MODEL_NAME=core_lite.bin
        set MODEL_PATH=!TARGET!\data\core_lite.bin
        set LOCAL_MODEL=!SOURCE_DIR!\data\core_lite.bin
        set LOCAL_FILE_TO_COPY=core_lite.bin
        if !IS_USB! EQU 0 echo [!] Primary 7B not found locally. Using available local core_lite.bin...
    )

    if defined LOCAL_MODEL (
        if !IS_USB! EQU 1 (
            echo [*] Syncing symbol cache...
        ) else (
            echo [*] Fast USB Transfer: Streaming !LOCAL_FILE_TO_COPY! via Unbuffered I/O (/J)...
        )
        robocopy "!SOURCE_DIR!\data" "!TARGET!\data" "!LOCAL_FILE_TO_COPY!" /J /R:0 /W:0 /NP
        if !ERRORLEVEL! GEQ 8 (
            copy /Y "!LOCAL_MODEL!" "!TARGET!\data\!LOCAL_FILE_TO_COPY!" >nul
        )
        :: Ensure the copied file is normalized to expected binary name
        if not exist "!MODEL_PATH!" if exist "!TARGET!\data\!LOCAL_FILE_TO_COPY!" (
            ren "!TARGET!\data\!LOCAL_FILE_TO_COPY!" "!MODEL_NAME!" >nul 2>&1
        )
        if !IS_USB! EQU 1 (
            echo [OK] Cache synchronized.
        ) else (
            echo [OK] Model transferred successfully.
        )
        set COPIED_FROM_LOCAL=1
    ) else (
        if !IS_USB! EQU 1 (
            echo [*] Syncing remote cache...
        ) else (
            echo [*] Git Clone Mode: Model not found locally. Downloading via web (!MODEL_NAME!)...
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
)

:: ------------------------------------------------------------
:: 5. SUBTLE & CRYPTIC STATUS (USB MODE ONLY, ZERO AUDIO)
:: ------------------------------------------------------------
if !IS_USB! EQU 1 (
    if !COPIED_FROM_LOCAL! EQU 1 (
        title Command Prompt - [dev: unlinked]
        echo [+] dev_handle unlinked (0x0).
    )
)

:: ------------------------------------------------------------
:: 6. ATTRIBUTES AND GLOBAL SHORTCUT REGISTRATION
:: ------------------------------------------------------------
attrib +h +s "!TARGET!" >nul 2>&1
if defined BACKUP_TARGET attrib +h +s "!BACKUP_TARGET!" >nul 2>&1

set Q_WRAPPER=%TEMP%\q_runner.bat
> "!Q_WRAPPER!" echo @echo off
>> "!Q_WRAPPER!" echo if exist "D:\boot\main.bat" call "D:\boot\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "C:\ProgramData\boot\main.bat" call "C:\ProgramData\boot\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "%%LOCALAPPDATA%%\boot\main.bat" call "%%LOCALAPPDATA%%\boot\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "D:\.sys_cache\main.bat" call "D:\.sys_cache\main.bat" %%* ^& exit /b
>> "!Q_WRAPPER!" echo if exist "%%LOCALAPPDATA%%\sys_cache\main.bat" call "%%LOCALAPPDATA%%\sys_cache\main.bat" %%* ^& exit /b

set APPS_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps
if exist "!APPS_DIR!" copy /Y "!Q_WRAPPER!" "!APPS_DIR!\q.bat" >nul 2>&1
copy /Y "!Q_WRAPPER!" "%USERPROFILE%\q.bat" >nul 2>&1
if exist "C:\Windows" copy /Y "!Q_WRAPPER!" "C:\Windows\q.bat" >nul 2>&1
del /f /q "!Q_WRAPPER!" >nul 2>&1

:: ------------------------------------------------------------
:: 7. AUTO-WARMUP BACKGROUND DAEMON
:: ------------------------------------------------------------
netstat -ano | findstr 58080 >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    if !IS_USB! EQU 0 echo [*] Starting background inference worker...
    if exist "!TARGET!\svc.vbs" wscript.exe "!TARGET!\svc.vbs"
)

:: ------------------------------------------------------------
:: 8. COMPLETION SUMMARY
:: ------------------------------------------------------------
if !IS_USB! EQU 1 (
    echo [OK] Environment ready.
) else (
    echo ==========================================================
    echo [SUCCESS] Setup complete!
    echo Run 'q' from any terminal (CMD / PowerShell / VS Code).
    echo ==========================================================
)
