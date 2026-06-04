# prepare_update.ps1 - Prepares KKT updater files from HTTP, local path, SMB share, or offline package.
# Called by auto_update.bat. The source can be a KKT root with Updater/FW_FR folders
# or the Updater folder itself.
param(
    [string]$Source = '',
    [string]$BaseUrl = '',
    [string]$FwUrl = '',
    [string]$Dir = '',
    [string]$FwDir = '',
    [string]$DfuDir = ''
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

if (-not $Source -and $env:KKT_SOURCE) {
    $Source = $env:KKT_SOURCE
}

if (-not $Source -and $BaseUrl) {
    $Source = $BaseUrl
}

if (-not $Source) {
    $Source = $Dir
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

function Download-FileCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    $parent = Split-Path -Parent $OutFile
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

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

function Copy-FileCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    $parent = Split-Path -Parent $OutFile
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $sourceFullPath = (Resolve-Path -LiteralPath $Path).Path
    $destinationFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    if ($sourceFullPath -eq $destinationFullPath) {
        return
    }

    Copy-Item -LiteralPath $Path -Destination $OutFile -Force
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

function Read-ManifestJson {
    param([string]$Path)

    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    $text = [string]::Join([Environment]::NewLine, $lines)
    $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($convertFromJson) {
        return $text | ConvertFrom-Json
    }

    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    return $serializer.DeserializeObject($text)
}

function Get-ManifestValue {
    param(
        [object]$Manifest,
        [string]$Name,
        [object]$Default
    )

    if ($null -eq $Manifest) { return $Default }

    if ($Manifest -is [System.Collections.IDictionary]) {
        if ($Manifest.Contains($Name)) { return $Manifest[$Name] }
        return $Default
    }

    $property = $Manifest.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-SourceLayout {
    param(
        [string]$SourceValue,
        [string]$BaseUrlValue,
        [string]$FwUrlValue
    )

    $isHttp = Test-IsHttpSource $SourceValue
    $layout = New-Object PSObject
    Add-Member -InputObject $layout -MemberType NoteProperty -Name IsHttp -Value $isHttp

    if ($isHttp) {
        $sourceRoot = $SourceValue.TrimEnd('/')
        if ($BaseUrlValue) {
            $updater = $BaseUrlValue.TrimEnd('/')
        } elseif ($sourceRoot -match '/Updater/?$') {
            $updater = $sourceRoot
        } else {
            $updater = Join-Url $sourceRoot 'Updater'
        }

        if ($FwUrlValue) {
            $firmware = $FwUrlValue.TrimEnd('/')
        } elseif ($sourceRoot -match '/Updater/?$') {
            $firmware = $sourceRoot -replace '/Updater/?$', '/FW_FR'
        } else {
            $firmware = Join-Url $sourceRoot 'FW_FR'
        }

        Add-Member -InputObject $layout -MemberType NoteProperty -Name Root -Value $sourceRoot
        Add-Member -InputObject $layout -MemberType NoteProperty -Name Updater -Value $updater
        Add-Member -InputObject $layout -MemberType NoteProperty -Name Firmware -Value $firmware
        return $layout
    }

    $resolvedSource = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceValue)
    if (-not (Test-Path -LiteralPath $resolvedSource)) {
        throw "Source path does not exist: $SourceValue"
    }

    $updaterCandidate = Join-Path $resolvedSource 'Updater'
    if (Test-Path -LiteralPath $updaterCandidate) {
        $updater = $updaterCandidate
        $root = $resolvedSource
    } else {
        $updater = $resolvedSource
        $root = Split-Path -Parent $resolvedSource
    }

    $firmwareCandidates = @(
        (Join-Path $root 'FW_FR'),
        (Join-Path $root 'firmware'),
        (Join-Path $resolvedSource 'FW_FR'),
        (Join-Path $resolvedSource 'firmware')
    )

    $firmware = ''
    foreach ($candidate in $firmwareCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $firmware = $candidate
            break
        }
    }

    if (-not $firmware) {
        $firmware = Join-Path $root 'FW_FR'
    }

    Add-Member -InputObject $layout -MemberType NoteProperty -Name Root -Value $root
    Add-Member -InputObject $layout -MemberType NoteProperty -Name Updater -Value $updater
    Add-Member -InputObject $layout -MemberType NoteProperty -Name Firmware -Value $firmware
    return $layout
}

function Receive-SourceFile {
    param(
        [object]$Layout,
        [string]$RelativeName,
        [string]$OutFile,
        [bool]$Required
    )

    try {
        if ($Layout.IsHttp) {
            Download-FileCompat -Uri (Join-Url $Layout.Updater $RelativeName) -OutFile $OutFile
        } else {
            $sourcePath = Join-Path $Layout.Updater $RelativeName
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                throw "File not found: $sourcePath"
            }
            Copy-FileCompat -Path $sourcePath -OutFile $OutFile
        }
        Write-Host "      OK: $RelativeName"
        return 0
    } catch {
        if ($Required) {
            Write-Host "      [ERROR] Failed: $RelativeName - $($_.Exception.Message)"
            return 1
        }

        Write-Host "      [WARN] Failed optional: $RelativeName - $($_.Exception.Message)"
        return 0
    }
}

