@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul

set "START_DIR=%~dp0"

:: Optional source selector:
::   auto_update.bat --source http://host/KKT
::   auto_update.bat --source C:\Offline\KKT
::   auto_update.bat --source \\server\share\KKT
:: Environment alternative: set KKT_SOURCE=...
:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="--source" (
    if "%~2"=="" (
        echo [ERROR] Missing value after --source.
        exit /b 1
    )
    set "KKT_SOURCE=%~2"
    shift
    shift
    goto :parse_args
)
set "ARG=%~1"
if /I "!ARG:~0,9!"=="--source=" (
    set "KKT_SOURCE=!ARG:~9!"
    shift
    goto :parse_args
)
echo [WARN] Unknown argument ignored: %~1
shift
goto :parse_args

:args_done
if not defined KKT_SOURCE if defined BASE_URL set "KKT_SOURCE=%BASE_URL%"
if not defined KKT_SOURCE set "KKT_SOURCE=%START_DIR%"

:: Проверка прав администратора (нужны для regsvr32)
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Administrator privileges required.
    echo         Re-run this script as Administrator.
    goto :fail
)

:: Working directory
set "SCRIPT_DIR=C:\KKT"
if defined TEMP set "SCRIPT_DIR=%TEMP%\KKT"
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%"
cd /d "%SCRIPT_DIR%"
echo       Working dir: %SCRIPT_DIR%
echo       Source: %KKT_SOURCE%

set "FLAG_FILE=%SCRIPT_DIR%\update_success.flag"
set "PYTHON_DIR=%SCRIPT_DIR%\python"
set "PYTHON_EXE=%PYTHON_DIR%\python.exe"
set "FW_DIR=%SCRIPT_DIR%\firmware"
set "VCOM_DFU_DIR=%SCRIPT_DIR%\VCOM+DFU"
set "DFU_DRIVER_LOG=%SCRIPT_DIR%\dfu_driver_install.log"
set "DFU_DRIVER_WARN=0"
set "PREPARE_SCRIPT=%SCRIPT_DIR%\prepare_update.ps1"

echo ========================================
echo  KKT Auto Update
echo ========================================
echo:

:: ========================================
:: 0. Prepare all files from selected source
:: ========================================
echo [0/5] Preparing files...

if exist "%START_DIR%prepare_update.ps1" (
    copy /Y "%START_DIR%prepare_update.ps1" "%PREPARE_SCRIPT%" >nul
)

if not exist "%PREPARE_SCRIPT%" if exist "%START_DIR%Updater\prepare_update.ps1" (
    copy /Y "%START_DIR%Updater\prepare_update.ps1" "%PREPARE_SCRIPT%" >nul
)

if not exist "%PREPARE_SCRIPT%" if exist "%KKT_SOURCE%\prepare_update.ps1" (
    copy /Y "%KKT_SOURCE%\prepare_update.ps1" "%PREPARE_SCRIPT%" >nul
)

if not exist "%PREPARE_SCRIPT%" if exist "%KKT_SOURCE%\Updater\prepare_update.ps1" (
    copy /Y "%KKT_SOURCE%\Updater\prepare_update.ps1" "%PREPARE_SCRIPT%" >nul
)

if not exist "%PREPARE_SCRIPT%" (
    echo %KKT_SOURCE% | findstr /I /R "^http:// ^https://" >nul
    if !ERRORLEVEL! EQU 0 (
        echo       Fetching prepare_update.ps1 from HTTP source...
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$src='%KKT_SOURCE%'.TrimEnd('/'); $dest='%PREPARE_SCRIPT%'; $urls=@($src + '/prepare_update.ps1', $src + '/Updater/prepare_update.ps1'); $wc=New-Object System.Net.WebClient; try { foreach ($u in $urls) { try { $wc.DownloadFile($u, $dest); if (Test-Path $dest) { exit 0 } } catch {} }; exit 1 } finally { $wc.Dispose() }"
    )
)

if not exist "%PREPARE_SCRIPT%" (
    echo [ERROR] prepare_update.ps1 not found.
    echo         Provide --source pointing to HTTP root, Updater folder, SMB path, or offline package.
    goto :fail
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PREPARE_SCRIPT%" -Source "%KKT_SOURCE%" -BaseUrl "%BASE_URL%" -FwUrl "%FW_URL%" -Dir "%SCRIPT_DIR%" -FwDir "%FW_DIR%" -DfuDir "%VCOM_DFU_DIR%"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] File preparation failed.
    goto :fail
)

:: Критические файлы должны существовать после подготовки
set "REQ_MISSING=0"
for %%f in (prepare_update.ps1 kkt_firmware_update.py kkt_driver.py kkt_dump_tables.py config.bat install_python.ps1 install_dfu_driver.bat) do (
    if not exist "%SCRIPT_DIR%\%%f" (
        echo [ERROR] Missing required file: %%f
        set "REQ_MISSING=1"
    )
)
if not exist "%VCOM_DFU_DIR%\Windows\INF\dfu\lpc-composite89-dfu.inf" (
    echo [ERROR] Missing required DFU driver INF.
    set "REQ_MISSING=1"
)
if not exist "%VCOM_DFU_DIR%\Windows\INF\vcom\lpc-ucom-vcom.inf" (
    echo [ERROR] Missing required VCOM driver INF.
    set "REQ_MISSING=1"
)
if "!REQ_MISSING!"=="1" (
    echo [ERROR] Required files are missing after preparation. Aborting.
    goto :fail
)

echo       Preparation complete.
echo:

:: Load config (prepared by prepare_update.ps1)
if exist "%SCRIPT_DIR%\config.bat" (
    call "%SCRIPT_DIR%\config.bat"
) else (
    set "KKT_IP=192.168.137.111"
    set "KKT_PORT=7778"
)

