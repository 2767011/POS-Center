# download.ps1 - Downloads all KKT updater files from web server
# Called by auto_update.bat
param(
    [string]$BaseUrl = 'http://192.168.20.229/KKT/Updater',
    [string]$FwUrl   = 'http://192.168.20.229/KKT/FW_FR',
    [string]$Dir     = '',
    [string]$FwDir   = '',
    [string]$DfuDir  = ''
)

$ErrorActionPreference = 'Continue'

if (-not $Dir) {
    if ($MyInvocation.MyCommand.Path) {
        $Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $Dir = (Get-Location).Path
    }
}

if (-not $FwDir) {
    $FwDir = Join-Path $Dir 'firmware'
}

if (-not $DfuDir) {
    $DfuDir = Join-Path $Dir 'VCOM+DFU'
}

function Download-FileCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Uri, $OutFile)
    } finally {
        $client.Dispose()
    }
}

function Get-UrlContentCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $client = New-Object System.Net.WebClient
    try {
        return $client.DownloadString($Uri)
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
        Write-Host "      [WARN] .NET ZipFile extraction unavailable: $($_.Exception.Message)"
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
                return
            }
        }
    }

    throw "ZIP extraction timed out"
}

if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
if (-not (Test-Path $FwDir)) { New-Item -ItemType Directory -Path $FwDir -Force | Out-Null }

# 1. Download scripts
$scripts = @(
    'install_python.ps1',
    'build_python_package.ps1',
    'kkt_driver.py',
    'kkt_firmware_update.py',
    'kkt_dump_tables.py',
    'kkt_info.py',
    'register_drvfr.bat',
    'install_dfu_driver.bat',
    'run_update.bat',
    'run.bat',
    'config.bat',
    'setup.bat',
    'probe_com.py'
)

Write-Host '      Downloading scripts...'
$failCount = 0
foreach ($f in $scripts) {
    try {
        Download-FileCompat -Uri "$BaseUrl/$f" -OutFile (Join-Path $Dir $f)
        Write-Host "      OK: $f"
    } catch {
        Write-Host "      [WARN] Failed: $f - $($_.Exception.Message)"
        $failCount++
    }
}

# 2. Download and extract VCOM/DFU driver package
Write-Host '      Downloading VCOM/DFU driver package...'
try {
    $dfuPackage = 'VCOM+DFU.zip'
    $dfuZipPath = Join-Path $Dir $dfuPackage
    Download-FileCompat -Uri "$BaseUrl/$dfuPackage" -OutFile $dfuZipPath
    Expand-ZipCompat -Path $dfuZipPath -DestinationPath $DfuDir

    $dfuInf = Join-Path $DfuDir 'Windows\INF\dfu\lpc-composite89-dfu.inf'
    $vcomInf = Join-Path $DfuDir 'Windows\INF\vcom\lpc-ucom-vcom.inf'
    if (-not (Test-Path $dfuInf) -or -not (Test-Path $vcomInf)) {
        throw 'Driver package extracted, but required INF files were not found'
    }

    Write-Host '      OK: VCOM+DFU.zip'
} catch {
    Write-Host "      [WARN] Failed VCOM/DFU package: $($_.Exception.Message)"
    $failCount++
}

# 3. Download firmware files (.bin) from Apache directory listing
Write-Host '      Downloading firmware...'
try {
    $html = Get-UrlContentCompat -Uri "$FwUrl/"
    $links = [regex]::Matches($html, 'href=["'']([^"''?#]+\.bin)["'']') |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique
    foreach ($f in $links) {
        $name = [System.IO.Path]::GetFileName([System.Uri]::UnescapeDataString($f))
        if (-not $name) { continue }
        if ($f -match '^https?://') {
            $fileUrl = $f
        } elseif ($f.StartsWith('/')) {
            $baseUri = New-Object System.Uri -ArgumentList $FwUrl
            $fileUri = New-Object System.Uri -ArgumentList $baseUri, $f
            $fileUrl = $fileUri.AbsoluteUri
        } else {
            $fileUrl = "$FwUrl/$f"
        }
        try {
            Download-FileCompat -Uri $fileUrl -OutFile (Join-Path $FwDir $name)
            Write-Host "      OK: $name"
        } catch {
            Write-Host "      [WARN] Failed: $name - $($_.Exception.Message)"
            $failCount++
        }
    }
} catch {
    Write-Host "      [WARN] Cannot read firmware index: $($_.Exception.Message)"
    $failCount++
}

# 4. Download table_after_update.csv
try {
    Download-FileCompat -Uri "$FwUrl/table_after_update.csv" -OutFile (Join-Path $FwDir 'table_after_update.csv')
    Write-Host '      OK: table_after_update.csv'
} catch {
    # Not critical
}

if ($failCount -gt 0) {
    Write-Host "      [WARN] $failCount file(s) failed to download"
    exit 1
}

Write-Host '      All downloads OK'
exit 0
