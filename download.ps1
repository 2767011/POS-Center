# download.ps1 - Compatibility wrapper for the universal KKT updater preparation.
# New code should call prepare_update.ps1 directly.
param(
    [string]$Source = '',
    [string]$BaseUrl = '',
    [string]$FwUrl = '',
    [string]$Dir = '',
    [string]$FwDir = '',
    [string]$DfuDir = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Dir) {
    if ($MyInvocation.MyCommand.Path) {
        $Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $Dir = (Get-Location).Path
    }
}

if (-not $Source -and $BaseUrl) {
    $Source = $BaseUrl
}

if (-not $Source -and $env:KKT_SOURCE) {
    $Source = $env:KKT_SOURCE
}

if (-not $Source) {
    $Source = $Dir
}

if (-not (Test-Path -LiteralPath $Dir)) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
}

$preparePath = Join-Path $Dir 'prepare_update.ps1'
if (-not (Test-Path -LiteralPath $preparePath)) {
    if ($MyInvocation.MyCommand.Path) {
        $localPrepare = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'prepare_update.ps1'
        if (Test-Path -LiteralPath $localPrepare) {
            Copy-Item -LiteralPath $localPrepare -Destination $preparePath -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $preparePath) -and $Source -match '^https?://') {
    $sourceRoot = $Source.TrimEnd('/')
    $urls = @($sourceRoot + '/prepare_update.ps1', $sourceRoot + '/Updater/prepare_update.ps1')
    $client = New-Object System.Net.WebClient
    try {
        foreach ($url in $urls) {
            try {
                $client.DownloadFile($url, $preparePath)
                if (Test-Path -LiteralPath $preparePath) { break }
            } catch {
            }
        }
    } finally {
        $client.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $preparePath)) {
    Write-Host '[ERROR] prepare_update.ps1 not found.'
    exit 1
}

$prepareArgs = @{
    Source = $Source
    Dir = $Dir
}
if ($BaseUrl) { $prepareArgs.BaseUrl = $BaseUrl }
if ($FwUrl) { $prepareArgs.FwUrl = $FwUrl }
if ($FwDir) { $prepareArgs.FwDir = $FwDir }
if ($DfuDir) { $prepareArgs.DfuDir = $DfuDir }

& $preparePath @prepareArgs
exit $LASTEXITCODE
