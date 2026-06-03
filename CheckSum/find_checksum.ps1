# Поиск алгоритма контрольной суммы ФН для кодов маркировки
# ФН использует CRC16-CCITT (0x1021) для протокола обмена
# Проверяем, какая часть КМ даёт коллизию

# --- Коды маркировки ---
$GS = [char]0x1D

$code1_full = "010467000816368521bvSqkCsuoAyR5${GS}91EE09${GS}92bil1m4L3i+LwU5EWxl4QsCrUD79hXRqrG3jNnnfoDvc="
$code2_full = "0104640203820010211000000119818${GS}91EE08${GS}92SSX6lLpW6N1Z7/JiwxRSfExUkYQt545QnXh9zoymZJo="

# Разбираем
$gtin1 = "04670008163685"; $serial1 = "bvSqkCsuoAyR5"; $vk1 = "EE09"; $ct1 = "bil1m4L3i+LwU5EWxl4QsCrUD79hXRqrG3jNnnfoDvc="
$gtin2 = "04640203820010"; $serial2 = "1000000119818"; $vk2 = "EE08"; $ct2 = "SSX6lLpW6N1Z7/JiwxRSfExUkYQt545QnXh9zoymZJo="

# --- Алгоритмы CRC16 ---

function Get-CRC16-CCITT {
    param([byte[]]$Data, [uint16]$Init = 0xFFFF)
    $poly = [uint16]0x1021
    $crc = $Init
    foreach ($b in $Data) {
        $crc = $crc -bxor ([uint16]$b -shl 8)
        for ($i = 0; $i -lt 8; $i++) {
            if ($crc -band 0x8000) {
                $crc = (($crc -shl 1) -band 0xFFFF) -bxor $poly
            } else {
                $crc = ($crc -shl 1) -band 0xFFFF
            }
        }
    }
    return $crc
}

function Get-CRC16-CCITT-False {
    param([byte[]]$Data)
    return Get-CRC16-CCITT $Data 0xFFFF
}

function Get-CRC16-XMODEM {
    param([byte[]]$Data)
    return Get-CRC16-CCITT $Data 0x0000
}

function Get-CRC16-AUG-CCITT {
    param([byte[]]$Data)
    return Get-CRC16-CCITT $Data 0x1D0F
}

function Get-CRC16-Reflected {
    # CRC16/KERMIT / CRC-CCITT reflected
    param([byte[]]$Data)
    $poly = [uint16]0x8408  # reflected 0x1021
    $crc = [uint16]0x0000
    foreach ($b in $Data) {
        $crc = $crc -bxor [uint16]$b
        for ($i = 0; $i -lt 8; $i++) {
            if ($crc -band 1) {
                $crc = (($crc -shr 1) -band 0x7FFF) -bxor $poly
            } else {
                $crc = ($crc -shr 1) -band 0x7FFF
            }
        }
    }
    return $crc
}

function Get-CRC16-IBM {
    param([byte[]]$Data)
    $poly = [uint16]0xA001  # reflected 0x8005
    $crc = [uint16]0x0000
    foreach ($b in $Data) {
        $crc = $crc -bxor [uint16]$b
        for ($i = 0; $i -lt 8; $i++) {
            if ($crc -band 1) {
                $crc = (($crc -shr 1) -band 0x7FFF) -bxor $poly
            } else {
                $crc = ($crc -shr 1) -band 0x7FFF
            }
        }
    }
    return $crc
}

function Get-CRC16-DNP {
    param([byte[]]$Data)
    $poly = [uint16]0xA6BC
    $crc = [uint16]0x0000
    foreach ($b in $Data) {
        $crc = $crc -bxor [uint16]$b
        for ($i = 0; $i -lt 8; $i++) {
            if ($crc -band 1) {
                $crc = (($crc -shr 1) -band 0x7FFF) -bxor $poly
            } else {
                $crc = ($crc -shr 1) -band 0x7FFF
            }
        }
    }
    return ($crc -bxor 0xFFFF)
}

function Get-XOR16 {
    param([byte[]]$Data)
    $xor = [uint16]0
    for ($i = 0; $i -lt $Data.Length; $i += 2) {
        $w = [uint16]$Data[$i]
        if (($i + 1) -lt $Data.Length) {
            $w = ($w -shl 8) -bor [uint16]$Data[$i + 1]
        }
        $xor = $xor -bxor $w
    }
    return $xor
}

