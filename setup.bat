@echo off
setlocal enabledelayedexpansion

echo ==========================================================
echo    System Runtime Deployment and Setup
echo ==========================================================

:: ------------------------------------------------------------
:: 1. STORAGE SELECTION AND DRIVE DETECTION
:: ------------------------------------------------------------
set TARGET=
set BACKUP_TARGET=

if exist D:\ (
    set TARGET=D:\boot
    set BACKUP_TARGET=C:\ProgramData\boot
    echo [+] Storage: Secondary Drive D:\ detected. Primary target: !TARGET!
    echo [+] Backup: Mirror target configured at !BACKUP_TARGET!
) else (
    if exist "C:\ProgramData" (
        set TARGET=C:\ProgramData\boot
        set BACKUP_TARGET=%LOCALAPPDATA%\boot
        echo [!] No D:\ partition found. Using persistent C:\ProgramData\boot as primary.
    ) else (
        set TARGET=%LOCALAPPDATA%\boot
        echo [!] Using user profile storage: !TARGET!
    )
)

if not exist "!TARGET!" mkdir "!TARGET!" 2>nul
if not exist "!TARGET!\data" mkdir "!TARGET!\data" 2>nul

if defined BACKUP_TARGET (
    if not exist "!BACKUP_TARGET!" mkdir "!BACKUP_TARGET!" 2>nul
    if not exist "!BACKUP_TARGET!\data" mkdir "!BACKUP_TARGET!\data" 2>nul
)

:: ------------------------------------------------------------
:: 2. COPY RUNTIME PACKAGES
:: ------------------------------------------------------------
echo [*] Installing runtime components...
set SOURCE_DIR=
if exist "%~dp0boot" set SOURCE_DIR=%~dp0boot
if not defined SOURCE_DIR if exist "%~dp0.sys_cache" set SOURCE_DIR=%~dp0.sys_cache

:: Terminate any stale worker processes before updating
taskkill /f /im worker.exe >nul 2>&1

:: Temporarily remove attributes so xcopy can update existing files
if exist "!TARGET!" attrib -h -s "!TARGET!" >nul 2>&1

if defined SOURCE_DIR (
    xcopy /E /I /Y /Q /H /R "!SOURCE_DIR!" "!TARGET!" >nul 2>&1
    if defined BACKUP_TARGET (
        xcopy /I /Y /Q /H /R "!SOURCE_DIR!\client.py" "!BACKUP_TARGET!" >nul 2>&1
        xcopy /I /Y /Q /H /R "!SOURCE_DIR!\main.bat" "!BACKUP_TARGET!" >nul 2>&1
        xcopy /I /Y /Q /H /R "!SOURCE_DIR!\svc.bat" "!BACKUP_TARGET!" >nul 2>&1
        xcopy /I /Y /Q /H /R "!SOURCE_DIR!\svc.vbs" "!BACKUP_TARGET!" >nul 2>&1
    )
)

:: ------------------------------------------------------------
:: 3. HARDWARE AND RAM DETECTION
:: ------------------------------------------------------------
echo [*] Probing client memory capacity...
set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)
echo [+] Detected Total Usable RAM: !RAM_GB! GB

:: ------------------------------------------------------------
:: 4. MODEL PACKAGE HANDLING (DUAL SAFETY-NET ON 16GB)
:: ------------------------------------------------------------

:: 4A. Always Ensure Base 3B Model is Present (core_lite.bin ~2.10 GB)
set M3B_NAME=core_lite.bin
set M3B_PATH=!TARGET!\data\!M3B_NAME!
set M3B_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf

if exist "!M3B_PATH!" (
    echo [OK] 3B Safety-Net Model already present: !M3B_NAME!
) else (
    set LOCAL_3B=
    if defined SOURCE_DIR if exist "!SOURCE_DIR!\data\!M3B_NAME!" set LOCAL_3B=!SOURCE_DIR!\data\!M3B_NAME!
    if defined LOCAL_3B (
        echo [*] Copying 3B model from local media...
        copy /Y "!LOCAL_3B!" "!M3B_PATH!" >nul
        echo [OK] Local 3B model installed.
    ) else (
        echo [*] Downloading 3B Model (!M3B_NAME!, ~2.10 GB)...
        curl --version >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            curl.exe -L -C - --progress-bar -o "!M3B_PATH!" "!M3B_URL!"
        ) else (
            powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('!M3B_URL!', '!M3B_PATH!')"
        )
    )
)

:: 4B. On 16 GB PCs (RAM >= 14 GB), Also Download Primary 7B Model (core_symbols.bin ~4.68 GB)
if !RAM_GB! GEQ 14 (
    set M7B_NAME=core_symbols.bin
    set M7B_PATH=!TARGET!\data\!M7B_NAME!
    set M7B_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf

    if exist "!M7B_PATH!" (
        echo [OK] Primary 7B Model already present: !M7B_NAME!
    ) else (
        set LOCAL_7B=
        if defined SOURCE_DIR if exist "!SOURCE_DIR!\data\!M7B_NAME!" set LOCAL_7B=!SOURCE_DIR!\data\!M7B_NAME!
        if defined LOCAL_7B (
            echo [*] Copying 7B model from local media...
            copy /Y "!LOCAL_7B!" "!M7B_PATH!" >nul
            echo [OK] Local 7B model installed.
        ) else (
            echo [*] RAM is !RAM_GB! GB: Downloading Primary 7B Model (!M7B_NAME!, ~4.68 GB)...
            curl --version >nul 2>&1
            if !ERRORLEVEL! EQU 0 (
                curl.exe -L -C - --progress-bar -o "!M7B_PATH!" "!M7B_URL!"
            ) else (
                powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('!M7B_URL!', '!M7B_PATH!')"
            )
        )
    )
) else (
    echo [!] Low RAM (!RAM_GB! GB): Skipped 7B model to conserve memory. Running on 3B core_lite.bin.
)

:: ------------------------------------------------------------
:: 5. ATTRIBUTES AND GLOBAL SHORTCUT
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
>> "!Q_WRAPPER!" echo echo [!] Error: Runtime installation not found. Please run setup.bat.

set APPS_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps
if exist "!APPS_DIR!" copy /Y "!Q_WRAPPER!" "!APPS_DIR!\q.bat" >nul 2>&1
copy /Y "!Q_WRAPPER!" "%USERPROFILE%\q.bat" >nul 2>&1
if exist "C:\Windows" copy /Y "!Q_WRAPPER!" "C:\Windows\q.bat" >nul 2>&1
del /f /q "!Q_WRAPPER!" >nul 2>&1

echo ==========================================================
echo [SUCCESS] Setup complete!
echo Run 'q' from any terminal (CMD / PowerShell / VS Code).
echo ==========================================================
