@echo off
setlocal
:: Explicit USB mode: always force IS_USB=1 regardless of file detection
call "%~dp0setup.bat" --usb %*
