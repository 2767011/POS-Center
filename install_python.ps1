# install_python.ps1 - Установка Portable Python из готового пакета
# Пакет python_ready.zip готовится скриптом build_python_package.ps1 и содержит
# Python + pip + pywin32 в одном архиве. Это исключает скачивание из интернета
# и зависание pip при запуске через PsExec.

param(
    [string]$PackageSource = '',
    [string]$BaseUrl = ''
)

$ErrorActionPreference = "Stop"

$extractPath = "python"

if (-not $PackageSource -and $env:KKT_PACKAGE_SOURCE) {
    $PackageSource = $env:KKT_PACKAGE_SOURCE
}

if (-not $BaseUrl -and $env:KKT_BASE_URL) {
    $BaseUrl = $env:KKT_BASE_URL
}

if (-not $BaseUrl -and $env:KKT_SOURCE -and $env:KKT_SOURCE -match '^https?://') {
    $BaseUrl = $env:KKT_SOURCE
}

function Test-IsHttpSource {
    param([string]$Value)
    return ($Value -match '^https?://')
}

function Join-Url {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base,

        [Parameter(Mandatory = $true)]
        [string]$Child
    )

    return $Base.TrimEnd('/') + '/' + $Child.TrimStart('/')
}

function Get-UpdaterUrl {
    param([string]$SourceUrl)

    if (-not $SourceUrl) { return '' }
    $sourceRoot = $SourceUrl.TrimEnd('/')
    if ($sourceRoot -match '/Updater/?$') {
        return $sourceRoot
    }
    return (Join-Url $sourceRoot 'Updater')
}

function Get-WindowsVersionCompat {
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        return [version]$os.Version
    } catch {
        return [Environment]::OSVersion.Version
    }
}

$windowsVersion = Get-WindowsVersionCompat
$isWindows7 = ($windowsVersion.Major -eq 6 -and $windowsVersion.Minor -eq 1)
$updaterUrl = Get-UpdaterUrl -SourceUrl $BaseUrl

if ($isWindows7) {
    # Python 3.8 is the last Python line suitable for Windows 7.
    $readyPackage = "python_ready_win7.zip"
    $pyVersion = "3.8.10"
    $pywin32Package = "pywin32==306"
    $getPipUrl = "https://bootstrap.pypa.io/pip/3.8/get-pip.py"
} else {
    $readyPackage = "python_ready.zip"
    $pyVersion = "3.11.5"
    $pywin32Package = "pywin32"
    $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
}

$readyUrl = ''
if ($updaterUrl) {
    $readyUrl = Join-Url $updaterUrl $readyPackage
}
$zipPath = $readyPackage

# Fallback: скачать embed-дистрибутив и поставить pip/pywin32 вручную
$pyUrl = "https://www.python.org/ftp/python/$pyVersion/python-$pyVersion-embed-amd64.zip"
$pyVersionParts = $pyVersion.Split(".")
$pyMajor = [int]$pyVersionParts[0]
$pyMinor = [int]$pyVersionParts[1]
$pythonReadyCheck = "import sys, win32com.client; raise SystemExit(0 if sys.version_info[:2] == ($pyMajor, $pyMinor) else 2)"

function Enable-Tls12Compat {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Host "  [WARN] TLS 1.2 is not available in this PowerShell/.NET runtime."
    }
}

function Download-FileCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        [int]$TimeoutSec = 0
    )

    $invokeWebRequest = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if ($invokeWebRequest) {
        if ($TimeoutSec -gt 0) {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
        } else {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        }
        return
    }

    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Uri, $OutFile)
    } finally {
        $client.Dispose()
    }
}

function Expand-ZipCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $zipFullPath = (Resolve-Path $Path).Path
    $destinationFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)

    if (Test-Path $destinationFullPath) {
        Remove-Item $destinationFullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $destinationFullPath -Force | Out-Null

    $expandArchive = Get-Command Expand-Archive -ErrorAction SilentlyContinue
    if ($expandArchive) {
        Expand-Archive -Path $zipFullPath -DestinationPath $destinationFullPath -Force
        return
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFullPath, $destinationFullPath)
        return
    } catch {
        Write-Host "  [WARN] .NET ZipFile extraction unavailable: $($_.Exception.Message)"
    }

    $shell = New-Object -ComObject Shell.Application
    $zip = $shell.NameSpace($zipFullPath)
    $destination = $shell.NameSpace($destinationFullPath)
    if (-not $zip -or -not $destination) {
        throw "Cannot open ZIP archive or destination folder"
    }

    $destination.CopyHere($zip.Items(), 0x14)

    $lastSize = -1
    $stableCount = 0
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $items = Get-ChildItem -Path $destinationFullPath -Recurse -Force -ErrorAction SilentlyContinue
        if ($items) {
            $currentSize = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
            if ($currentSize -eq $lastSize) {
                $stableCount++
            } else {
                $stableCount = 0
                $lastSize = $currentSize
            }

            if ($stableCount -ge 2) {
                Start-Sleep -Seconds 1
                Write-Host "  Extracted via Windows Shell ZIP support."
                return
            }
        }
    }

    throw "ZIP extraction timed out"
}

