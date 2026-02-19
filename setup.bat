@echo off
echo Starting KKT environment setup...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_python.ps1"
echo.
pause
