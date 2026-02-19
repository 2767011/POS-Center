# setup_env.ps1 - KKT environment setup
# ASCII-only output to avoid encoding issues in Windows console

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (!$isAdmin) {
    Write-Host "[WARN] Not running as Administrator. Some operations may fail." -ForegroundColor Yellow
    Write-Host "       For full install, right-click setup.bat -> Run as Administrator" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "--- KKT Environment Setup ---" -ForegroundColor Cyan

# 1. Find real Python (not Windows Store alias)
$pythonExe = $null

# Try 'py' launcher first (most reliable on Windows)
$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($pyLauncher) {
    $testVer = & py --version 2>&1
    if ($testVer -match "Python \d+\.\d+") {
        $pythonExe = "py"
        Write-Host "[OK] Python found via 'py' launcher: $testVer" -ForegroundColor Green
    }
}

# Try 'python' if py not found
if (-not $pythonExe) {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        # Check if it's the real python or Windows Store alias
        $testVer = & python --version 2>&1
        if ($testVer -match "Python \d+\.\d+") {
            $pythonExe = "python"
            Write-Host "[OK] Python found: $testVer" -ForegroundColor Green
        } else {
            Write-Host "[WARN] 'python' is a Windows Store alias, not real Python" -ForegroundColor Yellow
        }
    }
}

# Try 'python3'
if (-not $pythonExe) {
    $python3Cmd = Get-Command python3 -ErrorAction SilentlyContinue
    if ($python3Cmd) {
        $testVer = & python3 --version 2>&1
        if ($testVer -match "Python \d+\.\d+") {
            $pythonExe = "python3"
            Write-Host "[OK] Python found via 'python3': $testVer" -ForegroundColor Green
        }
    }
}

# If no Python found, install it
if (-not $pythonExe) {
    Write-Host "[!!] Python not found. Installing via Winget..." -ForegroundColor Yellow
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        & winget install -e --id Python.Python.3.11 --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Python installed. Restart terminal to apply PATH." -ForegroundColor Green
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            # Re-check
            $testVer = & py --version 2>&1
            if ($testVer -match "Python \d+\.\d+") {
                $pythonExe = "py"
            } else {
                $pythonExe = "python"
            }
        } else {
            Write-Host "[FAIL] Winget install failed." -ForegroundColor Red
            Write-Host "       Install Python manually from https://python.org" -ForegroundColor Red
            Write-Host "       IMPORTANT: Check 'Add Python to PATH' during install!" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit
        }
    } else {
        Write-Host "[FAIL] Winget not available and Python not found." -ForegroundColor Red
        Write-Host "       Install Python manually from https://python.org" -ForegroundColor Red
        Write-Host "       IMPORTANT: Check 'Add Python to PATH' during install!" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit
    }
}

Write-Host "Using Python command: $pythonExe" -ForegroundColor Cyan

# 2. Check pip
Write-Host "Checking pip..." -ForegroundColor Cyan
& $pythonExe -m ensurepip --default-pip 2>$null
& $pythonExe -m pip install --upgrade pip 2>$null
Write-Host "[OK] pip ready" -ForegroundColor Green

# 3. Install pywin32
Write-Host "Installing pywin32 (win32com)..." -ForegroundColor Cyan
$pipOutput = & $pythonExe -m pip install pywin32 2>&1
$pipOutput | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] pywin32 installed" -ForegroundColor Green
} else {
    Write-Host "[FAIL] pywin32 install error. Trying with --user flag..." -ForegroundColor Yellow
    $pipOutput2 = & $pythonExe -m pip install --user pywin32 2>&1
    $pipOutput2 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] pywin32 installed (user mode)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] pywin32 install failed." -ForegroundColor Red
        Write-Host "       Try manually: $pythonExe -m pip install pywin32" -ForegroundColor Red
    }
}

# 4. Check KKT driver (AddIn.DrvFR or SrvFRLib.SrvFR)
Write-Host "Checking KKT driver..." -ForegroundColor Cyan
$driverFound = $false
$driverProgIds = @("AddIn.DrvFR", "SrvFRLib.SrvFR")
foreach ($progId in $driverProgIds) {
    try {
        $drv = New-Object -ComObject $progId
        if ($drv) {
            Write-Host "[OK] Driver '$progId' found and working" -ForegroundColor Green
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($drv) | Out-Null
            $driverFound = $true
            break
        }
    } catch {
        # try next
    }
}
if (-not $driverFound) {
    Write-Host "[WARN] KKT driver not found (checked: $($driverProgIds -join ', '))" -ForegroundColor Yellow
    Write-Host "       Install KKT driver from shtrih-m.ru or pos-center.ru" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Setup complete ---" -ForegroundColor Cyan
Read-Host "Press Enter to exit"
