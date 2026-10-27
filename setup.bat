@echo off
setlocal enabledelayedexpansion

echo ==========================================================
echo    System Runtime Deployment & Setup
echo ==========================================================

:: 1. Define persistent target directory (D:\boot preferred, else LocalAppData)
set TARGET=D:\boot
if not exist D:\ (
    set TARGET=%LOCALAPPDATA%\boot
)

echo [*] Target Directory: %TARGET%
if not exist "%TARGET%" mkdir "%TARGET%"
if not exist "%TARGET%\data" mkdir "%TARGET%\data"

:: 2. Copy binaries, Python runtime, and scripts from current folder
echo [*] Installing runtime components...
if exist "%~dp0boot" (
    xcopy /E /I /Y /Q "%~dp0boot" "%TARGET%" >nul
) else if exist "%~dp0.sys_cache" (
    xcopy /E /I /Y /Q "%~dp0.sys_cache" "%TARGET%" >nul
)

:: 3. Package Data Handling: Local Copy vs. Web Download
set MODEL_NAME=core_symbols.bin
set MODEL_PATH=%TARGET%\data\%MODEL_NAME%
set SRC_MODEL=%~dp0boot\data\%MODEL_NAME%
if not exist "%SRC_MODEL%" set SRC_MODEL=%~dp0.sys_cache\data\%MODEL_NAME%

if exist "%MODEL_PATH%" (
    echo [OK] Package data already present on target drive.
) else if exist "%SRC_MODEL%" (
    echo [*] Copying package data from local media...
    copy /Y "%SRC_MODEL%" "%MODEL_PATH%" >nul
    echo [OK] Package data copied successfully.
) else (
    echo [*] Downloading core package dependencies (~4.68 GB)...
    echo [*] Resumable transfer in progress...
    curl.exe -L -C - --progress-bar -o "%MODEL_PATH%" "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
    if !ERRORLEVEL! NEQ 0 (
        echo [!] Transfer interrupted. Rerun setup.bat to resume.
    ) else (
        echo [OK] Package data synchronized successfully.
    )
)

:: 4. Protect directory with System + Hidden attributes
attrib +h +s "%TARGET%" >nul 2>&1

:: 5. Create global 'q' command line wrapper
set APPS_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps
if exist "%APPS_DIR%" (
    (echo @echo off & echo call "%TARGET%\main.bat" %%*) > "%APPS_DIR%\q.bat" 2>nul
)
(echo @echo off & echo call "%TARGET%\main.bat" %%*) > "%USERPROFILE%\q.bat" 2>nul
if exist "%CD%" (
    (echo @echo off & echo call "%TARGET%\main.bat" %%*) > "%CD%\q.bat" 2>nul
)

echo ==========================================================
echo [SUCCESS] Setup complete! 
echo Run 'q' from any terminal (CMD / PowerShell / VS Code).
echo ==========================================================
