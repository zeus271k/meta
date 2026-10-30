@echo off
setlocal

echo [*] Stopping background inference workers...
taskkill /f /im worker.exe >nul 2>&1
taskkill /f /im helper.exe >nul 2>&1

echo [*] Removing system runtime directories...
if exist "D:\boot" (
    attrib -h -s "D:\boot" >nul 2>&1
    rmdir /s /q "D:\boot" >nul 2>&1
)
if exist "%LOCALAPPDATA%\boot" (
    attrib -h -s "%LOCALAPPDATA%\boot" >nul 2>&1
    rmdir /s /q "%LOCALAPPDATA%\boot" >nul 2>&1
)
if exist "C:\ProgramData\boot" (
    attrib -h -s "C:\ProgramData\boot" >nul 2>&1
    rmdir /s /q "C:\ProgramData\boot" >nul 2>&1
)

:: Also clean legacy .sys_cache paths if present
if exist "D:\.sys_cache" (
    attrib -h -s "D:\.sys_cache" >nul 2>&1
    rmdir /s /q "D:\.sys_cache" >nul 2>&1
)
if exist "%LOCALAPPDATA%\sys_cache" (
    attrib -h -s "%LOCALAPPDATA%\sys_cache" >nul 2>&1
    rmdir /s /q "%LOCALAPPDATA%\sys_cache" >nul 2>&1
)

echo [*] Removing command shortcuts...
set APPS_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps
if exist "%APPS_DIR%\q.bat" del /f /q "%APPS_DIR%\q.bat" >nul 2>&1
if exist "%APPS_DIR%\q3.bat" del /f /q "%APPS_DIR%\q3.bat" >nul 2>&1
if exist "%USERPROFILE%\q.bat" (
    attrib -h -s "%USERPROFILE%\q.bat" >nul 2>&1
    del /f /q "%USERPROFILE%\q.bat" >nul 2>&1
)
if exist "%USERPROFILE%\q3.bat" (
    attrib -h -s "%USERPROFILE%\q3.bat" >nul 2>&1
    del /f /q "%USERPROFILE%\q3.bat" >nul 2>&1
)
if exist "C:\Windows\q.bat" (
    attrib -h -s "C:\Windows\q.bat" >nul 2>&1
    del /f /q "C:\Windows\q.bat" >nul 2>&1
)
if exist "C:\Windows\q3.bat" (
    attrib -h -s "C:\Windows\q3.bat" >nul 2>&1
    del /f /q "C:\Windows\q3.bat" >nul 2>&1
)
if exist "%USERPROFILE%\15" del /f /q "%USERPROFILE%\15" >nul 2>&1
if exist "%USERPROFILE%\16" del /f /q "%USERPROFILE%\16" >nul 2>&1
if exist "%USERPROFILE%\8" del /f /q "%USERPROFILE%\8" >nul 2>&1
if exist "q.bat" del /f /q "q.bat" >nul 2>&1
if exist "q3.bat" del /f /q "q3.bat" >nul 2>&1

:: Clean up global cleanup & reset wrappers
if exist "%USERPROFILE%\cleanup.bat" (
    attrib -h -s "%USERPROFILE%\cleanup.bat" >nul 2>&1
    if /i "%~f0" NEQ "%USERPROFILE%\cleanup.bat" del /f /q "%USERPROFILE%\cleanup.bat" >nul 2>&1
)
if exist "%USERPROFILE%\reset.bat" (
    attrib -h -s "%USERPROFILE%\reset.bat" >nul 2>&1
    if /i "%~f0" NEQ "%USERPROFILE%\reset.bat" del /f /q "%USERPROFILE%\reset.bat" >nul 2>&1
)
if exist "%APPS_DIR%\reset.bat" if /i "%~f0" NEQ "%APPS_DIR%\reset.bat" del /f /q "%APPS_DIR%\reset.bat" >nul 2>&1
if exist "%APPS_DIR%\cleanup.bat" if /i "%~f0" NEQ "%APPS_DIR%\cleanup.bat" del /f /q "%APPS_DIR%\cleanup.bat" >nul 2>&1

echo [OK] Cleanup and reset complete.

:: If executing from WindowsApps or UserProfile, self-delete on exit
if /i "%~f0"=="%APPS_DIR%\cleanup.bat" (goto) 2>nul & del "%~f0"
if /i "%~f0"=="%USERPROFILE%\cleanup.bat" (goto) 2>nul & del "%~f0"
if /i "%~f0"=="%APPS_DIR%\reset.bat" (goto) 2>nul & del "%~f0"
if /i "%~f0"=="%USERPROFILE%\reset.bat" (goto) 2>nul & del "%~f0"
