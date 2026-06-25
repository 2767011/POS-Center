@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul

set "DRIVER_ROOT=%~1"
if "%DRIVER_ROOT%"=="" set "DRIVER_ROOT=%~dp0VCOM+DFU"

set "DFU_INF=%DRIVER_ROOT%\Windows\INF\dfu\lpc-composite89-dfu.inf"
set "VCOM_INF=%DRIVER_ROOT%\Windows\INF\vcom\lpc-ucom-vcom.inf"

echo --- VCOM/DFU Driver Installer ---
echo Driver root: %DRIVER_ROOT%

where pnputil > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] pnputil.exe not found.
    exit /b 1
)

if not exist "%DFU_INF%" (
    echo [ERROR] DFU INF not found: %DFU_INF%
    exit /b 1
)

if not exist "%VCOM_INF%" (
    echo [ERROR] VCOM INF not found: %VCOM_INF%
    exit /b 1
)

call :stage_inf "DFU" "%DFU_INF%"
if !ERRORLEVEL! NEQ 0 exit /b 1

call :stage_inf "VCOM" "%VCOM_INF%"
if !ERRORLEVEL! NEQ 0 exit /b 1

echo VCOM/DFU drivers staged into driver store.
exit /b 0

:stage_inf
set "DRIVER_NAME=%~1"
set "INF_PATH=%~2"
set "LOG_FILE=%TEMP%\kkt_%DRIVER_NAME%_pnputil.log"
set "CAT_PATH=%~dpn2.cat"

echo Staging %DRIVER_NAME% driver...
echo       INF: %INF_PATH%

if exist "%CAT_PATH%" (
    call :trust_catalog_publisher "%DRIVER_NAME%" "%CAT_PATH%"
    if !ERRORLEVEL! NEQ 0 (
        echo       [WARN] Cannot add %DRIVER_NAME% publisher to TrustedPublisher.
    )
) else (
    echo       [WARN] Catalog file not found: %CAT_PATH%
)

REM The KKT enters DFU mode only during flashing, so the USB device is NOT
REM present at this preflight step. We therefore only STAGE the driver into
REM the driver store (no install-on-present-device). Windows installs it
REM automatically via PnP when the device appears in DFU mode.
REM Note: do NOT use /install (Win10+) or -i (legacy) - both require a
REM matching device to be present and fail with "No more data is available".

REM Try modern syntax first (Windows 10 1607+).
pnputil /add-driver "%INF_PATH%" > "%LOG_FILE%" 2>&1
call :staging_ok "%LOG_FILE%" !ERRORLEVEL!
if !ERRORLEVEL! EQU 0 (
    echo       OK: %DRIVER_NAME% staged into driver store.
    exit /b 0
)

REM Fallback to legacy syntax (Windows 7 / 8.1).
pnputil -a "%INF_PATH%" >> "%LOG_FILE%" 2>&1
call :staging_ok "%LOG_FILE%" !ERRORLEVEL!
if !ERRORLEVEL! EQU 0 (
    echo       OK: %DRIVER_NAME% staged into driver store ^(legacy pnputil^).
    exit /b 0
)

echo [ERROR] Failed to stage %DRIVER_NAME% driver into the store.
echo         See log: %LOG_FILE%
type "%LOG_FILE%"
exit /b 1

:staging_ok
REM %1 = log file, %2 = pnputil exit code.
REM Returns 0 if the driver package is in the store, 1 otherwise.
REM Staging is a success regardless of "Number successfully imported",
REM which only counts installs onto present devices.
set "_LOG=%~1"
set "_RC=%~2"

if "%_RC%"=="0" exit /b 0

REM Even with a non-zero exit code the package may already be staged or
REM up-to-date in the store. Detect that from the pnputil output.
findstr /I /C:"Driver package added successfully" /C:"Published" /C:"up-to-date" "%_LOG%" >nul 2>&1
if !ERRORLEVEL! EQU 0 exit /b 0

exit /b 1

:trust_catalog_publisher
set "DRIVER_NAME=%~1"
set "CAT_PATH=%~2"

echo       Trusting %DRIVER_NAME% catalog publisher...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cat = '%CAT_PATH%'; $sig = Get-AuthenticodeSignature -LiteralPath $cat; if (-not $sig.SignerCertificate) { throw 'No signer certificate found' }; $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine'); $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite); try { $thumb = $sig.SignerCertificate.Thumbprint; $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $thumb }; if ($existing) { Write-Host ('      TrustedPublisher already has: ' + $thumb) } else { $store.Add($sig.SignerCertificate); Write-Host ('      Added TrustedPublisher: ' + $thumb) } } finally { $store.Close() }"
if %ERRORLEVEL% NEQ 0 exit /b 1
exit /b 0