function Receive-FirmwareFile {
    param(
        [object]$Layout,
        [string]$Name,
        [string]$OutFile,
        [bool]$Required
    )

    try {
        if ($Layout.IsHttp) {
            Download-FileCompat -Uri (Join-Url $Layout.Firmware $Name) -OutFile $OutFile
        } else {
            $sourcePath = Join-Path $Layout.Firmware $Name
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                throw "File not found: $sourcePath"
            }
            Copy-FileCompat -Path $sourcePath -OutFile $OutFile
        }
        Write-Host "      OK: $Name"
        return 0
    } catch {
        if ($Required) {
            Write-Host "      [ERROR] Failed firmware: $Name - $($_.Exception.Message)"
            return 1
        }

        return 0
    }
}

if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
if (-not (Test-Path $FwDir)) { New-Item -ItemType Directory -Path $FwDir -Force | Out-Null }

$defaultRequiredScripts = @(
    'prepare_update.ps1',
    'install_python.ps1',
    'kkt_driver.py',
    'kkt_firmware_update.py',
    'kkt_dump_tables.py',
    'config.bat',
    'install_dfu_driver.bat'
)

$defaultOptionalScripts = @(
    'download.ps1',
    'build_python_package.ps1',
    'kkt_info.py',
    'register_drvfr.bat',
    'run_update.bat',
    'run.bat',
    'setup.bat',
    'probe_com.py',
    'auto_update.bat'
)

$defaultPythonPackages = @('python_ready.zip', 'python_ready_win7.zip')
$driverPackage = 'VCOM+DFU.zip'
$requiredDriverFiles = @(
    'Windows\INF\dfu\lpc-composite89-dfu.inf',
    'Windows\INF\vcom\lpc-ucom-vcom.inf'
)
$firmwareFiles = @()
$firmwarePatterns = @('*.bin')
$optionalFirmware = @('table_after_update.csv')

try {
    $layout = Get-SourceLayout -SourceValue $Source -BaseUrlValue $BaseUrl -FwUrlValue $FwUrl
} catch {
    Write-Host "      [ERROR] Cannot resolve source: $($_.Exception.Message)"
    exit 1
}

Write-Host "      Source: $Source"
Write-Host "      Updater: $($layout.Updater)"
Write-Host "      Firmware: $($layout.Firmware)"

$manifestPath = Join-Path $Dir 'manifest.json'
$manifestStatus = Receive-SourceFile -Layout $layout -RelativeName 'manifest.json' -OutFile $manifestPath -Required $false
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $manifest = Read-ManifestJson -Path $manifestPath
        Write-Host '      OK: manifest.json'
    } catch {
        Write-Host "      [ERROR] Invalid manifest.json: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host '      [WARN] manifest.json not found, using built-in file list.'
}

$requiredScripts = @(Get-ManifestValue -Manifest $manifest -Name 'required_scripts' -Default $defaultRequiredScripts)
$optionalScripts = @(Get-ManifestValue -Manifest $manifest -Name 'optional_scripts' -Default $defaultOptionalScripts)
$pythonPackages = @(Get-ManifestValue -Manifest $manifest -Name 'python_packages' -Default $defaultPythonPackages)
$driverPackageValue = Get-ManifestValue -Manifest $manifest -Name 'driver_package' -Default $driverPackage
$requiredDriverValue = Get-ManifestValue -Manifest $manifest -Name 'required_driver_files' -Default $requiredDriverFiles

$firmwareSection = Get-ManifestValue -Manifest $manifest -Name 'firmware' -Default $null
if ($firmwareSection) {
    $firmwareFiles = @(Get-ManifestValue -Manifest $firmwareSection -Name 'files' -Default $firmwareFiles)
    $firmwarePatterns = @(Get-ManifestValue -Manifest $firmwareSection -Name 'patterns' -Default $firmwarePatterns)
    $optionalFirmware = @(Get-ManifestValue -Manifest $firmwareSection -Name 'optional' -Default $optionalFirmware)
}

$failCount = 0

Write-Host '      Preparing scripts...'
foreach ($file in $requiredScripts) {
    $failCount += Receive-SourceFile -Layout $layout -RelativeName $file -OutFile (Join-Path $Dir $file) -Required $true
}

