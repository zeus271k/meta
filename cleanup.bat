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

echo [OK] Cleanup and reset complete.
