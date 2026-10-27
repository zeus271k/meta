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

if !RAM_GB! GEQ 14 (
    set MODEL_NAME=core_symbols.bin
    set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
    echo [+] RAM is !RAM_GB! GB: Selected 7B Model core_symbols.bin
) else (
    set MODEL_NAME=core_lite.bin
    set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf
    echo [!] Low RAM: !RAM_GB! GB is under 14 GB. Selected lightweight 3B Model core_lite.bin
)

:: ------------------------------------------------------------
:: 4. MODEL PACKAGE HANDLING
:: ------------------------------------------------------------
set MODEL_PATH=!TARGET!\data\!MODEL_NAME!
set SRC_MODEL=
if defined SOURCE_DIR (
    if exist "!SOURCE_DIR!\data\!MODEL_NAME!" set SRC_MODEL=!SOURCE_DIR!\data\!MODEL_NAME!
    if not defined SRC_MODEL if exist "!SOURCE_DIR!\data\core_symbols.bin" set SRC_MODEL=!SOURCE_DIR!\data\core_symbols.bin
    if not defined SRC_MODEL if exist "!SOURCE_DIR!\data\core_lite.bin" set SRC_MODEL=!SOURCE_DIR!\data\core_lite.bin
)

if exist "!MODEL_PATH!" (
    echo [OK] Package data already present on target drive.
    goto :done_model
)

if defined SRC_MODEL (
    echo [*] Copying package data from local media...
    copy /Y "!SRC_MODEL!" "!MODEL_PATH!" >nul
    echo [OK] Local package data installed.
    goto :done_model
)

echo [*] Downloading core package dependencies: !MODEL_NAME!...
curl --version >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo [*] Resumable transfer in progress...
    curl.exe -L -C - --progress-bar -o "!MODEL_PATH!" "!MODEL_URL!"
) else (
    echo [*] Transferring via PowerShell download engine...
    powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('!MODEL_URL!', '!MODEL_PATH!')"
)

if exist "!MODEL_PATH!" (
    echo [OK] Package data synchronized successfully.
) else (
    echo [!] Warning: Download interrupted. Rerun setup.bat to resume.
)

:done_model

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