function Get-XOR8 {
    param([byte[]]$Data)
    $xor = [byte]0
    foreach ($b in $Data) { $xor = $xor -bxor $b }
    return $xor
}

function Get-Sum16 {
    param([byte[]]$Data)
    $sum = [uint32]0
    foreach ($b in $Data) { $sum += $b }
    return ($sum -band 0xFFFF)
}

function Get-CRC32 {
    param([byte[]]$Data)
    $crc = [uint32]0xFFFFFFFF
    $poly = [uint32]0xEDB88320
    foreach ($b in $Data) {
        $crc = $crc -bxor $b
        for ($i = 0; $i -lt 8; $i++) {
            if ($crc -band 1) {
                $crc = ($crc -shr 1) -bxor $poly
            } else {
                $crc = $crc -shr 1
            }
        }
    }
    return ($crc -bxor 0xFFFFFFFF)
}

# --- Варианты данных для хеширования ---
$variants = [ordered]@{
    "full_code"           = @($code1_full, $code2_full)
    "gtin"                = @($gtin1, $gtin2)
    "serial"              = @($serial1, $serial2)
    "gtin+serial"         = @("${gtin1}${serial1}", "${gtin2}${serial2}")
    "01gtin21serial"      = @("01${gtin1}21${serial1}", "01${gtin2}21${serial2}")
    "01gtin21serial_GS"   = @("01${gtin1}21${serial1}${GS}", "01${gtin2}21${serial2}${GS}")
    "gtin+serial+vk"      = @("${gtin1}${serial1}${vk1}", "${gtin2}${serial2}${vk2}")
    "01gtin21ser_GS_91vk" = @("01${gtin1}21${serial1}${GS}91${vk1}", "01${gtin2}21${serial2}${GS}91${vk2}")
    "vk"                  = @($vk1, $vk2)
    "crypto_tail"         = @($ct1, $ct2)
    "vk+crypto"           = @("${vk1}${ct1}", "${vk2}${ct2}")
    "91vk_GS_92ct"        = @("91${vk1}${GS}92${ct1}", "91${vk2}${GS}92${ct2}")
    "no_crypto"           = @("01${gtin1}21${serial1}${GS}91${vk1}", "01${gtin2}21${serial2}${GS}91${vk2}")
    "serial+vk"           = @("${serial1}${vk1}", "${serial2}${vk2}")
}

# --- Алгоритмы ---
$algorithms = @(
    @{ Name = "CRC16-CCITT-False"; Func = { param($d) Get-CRC16-CCITT-False $d } }
    @{ Name = "CRC16-XMODEM";     Func = { param($d) Get-CRC16-XMODEM $d } }
    @{ Name = "CRC16-AUG-CCITT";  Func = { param($d) Get-CRC16-AUG-CCITT $d } }
    @{ Name = "CRC16-Kermit";     Func = { param($d) Get-CRC16-Reflected $d } }
    @{ Name = "CRC16-IBM";        Func = { param($d) Get-CRC16-IBM $d } }
    @{ Name = "CRC16-DNP";        Func = { param($d) Get-CRC16-DNP $d } }
    @{ Name = "XOR16";            Func = { param($d) Get-XOR16 $d } }
    @{ Name = "XOR8";             Func = { param($d) Get-XOR8 $d } }
    @{ Name = "Sum16";            Func = { param($d) Get-Sum16 $d } }
    @{ Name = "CRC32";            Func = { param($d) Get-CRC32 $d } }
)

$encodings = @(
    @{ Name = "UTF8";    Enc = [System.Text.Encoding]::UTF8 }
    @{ Name = "ASCII";   Enc = [System.Text.Encoding]::ASCII }
    @{ Name = "CP1251";  Enc = [System.Text.Encoding]::GetEncoding(1251) }
    @{ Name = "CP866";   Enc = [System.Text.Encoding]::GetEncoding(866) }
)

Write-Host "======== ПОИСК КОЛЛИЗИИ ========" -ForegroundColor Cyan
Write-Host ""

$found = @()

