# build_python_package.ps1 - Сборка готового python_ready.zip для деплоя на кассы
#
# Запускать на машине с интернетом. Один раз при обновлении версии.
# Результаты положить на сервер:
#   http://192.168.20.229/KKT/Updater/python_ready.zip
#   http://192.168.20.229/KKT/Updater/python_ready_win7.zip
#
# Использование:
#   pwsh -NoProfile -File build_python_package.ps1
#   pwsh -NoProfile -File build_python_package.ps1 -Win7
#   pwsh -NoProfile -File build_python_package.ps1 -OutputPath "C:\share\python_ready.zip"

param(
    [switch]$Win7,
    [string]$PyVersion = "",
    [string]$OutputPath = "",
    [string]$WorkDir = ".\__build_python",
    [string]$Pywin32Package = ""
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Win7) {
    if (-not $PyVersion) { $PyVersion = "3.8.10" }
    if (-not $OutputPath) { $OutputPath = ".\python_ready_win7.zip" }
    if (-not $Pywin32Package) { $Pywin32Package = "pywin32==306" }
    $getPipUrl = "https://bootstrap.pypa.io/pip/3.8/get-pip.py"
} else {
    if (-not $PyVersion) { $PyVersion = "3.11.5" }
    if (-not $OutputPath) { $OutputPath = ".\python_ready.zip" }
    if (-not $Pywin32Package) { $Pywin32Package = "pywin32" }
    $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
}

$pyUrl = "https://www.python.org/ftp/python/$PyVersion/python-$PyVersion-embed-amd64.zip"
$embedZip = Join-Path $WorkDir "python_embed.zip"
$extractPath = Join-Path $WorkDir "python"

Write-Host "=== Python Package Builder ===" -ForegroundColor Cyan
if ($Win7) { Write-Host "Target: Windows 7" }
Write-Host "Python version: $PyVersion"
Write-Host "pywin32 package: $Pywin32Package"
Write-Host "Output: $OutputPath"
Write-Host ""

# Cleanup
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# 1. Download Python embed
Write-Host "[1/5] Downloading Python $PyVersion embed..."
Invoke-WebRequest -Uri $pyUrl -OutFile $embedZip
Write-Host "  OK: $([math]::Round((Get-Item $embedZip).Length/1MB, 1)) MB"

# 2. Extract
Write-Host "[2/5] Extracting..."
Expand-Archive -Path $embedZip -DestinationPath $extractPath -Force
Remove-Item $embedZip -Force

# 3. Patch ._pth for pip support
Write-Host "[3/5] Patching ._pth for pip support..."
$pthFile = Get-ChildItem "$extractPath\*._pth" | Select-Object -First 1
if ($pthFile) {
    $content = Get-Content $pthFile.FullName
    $newContent = $content -replace "#import site", "import site"
    Set-Content $pthFile.FullName $newContent
    Write-Host "  Patched: $($pthFile.Name)"
} else {
    Write-Host "  [WARN] No ._pth file found!"
}

# 4. Install pip + pywin32
Write-Host "[4/5] Installing pip and pywin32..."
$getPipPath = Join-Path $WorkDir "get-pip.py"
Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipPath
& "$extractPath\python.exe" $getPipPath --no-warn-script-location
Remove-Item $getPipPath -Force

& "$extractPath\python.exe" -m pip install $Pywin32Package --no-warn-script-location
Write-Host "  Verifying pywin32..."
& "$extractPath\python.exe" -c "import win32com.client; print('  pywin32 OK')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] pywin32 verification failed!" -ForegroundColor Red
    exit 1
}

# 5. Package
Write-Host "[5/5] Creating $OutputPath..."
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

# Упаковываем содержимое папки python (без вложенной папки python\)
Compress-Archive -Path "$extractPath\*" -DestinationPath $OutputPath -CompressionLevel Optimal
$zipSize = [math]::Round((Get-Item $OutputPath).Length/1MB, 1)
Write-Host "  OK: $zipSize MB"

# Cleanup
Remove-Item $WorkDir -Recurse -Force

Write-Host ""
Write-Host "=== Done! ===" -ForegroundColor Green
Write-Host "File: $OutputPath ($zipSize MB)"
Write-Host ""
Write-Host "Deploy:" -ForegroundColor Yellow
Write-Host "  Copy $OutputPath to server: http://192.168.20.229/KKT/Updater/$(Split-Path $OutputPath -Leaf)"
