# download.ps1 - Downloads all KKT updater files from web server
# Called by auto_update.bat
param(
    [string]$BaseUrl = 'http://192.168.20.229/KKT/Updater',
    [string]$FwUrl   = 'http://192.168.20.229/KKT/FW_FR',
    [string]$Dir     = $PSScriptRoot,
    [string]$FwDir   = (Join-Path $PSScriptRoot 'firmware')
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
if (-not (Test-Path $FwDir)) { New-Item -ItemType Directory -Path $FwDir -Force | Out-Null }

# 1. Download scripts
$scripts = @(
    'install_python.ps1',
    'kkt_firmware_update.py',
    'kkt_dump_tables.py',
    'kkt_info.py',
    'kkt_firmware_manager.py',
    'register_drvfr.bat',
    'run_update.bat',
    'setup.bat',
    'probe_com.py'
)

Write-Host '      Downloading scripts...'
$failCount = 0
foreach ($f in $scripts) {
    try {
        Invoke-WebRequest -Uri "$BaseUrl/$f" -OutFile (Join-Path $Dir $f) -UseBasicParsing
        Write-Host "      OK: $f"
    } catch {
        Write-Host "      [WARN] Failed: $f - $($_.Exception.Message)"
        $failCount++
    }
}

# 2. Download firmware files (.bin) from Apache directory listing
Write-Host '      Downloading firmware...'
try {
    $r = Invoke-WebRequest -Uri "$FwUrl/" -UseBasicParsing
    $links = $r.Links | Where-Object { $_.href -match '\.bin$' } | ForEach-Object { $_.href }
    foreach ($f in $links) {
        $name = [System.Uri]::UnescapeDataString($f)
        try {
            Invoke-WebRequest -Uri "$FwUrl/$f" -OutFile (Join-Path $FwDir $name) -UseBasicParsing
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

# 3. Download table_after_update.csv
try {
    Invoke-WebRequest -Uri "$FwUrl/table_after_update.csv" -OutFile (Join-Path $FwDir 'table_after_update.csv') -UseBasicParsing
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