Write-Host "--- Portable Python Installer ---"
Write-Host "Windows version: $windowsVersion"
if ($isWindows7) {
    Write-Host "Windows 7 detected, using $readyPackage with Python $pyVersion."
}

# 1. Проверка наличия
if (Test-Path "$extractPath\python.exe") {
    # Проверяем что версия Python подходит для ОС и pywin32 тоже на месте.
    $testResult = & ".\$extractPath\python.exe" -c $pythonReadyCheck 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Python already installed and ready in $extractPath."
        exit 0
    }
    Write-Host "Python found but version/dependencies are not suitable, reinstalling..."
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# 2. Попытка взять готовый пакет из подготовленной папки или явно заданного HTTP-источника
$downloaded = $false
$scriptDir = ''
if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$packageCandidates = @()
if ($PackageSource -and -not (Test-IsHttpSource $PackageSource)) {
    $packageCandidates += (Join-Path $PackageSource $readyPackage)
}
$packageCandidates += (Join-Path (Get-Location).Path $readyPackage)
if ($scriptDir) {
    $packageCandidates += (Join-Path $scriptDir $readyPackage)
}

foreach ($candidate in ($packageCandidates | Select-Object -Unique)) {
    if (-not $candidate) { continue }
    if (Test-Path -LiteralPath $candidate) {
        $fileSize = (Get-Item -LiteralPath $candidate).Length
        if ($fileSize -gt 1048576) {
            if ((Resolve-Path -LiteralPath $candidate).Path -ne (Join-Path (Get-Location).Path $zipPath)) {
                Copy-Item -LiteralPath $candidate -Destination $zipPath -Force
            }
            $downloaded = $true
            Write-Host "Using local pre-built Python package: $candidate"
            Write-Host "  OK: $([math]::Round($fileSize/1MB, 1)) MB"
            break
        }
    }
}

if (-not $downloaded -and $readyUrl) {
    Write-Host "Downloading pre-built Python package from $readyUrl..."
    try {
        Download-FileCompat -Uri $readyUrl -OutFile $zipPath -TimeoutSec 30
        if (Test-Path $zipPath) {
            $fileSize = (Get-Item $zipPath).Length
            if ($fileSize -gt 1048576) {
                $downloaded = $true
                Write-Host "  OK: $([math]::Round($fileSize/1MB, 1)) MB"
            } else {
                Write-Host "  Downloaded file too small ($fileSize bytes), trying fallback..."
                Remove-Item $zipPath -Force
            }
        }
    } catch {
        Write-Host "  [WARN] Cannot download pre-built package: $($_.Exception.Message)"
        Write-Host "  Falling back to internet install..."
    }
}

if (-not $downloaded -and -not $readyUrl) {
    Write-Host "  [WARN] Pre-built Python package was not found locally."
    Write-Host "  Falling back to internet install..."
}

if ($downloaded) {
    # 3a. Распаковка готового пакета
    Write-Host "Extracting pre-built package..."
    Expand-ZipCompat -Path $zipPath -DestinationPath $extractPath
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # Проверка
    if (Test-Path "$extractPath\python.exe") {
        $testResult = & ".\$extractPath\python.exe" -c $pythonReadyCheck 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Done! Python with pywin32 is ready in ./$extractPath"
            exit 0
        }
        Write-Host "[WARN] Python version/dependency check failed after extraction, continuing with pip install..."
    } else {
        Write-Host "[WARN] python.exe not found after extraction"
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 3b. Fallback: ручная установка (только если готовый пакет недоступен)
Write-Host "=== Fallback: manual install from internet ==="

if (-not (Test-Path "$extractPath\python.exe")) {
    Write-Host "Downloading Python $pyVersion..."
    Enable-Tls12Compat
    $embedZip = "python_embed.zip"
    Download-FileCompat -Uri $pyUrl -OutFile $embedZip
    Write-Host "Extracting..."
    Expand-ZipCompat -Path $embedZip -DestinationPath $extractPath
    Remove-Item $embedZip -Force -ErrorAction SilentlyContinue
}

# Настройка ._pth для поддержки pip
$pthFile = Get-ChildItem "$extractPath\*._pth" | Select-Object -First 1
if ($pthFile) {
    Write-Host "Patching $($pthFile.Name) for pip support..."
    $content = Get-Content $pthFile.FullName
    $newContent = $content -replace "#import site", "import site"
    Set-Content $pthFile.FullName $newContent
}

# Установка pip
if (-not (Test-Path "$extractPath\Scripts\pip.exe")) {
    Write-Host "Downloading get-pip.py..."
    Enable-Tls12Compat
    Download-FileCompat -Uri $getPipUrl -OutFile "get-pip.py"

    Write-Host "Installing pip..."
    & ".\$extractPath\python.exe" get-pip.py --no-warn-script-location
    Remove-Item "get-pip.py" -Force -ErrorAction SilentlyContinue
}

# Установка pywin32
Write-Host "Installing $pywin32Package..."
& ".\$extractPath\python.exe" -m pip install $pywin32Package --no-warn-script-location

Write-Host "Done! Python is ready in ./$extractPath"
