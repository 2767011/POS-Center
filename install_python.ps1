# Скрипт для автоматической установки Portable Python и зависимостей
$ErrorActionPreference = "Stop"

$pyVersion = "3.11.5"
$pyUrl = "https://www.python.org/ftp/python/$pyVersion/python-$pyVersion-embed-amd64.zip"
$zipPath = "python.zip"
$extractPath = "python"

Write-Host "--- Portable Python Installer ---"

# 1. Проверка наличия
if (Test-Path "$extractPath\python.exe") {
    Write-Host "Python already installed in $extractPath."
} else {
    # 2. Скачивание
    Write-Host "Downloading Python $pyVersion..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $pyUrl -OutFile $zipPath

    # 3. Распаковка
    Write-Host "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Remove-Item $zipPath
}

# 4. Настройка ._pth для поддержки pip (раскомментировать import site)
$pthFile = Get-ChildItem "$extractPath\*._pth" | Select-Object -First 1
if ($pthFile) {
    Write-Host "Patching $($pthFile.Name) for pip support..."
    $content = Get-Content $pthFile.FullName
    $newContent = $content -replace "#import site", "import site"
    Set-Content $pthFile.FullName $newContent
}

# 5. Установка pip
if (-not (Test-Path "$extractPath\Scripts\pip.exe")) {
    Write-Host "Downloading get-pip.py..."
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "get-pip.py"
    
    Write-Host "Installing pip..."
    & ".\$extractPath\python.exe" get-pip.py --no-warn-script-location
    Remove-Item "get-pip.py"
}

# 6. Установка зависимостей (pywin32)
Write-Host "Installing pywin32..."
& ".\$extractPath\python.exe" -m pip install pywin32 --no-warn-script-location

Write-Host "Done! Python is ready in ./$extractPath"
