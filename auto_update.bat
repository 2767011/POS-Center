@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul

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

set "FLAG_FILE=%SCRIPT_DIR%\update_success.flag"
set "PYTHON_DIR=%SCRIPT_DIR%\python"
set "PYTHON_EXE=%PYTHON_DIR%\python.exe"
set "FW_DIR=%SCRIPT_DIR%\firmware"
set "VCOM_DFU_DIR=%SCRIPT_DIR%\VCOM+DFU"
set "DFU_DRIVER_LOG=%SCRIPT_DIR%\dfu_driver_install.log"
set "DFU_DRIVER_WARN=0"

set "BASE_URL=http://192.168.20.229/KKT/Updater"
set "FW_URL=http://192.168.20.229/KKT/FW_FR"

echo ========================================
echo  KKT Auto Update
echo ========================================
echo:

:: ========================================
:: 0. Download all files from server
:: ========================================
echo [0/5] Downloading files from server...

:: Step 0a: Download the download script itself
echo       Fetching download.ps1...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$wc=New-Object System.Net.WebClient; try { $wc.DownloadFile('%BASE_URL%/download.ps1', '%SCRIPT_DIR%\download.ps1') } finally { $wc.Dispose() }"
if not exist "%SCRIPT_DIR%\download.ps1" (
    echo [ERROR] Cannot download download.ps1 from %BASE_URL%
    echo         Check network connectivity to 192.168.20.229
    goto :fail
)

:: Step 0b: Run the download script with parameters
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\download.ps1" -Dir "%SCRIPT_DIR%" -FwDir "%FW_DIR%" -DfuDir "%VCOM_DFU_DIR%" -BaseUrl "%BASE_URL%" -FwUrl "%FW_URL%"
if !ERRORLEVEL! NEQ 0 (
    echo       [WARN] Some downloads may have failed
)

:: Критические файлы должны существовать после загрузки
set "REQ_MISSING=0"
for %%f in (kkt_firmware_update.py kkt_driver.py kkt_dump_tables.py config.bat install_python.ps1 install_dfu_driver.bat) do (
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
    echo [ERROR] Required files are missing after download. Aborting.
    goto :fail
)

echo       Downloads complete.
echo:

:: Load config (downloaded by download.ps1)
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\install_python.ps1"
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