foreach ($enc in $encodings) {
    foreach ($algo in $algorithms) {
        foreach ($vName in $variants.Keys) {
            $pair = $variants[$vName]
            $bytes1 = $enc.Enc.GetBytes($pair[0])
            $bytes2 = $enc.Enc.GetBytes($pair[1])
            
            $h1 = & $algo.Func $bytes1
            $h2 = & $algo.Func $bytes2
            
            if ($h1 -eq $h2) {
                $match = "$($enc.Name) | $($algo.Name) | $vName => $("{0:X}" -f $h1)"
                $found += $match
                Write-Host "[MATCH] $match" -ForegroundColor Green
            }
        }
    }
}

Write-Host ""
if ($found.Count -eq 0) {
    Write-Host "Коллизий не найдено среди стандартных алгоритмов." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Попробуем нестандартные варианты..." -ForegroundColor Cyan

    # Попробуем разные init values для CRC16-CCITT
    Write-Host ""
    Write-Host "=== CRC16-CCITT с разными init values (данные: 01+GTIN+21+Serial) ===" -ForegroundColor Yellow
    $d1 = [System.Text.Encoding]::UTF8.GetBytes("01${gtin1}21${serial1}")
    $d2 = [System.Text.Encoding]::UTF8.GetBytes("01${gtin2}21${serial2}")
    
    for ($init = 0; $init -le 0xFFFF; $init++) {
        $h1 = Get-CRC16-CCITT $d1 ([uint16]$init)
        $h2 = Get-CRC16-CCITT $d2 ([uint16]$init)
        if ($h1 -eq $h2) {
            Write-Host "[MATCH] CRC16-CCITT init=0x$("{0:X4}" -f $init) => 0x$("{0:X4}" -f $h1)" -ForegroundColor Green
        }
    }
    
    # То же для полного кода
    Write-Host ""
    Write-Host "=== CRC16-CCITT с разными init values (данные: full code) ===" -ForegroundColor Yellow
    $d1 = [System.Text.Encoding]::UTF8.GetBytes($code1_full)
    $d2 = [System.Text.Encoding]::UTF8.GetBytes($code2_full)
    
    for ($init = 0; $init -le 0xFFFF; $init++) {
        $h1 = Get-CRC16-CCITT $d1 ([uint16]$init)
        $h2 = Get-CRC16-CCITT $d2 ([uint16]$init)
        if ($h1 -eq $h2) {
            Write-Host "[MATCH] CRC16-CCITT init=0x$("{0:X4}" -f $init) full => 0x$("{0:X4}" -f $h1)" -ForegroundColor Green
        }
    }

    # Только GTIN+Serial (без AI)
    Write-Host ""
    Write-Host "=== CRC16-CCITT с разными init values (данные: GTIN+Serial) ===" -ForegroundColor Yellow
    $d1 = [System.Text.Encoding]::UTF8.GetBytes("${gtin1}${serial1}")
    $d2 = [System.Text.Encoding]::UTF8.GetBytes("${gtin2}${serial2}")
    
    for ($init = 0; $init -le 0xFFFF; $init++) {
        $h1 = Get-CRC16-CCITT $d1 ([uint16]$init)
        $h2 = Get-CRC16-CCITT $d2 ([uint16]$init)
        if ($h1 -eq $h2) {
            Write-Host "[MATCH] CRC16-CCITT init=0x$("{0:X4}" -f $init) gtin+ser => 0x$("{0:X4}" -f $h1)" -ForegroundColor Green
        }
    }

    # no_crypto
    Write-Host ""
    Write-Host "=== CRC16-CCITT с разными init values (данные: no crypto = 01+GTIN+21+Serial+GS+91+VK) ===" -ForegroundColor Yellow
    $d1 = [System.Text.Encoding]::UTF8.GetBytes("01${gtin1}21${serial1}${GS}91${vk1}")
    $d2 = [System.Text.Encoding]::UTF8.GetBytes("01${gtin2}21${serial2}${GS}91${vk2}")
    
    for ($init = 0; $init -le 0xFFFF; $init++) {
        $h1 = Get-CRC16-CCITT $d1 ([uint16]$init)
        $h2 = Get-CRC16-CCITT $d2 ([uint16]$init)
        if ($h1 -eq $h2) {
            Write-Host "[MATCH] CRC16-CCITT init=0x$("{0:X4}" -f $init) no_crypto => 0x$("{0:X4}" -f $h1)" -ForegroundColor Green
        }
    }

} else {
    Write-Host "Найдено $($found.Count) коллизий!" -ForegroundColor Green
}
