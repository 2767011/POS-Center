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

call :install_inf "DFU" "%DFU_INF%"
if !ERRORLEVEL! NEQ 0 exit /b 1

call :install_inf "VCOM" "%VCOM_INF%"
if !ERRORLEVEL! NEQ 0 exit /b 1

echo VCOM/DFU drivers installed.
exit /b 0

:install_inf
set "DRIVER_NAME=%~1"
set "INF_PATH=%~2"
set "LOG_FILE=%TEMP%\kkt_%DRIVER_NAME%_pnputil.log"
set "CAT_PATH=%~dpn2.cat"

echo Installing %DRIVER_NAME% driver...
echo       INF: %INF_PATH%

if exist "%CAT_PATH%" (
    call :trust_catalog_publisher "%DRIVER_NAME%" "%CAT_PATH%"
    if !ERRORLEVEL! NEQ 0 (
        echo       [WARN] Cannot add %DRIVER_NAME% publisher to TrustedPublisher.
    )
) else (
    echo       [WARN] Catalog file not found: %CAT_PATH%
)

pnputil /add-driver "%INF_PATH%" /install > "%LOG_FILE%" 2>&1
if !ERRORLEVEL! EQU 0 (
    echo       OK: %DRIVER_NAME%
    exit /b 0
)

pnputil -i -a "%INF_PATH%" >> "%LOG_FILE%" 2>&1
if !ERRORLEVEL! EQU 0 (
    echo       OK: %DRIVER_NAME%
    exit /b 0
)

echo [ERROR] Failed to install %DRIVER_NAME% driver.
echo         See log: %LOG_FILE%
type "%LOG_FILE%"
exit /b 1

:trust_catalog_publisher
set "DRIVER_NAME=%~1"
set "CAT_PATH=%~2"

echo       Trusting %DRIVER_NAME% catalog publisher...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cat = '%CAT_PATH%'; $sig = Get-AuthenticodeSignature -LiteralPath $cat; if (-not $sig.SignerCertificate) { throw 'No signer certificate found' }; $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine'); $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite); try { $thumb = $sig.SignerCertificate.Thumbprint; $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $thumb }; if ($existing) { Write-Host ('      TrustedPublisher already has: ' + $thumb) } else { $store.Add($sig.SignerCertificate); Write-Host ('      Added TrustedPublisher: ' + $thumb) } } finally { $store.Close() }"
if %ERRORLEVEL% NEQ 0 exit /b 1
exit /b 0
