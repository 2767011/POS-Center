@echo off
cd /d "%~dp0"
chcp 65001 > nul

set PYTHON_PATH=%~dp0python\python.exe
set SCRIPT_PATH=%~dp0kkt_firmware_update.py
set FW_PATH=%~dp0firmware

:: IP адрес ККТ по умолчанию для RNDIS подключения
set KKT_IP=192.168.137.111
set KKT_PORT=7778

echo [INFO] Запуск обновления прошивки ККТ...
echo [INFO] Python: %PYTHON_PATH%
echo [INFO] Скрипт: %SCRIPT_PATH%
echo [INFO] Прошивка: %FW_PATH%
echo [INFO] ККТ: %KKT_IP%:%KKT_PORT%
echo.

"%PYTHON_PATH%" "%SCRIPT_PATH%" --ip %KKT_IP% --port %KKT_PORT% --file "%FW_PATH%" --force

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Обновление завершилось с ошибкой!
    exit /b 1
)

echo.
echo [SUCCESS] Обновление успешно завершено.
exit /b 0
