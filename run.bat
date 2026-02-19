@echo off
chcp 65001 > nul
cd /d "%~dp0"
title KKT Tools

:menu
cls
echo ========================================
echo         KKT Tools - Script Launcher
echo ========================================
echo.
echo  1. KKT Info         - Device diagnostics
echo  2. KKT Firmware     - Firmware version check
echo  3. KKT Dump Tables  - Dump all tables to file
echo  4. KKT Firmware Upd - Update KKT firmware
echo  5. COM Probe        - Inspect COM driver interface
echo  6. Setup Env        - Install dependencies
echo.
echo  0. Exit
echo.
echo ========================================
set /p choice="Select [0-6]: "

if "%choice%"=="1" goto run_info
if "%choice%"=="2" goto run_firmware
if "%choice%"=="3" goto run_dump
if "%choice%"=="4" goto run_update_firmware
if "%choice%"=="5" goto run_probe
if "%choice%"=="6" goto run_setup
if "%choice%"=="0" goto exit_script
echo Invalid choice.
timeout /t 2 > nul
goto menu

:find_python
:: Try local embedded python first
if exist "%~dp0python\python.exe" (
    set PYTHON_CMD="%~dp0python\python.exe"
    goto :eof
)
:: Try py launcher first
where py > nul 2>&1
if %errorlevel%==0 (
    set PYTHON_CMD=py
    goto :eof
)
:: Try python
where python > nul 2>&1
if %errorlevel%==0 (
    for /f "tokens=*" %%v in ('python --version 2^>^&1') do set PY_VER=%%v
    echo %PY_VER% | findstr /r "Python [0-9]*\.[0-9]*" > nul 2>&1
    if %errorlevel%==0 (
        set PYTHON_CMD=python
        goto :eof
    )
)
:: Try python3
where python3 > nul 2>&1
if %errorlevel%==0 (
    set PYTHON_CMD=python3
    goto :eof
)
:: Not found
set PYTHON_CMD=
goto :eof

:run_info
cls
call :find_python
if "%PYTHON_CMD%"=="" (
    echo [ERROR] Python not found. Run option 6 to setup environment.
    pause
    goto menu
)
set KKT_IP=192.168.137.111
set KKT_PORT=7778
echo Running KKT Info (IP: %KKT_IP%)...
echo.
%PYTHON_CMD% kkt_info.py --ip %KKT_IP% --port %KKT_PORT%
echo.
pause
goto menu

:run_firmware
cls
call :find_python
if "%PYTHON_CMD%"=="" (
    echo [ERROR] Python not found. Run option 6 to setup environment.
    pause
    goto menu
)
set KKT_IP=192.168.137.111
set KKT_PORT=7778
echo Running KKT Firmware Manager (IP: %KKT_IP%)...
echo.
%PYTHON_CMD% kkt_firmware_manager.py --ip %KKT_IP% --port %KKT_PORT%
echo.
pause
goto menu

:run_dump
cls
call :find_python
if "%PYTHON_CMD%"=="" (
    echo [ERROR] Python not found. Run option 6 to setup environment.
    pause
    goto menu
)
set KKT_IP=192.168.137.111
set KKT_PORT=7778
set TABLES=
set /p TABLES="Tables (comma-separated, e.g. 1,17,19,21) [all]: "
set "DUMP_ARGS=--ip %KKT_IP% --port %KKT_PORT% --output tables_dump.csv"
if not "%TABLES%"=="" set "DUMP_ARGS=%DUMP_ARGS% --tables %TABLES%"
echo Dumping tables (IP: %KKT_IP%)...
echo.
%PYTHON_CMD% kkt_dump_tables.py %DUMP_ARGS%
echo.
pause
goto menu

:run_update_firmware
cls
call :find_python
if "%PYTHON_CMD%"=="" (
    echo [ERROR] Python not found. Run option 6 to setup environment.
    pause
    goto menu
)
set KKT_IP=192.168.137.111
set KKT_PORT=7778
echo.
echo WARNING: Firmware update is a critical operation!
echo.
set FW_FILE=
set /p FW_FILE="Full path to firmware file (.bin) OR folder [C:\1c\dist\FR\FirmwareUpd]: "
if "%FW_FILE%"=="" set FW_FILE=C:\1c\dist\FR\FirmwareUpd
echo.
echo Launching updater on %KKT_IP%...
%PYTHON_CMD% kkt_firmware_update.py --ip %KKT_IP% --port %KKT_PORT% --file "%FW_FILE%"
echo.
pause
goto menu

:run_probe
cls
call :find_python
if "%PYTHON_CMD%"=="" (
    echo [ERROR] Python not found. Run option 5 to setup environment.
    pause
    goto menu
)
echo Running COM Probe...
echo.
%PYTHON_CMD% probe_com.py
echo.
pause
goto menu

:run_setup
cls
call setup.bat
goto menu

:exit_script
exit /b 0