foreach ($file in $optionalScripts) {
    $failCount += Receive-SourceFile -Layout $layout -RelativeName $file -OutFile (Join-Path $Dir $file) -Required $false
}

Write-Host '      Preparing Python packages...'
foreach ($file in $pythonPackages) {
    $failCount += Receive-SourceFile -Layout $layout -RelativeName $file -OutFile (Join-Path $Dir $file) -Required $false
}

Write-Host '      Preparing VCOM/DFU driver package...'
$dfuZipPath = Join-Path $Dir $driverPackageValue
$driverCopied = $false
try {
    if ((Receive-SourceFile -Layout $layout -RelativeName $driverPackageValue -OutFile $dfuZipPath -Required $true) -eq 0) {
        Expand-ZipCompat -Path $dfuZipPath -DestinationPath $DfuDir
        $driverCopied = $true
    }
} catch {
    Write-Host "      [ERROR] Failed VCOM/DFU package: $($_.Exception.Message)"
    $failCount++
}

if (-not $driverCopied -and -not $layout.IsHttp) {
    $expandedDriverPath = Join-Path $layout.Updater 'VCOM+DFU'
    if (Test-Path -LiteralPath $expandedDriverPath) {
        try {
            if (Test-Path -LiteralPath $DfuDir) {
                Remove-Item -LiteralPath $DfuDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -LiteralPath $expandedDriverPath -Destination $DfuDir -Recurse -Force
            $driverCopied = $true
            Write-Host '      OK: VCOM+DFU directory'
        } catch {
            Write-Host "      [ERROR] Failed VCOM/DFU directory: $($_.Exception.Message)"
            $failCount++
        }
    }
}

foreach ($file in $requiredDriverValue) {
    if (-not (Test-Path -LiteralPath (Join-Path $DfuDir $file))) {
        Write-Host "      [ERROR] Missing required driver file after extraction: $file"
        $failCount++
    }
}

Write-Host '      Preparing firmware...'
$firmwareCopied = 0
if ($firmwareFiles.Count -gt 0) {
    foreach ($file in $firmwareFiles) {
        $outFile = Join-Path $FwDir ([System.IO.Path]::GetFileName($file))
        if ((Receive-FirmwareFile -Layout $layout -Name $file -OutFile $outFile -Required $true) -eq 0) {
            $firmwareCopied++
        } else {
            $failCount++
        }
    }
} elseif ($layout.IsHttp) {
    try {
        $html = Get-UrlContentCompat -Uri ($layout.Firmware.TrimEnd('/') + '/')
        $links = [regex]::Matches($html, 'href=["'']([^"''?#]+\.bin)["'']') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique
        foreach ($link in $links) {
            $name = [System.IO.Path]::GetFileName([System.Uri]::UnescapeDataString($link))
            if (-not $name) { continue }

            if ($link -match '^https?://') {
                $fileUrl = $link
            } elseif ($link.StartsWith('/')) {
                $baseUri = New-Object System.Uri -ArgumentList $layout.Firmware
                $fileUri = New-Object System.Uri -ArgumentList $baseUri, $link
                $fileUrl = $fileUri.AbsoluteUri
            } else {
                $fileUrl = Join-Url $layout.Firmware $link
            }

            try {
                Download-FileCompat -Uri $fileUrl -OutFile (Join-Path $FwDir $name)
                Write-Host "      OK: $name"
                $firmwareCopied++
            } catch {
                Write-Host "      [ERROR] Failed firmware: $name - $($_.Exception.Message)"
                $failCount++
            }
        }
    } catch {
        Write-Host "      [ERROR] Cannot read firmware index: $($_.Exception.Message)"
        $failCount++
    }
} else {
    foreach ($pattern in $firmwarePatterns) {
        $items = Get-ChildItem -Path $layout.Firmware -Filter $pattern -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer }
        foreach ($item in $items) {
            Copy-FileCompat -Path $item.FullName -OutFile (Join-Path $FwDir $item.Name)
            Write-Host "      OK: $($item.Name)"
            $firmwareCopied++
        }
    }
}

foreach ($file in $optionalFirmware) {
    $targetName = [System.IO.Path]::GetFileName($file)
    if (-not $targetName) { continue }
    $null = Receive-FirmwareFile -Layout $layout -Name $file -OutFile (Join-Path $FwDir $targetName) -Required $false
}

if ($firmwareCopied -eq 0) {
    Write-Host '      [ERROR] No firmware *.bin files were prepared.'
    $failCount++
}

if ($failCount -gt 0) {
    Write-Host "      [ERROR] Preparation failed: $failCount problem(s)."
    exit 1
}

Write-Host '      Preparation complete.'
exit 0