:: ========================================
:: 1. Python
:: ========================================
echo [1/5] Python...
if not exist "%SCRIPT_DIR%\install_python.ps1" (
    echo [ERROR] install_python.ps1 not found!
    goto :fail
)
echo       Checking/installing portable Python...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\install_python.ps1" -PackageSource "%SCRIPT_DIR%"
if not exist "%PYTHON_EXE%" (
    echo [ERROR] Python install failed!
    goto :fail
)
echo       Installed.

:python_ok
echo       OK: %PYTHON_EXE%
echo:

:: ========================================
:: 2. pywin32
:: ========================================
echo [2/5] pywin32...
"%PYTHON_EXE%" -c "import win32com.client" 2>nul
if %ERRORLEVEL% EQU 0 goto :pywin32_ok

echo       Not found. Installing...
set "PYWIN32_PACKAGE=pywin32"
"%PYTHON_EXE%" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 8) else 1)" >nul 2>nul
if %ERRORLEVEL% EQU 0 set "PYWIN32_PACKAGE=pywin32==306"
"%PYTHON_EXE%" -m pip install %PYWIN32_PACKAGE% --no-warn-script-location 2>&1
"%PYTHON_EXE%" -c "import win32com.client" 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] pywin32 install failed!
    goto :fail
)
echo       Installed.

:pywin32_ok
echo       OK
echo:

:: ========================================
:: 3. COM driver (AddIn.DrvFR)
:: ========================================
echo [3/5] COM driver AddIn.DrvFR...

"%PYTHON_EXE%" -c "import sys,win32com.client;win32com.client.Dispatch('AddIn.DrvFR');sys.exit(0)" 2>nul
set COM_RESULT=%ERRORLEVEL%

if %COM_RESULT% EQU 0 goto :com_ok

echo       Not registered. Trying to register...

set "DRV_DLL="
if exist "C:\Program Files\Poscenter\DrvKKT\Bin\DrvFR.dll" set "DRV_DLL=C:\Program Files\Poscenter\DrvKKT\Bin\DrvFR.dll"
if not defined DRV_DLL if exist "C:\Program Files\Shtrih-M\DrvFR\Bin\DrvFR.dll" set "DRV_DLL=C:\Program Files\Shtrih-M\DrvFR\Bin\DrvFR.dll"
if not defined DRV_DLL (
    echo [ERROR] DrvFR.dll not found. Install KKT driver first.
    goto :fail
)
echo       Found: !DRV_DLL!
regsvr32 /s "!DRV_DLL!"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] regsvr32 failed for !DRV_DLL!
    goto :fail
)

"%PYTHON_EXE%" -c "import sys,win32com.client;win32com.client.Dispatch('AddIn.DrvFR');sys.exit(0)" 2>nul
set COM_RESULT=%ERRORLEVEL%

if %COM_RESULT% NEQ 0 goto :com_fail
echo       Registered.
goto :com_ok

:com_fail
echo       [WARN] COM driver registered but Dispatch failed.
"%PYTHON_EXE%" -c "import win32com.client;win32com.client.Dispatch('AddIn.DrvFR')"
echo       Continuing anyway...
echo:

:com_ok
echo       OK
echo:

:: ========================================
:: 4. USB VCOM/DFU driver
:: ========================================
echo [4/5] USB VCOM/DFU driver...

call "%SCRIPT_DIR%\install_dfu_driver.bat" "%VCOM_DFU_DIR%" > "%DFU_DRIVER_LOG%" 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo       [WARN] VCOM/DFU driver installation failed. Firmware update will continue.
    echo       [WARN] Driver install log: %DFU_DRIVER_LOG%
    set "DFU_DRIVER_WARN=1"
) else (
    echo       OK
)
echo:

:: ========================================
:: 5. Firmware files check
:: ========================================
echo [5/5] Firmware in %FW_DIR%...

set BIN_FOUND=0
for %%f in ("%FW_DIR%\*.bin") do set BIN_FOUND=1
if %BIN_FOUND%==0 (
    echo [ERROR] No *.bin files in %FW_DIR%
    goto :fail
)
echo       OK
echo:

:: ========================================
:: Close 1C clients (they hold the KKT / COM port)
:: ========================================
echo [*] Closing 1C clients that may hold the KKT...
for %%P in (1cv8.exe 1cv8c.exe) do (
    tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul
    if !ERRORLEVEL! EQU 0 (
        echo       Stopping %%P ...
        taskkill /F /T /IM %%P >nul 2>&1
    )
)
echo       OK
echo:

:: ========================================
:: Run update
:: ========================================
echo ========================================
echo  All checks passed. Starting update...
echo ========================================
echo:

"%PYTHON_EXE%" "%SCRIPT_DIR%\kkt_firmware_update.py" --ip %KKT_IP% --port %KKT_PORT% --file "%FW_DIR%" --force --report-json "%SCRIPT_DIR%\update_report.json"

if %ERRORLEVEL% NEQ 0 goto :update_fail

echo:
call :print_dfu_driver_warning
echo [SUCCESS] Update completed.
type nul > "%FLAG_FILE%"
exit /b 0

:update_fail
echo:
call :print_dfu_driver_warning
echo [ERROR] Update failed. See update_kkt.log
goto :fail

:print_dfu_driver_warning
if "%DFU_DRIVER_WARN%"=="1" (
    echo:
    echo ############################################################
    echo # WARNING: USB VCOM/DFU DRIVER INSTALLATION FAILED         #
    echo # Firmware update was NOT stopped because of this warning. #
    echo # Check driver install log:                                #
    echo #   %DFU_DRIVER_LOG%
    echo ############################################################
    echo:
)
exit /b 0

:fail
echo:
echo Press any key to close...
pause > nul
exit /b 1
