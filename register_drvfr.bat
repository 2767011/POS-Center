@echo off
REM ============================================================
REM Universal DrvFR.dll registration script
REM Works on both 32-bit and 64-bit Windows
REM Detects DrvFR.dll location and registers it properly
REM Must be run as Administrator!
REM ============================================================
setlocal enabledelayedexpansion

echo ========================================
echo  DrvFR.dll Universal Register Tool
echo ========================================
echo.

REM Detect OS architecture
if exist "%SystemRoot%\SysWOW64" (
    set OS_ARCH=64
    echo OS: 64-bit
) else (
    set OS_ARCH=32
    echo OS: 32-bit
)

REM Detect DrvFR.dll locations
set DLL64=
set DLL32=

REM Check 64-bit path (Program Files)
if exist "C:\Program Files\Poscenter\DrvKKT\Bin\DrvFR.dll" (
    set "DLL64=C:\Program Files\Poscenter\DrvKKT\Bin\DrvFR.dll"
    echo Found 64-bit DLL: !DLL64!
)

REM Check 32-bit path (Program Files x86)
if exist "C:\Program Files (x86)\Poscenter\DrvKKT\Bin\DrvFR.dll" (
    set "DLL32=C:\Program Files (x86)\Poscenter\DrvKKT\Bin\DrvFR.dll"
    echo Found 32-bit DLL: !DLL32!
)

REM Also check without Poscenter (Shtrih-M original)
if not defined DLL64 if exist "C:\Program Files\Shtrih-M\DrvFR\Bin\DrvFR.dll" (
    set "DLL64=C:\Program Files\Shtrih-M\DrvFR\Bin\DrvFR.dll"
    echo Found 64-bit DLL: !DLL64!
)
if not defined DLL32 if exist "C:\Program Files (x86)\Shtrih-M\DrvFR\Bin\DrvFR.dll" (
    set "DLL32=C:\Program Files (x86)\Shtrih-M\DrvFR\Bin\DrvFR.dll"
    echo Found 32-bit DLL: !DLL32!
)

echo.

REM No DLL found at all
if not defined DLL64 if not defined DLL32 (
    echo [ERROR] DrvFR.dll not found in any known location.
    echo Checked paths:
    echo   C:\Program Files\Poscenter\DrvKKT\Bin\
    echo   C:\Program Files ^(x86^)\Poscenter\DrvKKT\Bin\
    echo   C:\Program Files\Shtrih-M\DrvFR\Bin\
    echo   C:\Program Files ^(x86^)\Shtrih-M\DrvFR\Bin\
    pause
    exit /b 1
)

set CLSID={E187099F-8C5C-4723-8866-D8DBB6353ADE}

REM ============================================================
REM Case 1: 32-bit OS - just register the DLL
REM ============================================================
if "%OS_ARCH%"=="32" (
    echo 32-bit OS: Simple registration...
    if defined DLL32 (
        regsvr32 /s "!DLL32!"
    ) else if defined DLL64 (
        regsvr32 /s "!DLL64!"
    )
    if !errorlevel! neq 0 (
        echo [ERROR] regsvr32 failed!
        pause
        exit /b 1
    )
    echo [OK] DrvFR.dll registered.
    goto :verify
)

REM ============================================================
REM Case 2: 64-bit OS with 64-bit DLL - register natively
REM ============================================================
if "%OS_ARCH%"=="64" if defined DLL64 (
    echo 64-bit OS + 64-bit DLL: Native registration...
    regsvr32 /s "!DLL64!"
    if !errorlevel! neq 0 (
        echo [ERROR] regsvr32 failed for 64-bit DLL!
        pause
        exit /b 1
    )
    echo [OK] 64-bit DrvFR.dll registered natively.
    
    REM Also register 32-bit if available (for 32-bit apps)
    if defined DLL32 (
        echo Also registering 32-bit DLL for 32-bit apps...
        C:\Windows\SysWOW64\regsvr32.exe /s "!DLL32!"
    )
    goto :verify
)

REM ============================================================
REM Case 3: 64-bit OS with only 32-bit DLL - need 64-bit DLL
REM ============================================================
if "%OS_ARCH%"=="64" if not defined DLL64 if defined DLL32 (
    echo 64-bit OS + 32-bit DLL only.
    echo.
    echo [1/2] Registering 32-bit DLL for 32-bit apps...
    C:\Windows\SysWOW64\regsvr32.exe /s "!DLL32!"
    if !errorlevel! neq 0 (
        echo [ERROR] regsvr32 failed for 32-bit DLL!
        pause
        exit /b 1
    )
    echo       OK
    echo.
    echo [WARNING] 32-bit DrvFR.dll will NOT work with 64-bit Python!
    echo To use with 64-bit Python, copy 64-bit DrvFR.dll + dependencies:
    echo   DrvFR.dll, DrvFR.lic, libeay32.dll, ssleay32.dll, sqlite3.dll
    echo to: C:\Program Files\Poscenter\DrvKKT\Bin\
    echo then re-run this script.
    echo.
    goto :verify
)

:verify
echo.
echo ========================================
echo  Verification
echo ========================================
echo.
echo Checking registry...
reg query "HKLM\SOFTWARE\Classes\Addin.DrvFR\CLSID" 2>nul
echo.
if "%OS_ARCH%"=="64" (
    echo 64-bit CLSID:
    reg query "HKLM\SOFTWARE\Classes\CLSID\%CLSID%\InprocServer32" 2>nul
    echo.
    echo 32-bit CLSID:
    reg query "HKLM\SOFTWARE\Classes\Wow6432Node\CLSID\%CLSID%\InprocServer32" 2>nul
)
echo.
echo ========================================
echo  Test with: python -c "import win32com.client; d=win32com.client.Dispatch('Addin.DrvFR'); print('OK:', d.Password)"
echo ========================================
echo.
pause
