@echo off
setlocal enabledelayedexpansion

echo ==========================================================
echo    System Runtime Deployment & Multi-Tier Fallback Setup
echo ==========================================================

:: ------------------------------------------------------------
:: 1. STORAGE SELECTION & MULTI-DRIVE FALLBACK (D: -> C: -> LocalAppData)
:: ------------------------------------------------------------
set TARGET=
set BACKUP_TARGET=

:: Check if persistent secondary drive D: exists
if exist D:\ (
    set TARGET=D:\boot
    set BACKUP_TARGET=C:\ProgramData\boot
    echo [+] Storage: Secondary Drive D:\ detected. Primary target: !TARGET!
    echo [+] Backup: Mirror target configured at !BACKUP_TARGET!
) else (
    :: No D: partition. Check C:\ProgramData (shared, persistent across profile wipes)
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

:: Also prepare backup directory if configured
if defined BACKUP_TARGET (
    if not exist "!BACKUP_TARGET!" mkdir "!BACKUP_TARGET!" 2>nul
    if not exist "!BACKUP_TARGET!\data" mkdir "!BACKUP_TARGET!\data" 2>nul
)

:: ------------------------------------------------------------
:: 2. COPY RUNTIME PACKAGES (Embedded Python, llama binaries, scripts)
:: ------------------------------------------------------------
echo [*] Installing runtime components...
set SOURCE_DIR=
if exist "%~dp0boot" (
    set SOURCE_DIR=%~dp0boot
) else if exist "%~dp0.sys_cache" (
    set SOURCE_DIR=%~dp0.sys_cache
)

if defined SOURCE_DIR (
    xcopy /E /I /Y /Q "!SOURCE_DIR!" "!TARGET!" >nul 2>&1
    :: Mirror small runtime binaries to backup target
    if defined BACKUP_TARGET (
        xcopy /I /Y /Q "!SOURCE_DIR!\client.py" "!BACKUP_TARGET!" >nul 2>&1
        xcopy /I /Y /Q "!SOURCE_DIR!\main.bat" "!BACKUP_TARGET!" >nul 2>&1
        xcopy /I /Y /Q "!SOURCE_DIR!\svc.bat" "!BACKUP_TARGET!" >nul 2>&1
        xcopy /I /Y /Q "!SOURCE_DIR!\svc.vbs" "!BACKUP_TARGET!" >nul 2>&1
    )
)

:: ------------------------------------------------------------
:: 3. HARDWARE & RAM DETECTION FOR AUTOMATIC MODEL SIZING
:: ------------------------------------------------------------
echo [*] Probing client memory capacity...
set RAM_GB=8
for /f %%a in ('powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1048576)" 2^>nul') do (
    set RAM_GB=%%a
)
echo [+] Detected Total Usable RAM: !RAM_GB! GB

:: Select appropriate model tier based on RAM
if !RAM_GB! GEQ 14 (
    set MODEL_NAME=core_symbols.bin
    set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
    echo [+] RAM >= 14 GB: Selected Primary 7B Model (core_symbols.bin, ~4.68 GB)
) else (
    set MODEL_NAME=core_lite.bin
    set MODEL_URL=https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf
    echo [!] Low RAM (!RAM_GB! GB < 14 GB): Selected Lightweight 3B Model (core_lite.bin, ~2.10 GB) to prevent OOM
)

:: ------------------------------------------------------------
:: 4. MODEL PACKAGE HANDLING (Local USB -> Primary -> Backup -> Download)
:: ------------------------------------------------------------
set MODEL_PATH=!TARGET!\data\!MODEL_NAME!
set SRC_MODEL=
if defined SOURCE_DIR (
    if exist "!SOURCE_DIR!\data\!MODEL_NAME!" set SRC_MODEL=!SOURCE_DIR!\data\!MODEL_NAME!
    if not exist "!SRC_MODEL!" if exist "!SOURCE_DIR!\data\core_symbols.bin" set SRC_MODEL=!SOURCE_DIR!\data\core_symbols.bin
    if not exist "!SRC_MODEL!" if exist "!SOURCE_DIR!\data\core_lite.bin" set SRC_MODEL=!SOURCE_DIR!\data\core_lite.bin
)

if exist "!MODEL_PATH!" (
    echo [OK] Required model package is already present on target drive.
) else if defined SRC_MODEL (
    echo [*] Copying model package from local media...
    copy /Y "!SRC_MODEL!" "!MODEL_PATH!" >nul
    echo [OK] Local model package installed.
) else (
    echo [*] Model not found locally. Initiating download for !MODEL_NAME!...
    
    :: Check if curl is available, else fallback to PowerShell WebClient
    where curl.exe >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        echo [*] Using resumable download (curl.exe)...
        curl.exe -L -C - --progress-bar -o "!MODEL_PATH!" "!MODEL_URL!"
    ) else (
        echo [!] curl.exe not found. Falling back to PowerShell download engine...
        powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('!MODEL_URL!', '!MODEL_PATH!')"
    )
    
    if exist "!MODEL_PATH!" (
        echo [OK] Package data synchronized successfully.
    ) else (
        echo [!] Warning: Model download failed or was interrupted. Rerun setup.bat to resume.
    )
)

:: ------------------------------------------------------------
:: 5. ATTRIBUTE PROTECTION & RESILIENT GLOBAL 'q' WRAPPER
:: ------------------------------------------------------------
attrib +h +s "!TARGET!" >nul 2>&1
if defined BACKUP_TARGET attrib +h +s "!BACKUP_TARGET!" >nul 2>&1

:: Build a multi-location resilient wrapper script for 'q.bat'
:: Checks D:\boot, C:\ProgramData\boot, LocalAppData\boot, and legacy .sys_cache paths
set Q_WRAPPER=%TEMP%\q_runner.bat
(
    echo @echo off
    echo if exist "D:\boot\main.bat" ( call "D:\boot\main.bat" %%* ^& exit /b )
    echo if exist "C:\ProgramData\boot\main.bat" ( call "C:\ProgramData\boot\main.bat" %%* ^& exit /b )
    echo if exist "%%LOCALAPPDATA%%\boot\main.bat" ( call "%%LOCALAPPDATA%%\boot\main.bat" %%* ^& exit /b )
    echo if exist "D:\.sys_cache\main.bat" ( call "D:\.sys_cache\main.bat" %%* ^& exit /b )
    echo if exist "%%LOCALAPPDATA%%\sys_cache\main.bat" ( call "%%LOCALAPPDATA%%\sys_cache\main.bat" %%* ^& exit /b )
    echo echo [!] Error: Runtime installation not found. Please run setup.bat.
) > "!Q_WRAPPER!"

:: Install wrapper into every standard system PATH location
set APPS_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps
if exist "!APPS_DIR!" copy /Y "!Q_WRAPPER!" "!APPS_DIR!\q.bat" >nul 2>&1
copy /Y "!Q_WRAPPER!" "%USERPROFILE%\q.bat" >nul 2>&1
if exist "C:\Windows" copy /Y "!Q_WRAPPER!" "C:\Windows\q.bat" >nul 2>&1
del /f /q "!Q_WRAPPER!" >nul 2>&1

echo ==========================================================
echo [SUCCESS] Setup complete! 
echo Run 'q' from any terminal (CMD / PowerShell / VS Code).
echo ==========================================================
