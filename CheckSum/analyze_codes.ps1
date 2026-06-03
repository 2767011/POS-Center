# Разбор двух кодов маркировки
# Структура: 01(GTIN 14) + 21(Serial) + GS + 91(VerKey 4) + GS + 92(CryptoTail)

$code1_raw = "010467000816368521bvSqkCsuoAyR5`u{001D}91EE09`u{001D}92bil1m4L3i+LwU5EWxl4QsCrUD79hXRqrG3jNnnfoDvc="
$code2_raw = "0104640203820010211000000119818`u{001D}91EE08`u{001D}92SSX6lLpW6N1Z7/JiwxRSfExUkYQt545QnXh9zoymZJo="

# Парсинг AI
function Parse-MarkingCode {
    param([string]$Raw)
    
    $parts = $Raw -split [char]0x1D
    
    # Первая часть: 01 + GTIN(14) + 21 + Serial
    $p0 = $parts[0]
    $ai01 = $p0.Substring(0, 2)  # "01"
    $gtin = $p0.Substring(2, 14)
    $ai21 = $p0.Substring(16, 2) # "21"
    $serial = $p0.Substring(18)
    
    # Вторая часть: 91 + VerKey
    $p1 = $parts[1]
    $ai91 = $p1.Substring(0, 2)  # "91"
    $verKey = $p1.Substring(2)
    
    # Третья часть: 92 + CryptoTail
    $p2 = $parts[2]
    $ai92 = $p2.Substring(0, 2)  # "92"
    $cryptoTail = $p2.Substring(2)
    
    return [PSCustomObject]@{
        GTIN       = $gtin
        Serial     = $serial
        VerKey     = $verKey
        CryptoTail = $cryptoTail
        # "Идентификатор" = GTIN + Serial (без AI)
        Identifier = $gtin + $serial
        # Данные для подписи (01+GTIN+21+Serial+GS+91+VerKey)
        DataToSign = "01${gtin}21${serial}" + [char]0x1D + "91${verKey}"
    }
}

$c1 = Parse-MarkingCode $code1_raw
$c2 = Parse-MarkingCode $code2_raw

Write-Host "=== Код 1 ===" -ForegroundColor Cyan
Write-Host "GTIN:       $($c1.GTIN)"
Write-Host "Serial:     $($c1.Serial)"
Write-Host "VerKey:     $($c1.VerKey)"
Write-Host "CryptoTail: $($c1.CryptoTail)"

Write-Host ""
Write-Host "=== Код 2 ===" -ForegroundColor Cyan
Write-Host "GTIN:       $($c2.GTIN)"
Write-Host "Serial:     $($c2.Serial)"
Write-Host "VerKey:     $($c2.VerKey)"
Write-Host "CryptoTail: $($c2.CryptoTail)"

# Проверка контрольной цифры GTIN (Mod10 / GS1)
function Get-GTINCheckDigit {
    param([string]$gtin)
    $digits = $gtin.ToCharArray() | ForEach-Object { [int]::Parse($_) }
    # Для 14-значного GTIN: позиции 1-13 (0-based), check digit = позиция 14 (index 13)
    $sum = 0
    for ($i = 0; $i -lt 13; $i++) {
        $weight = if (($i % 2) -eq 0) { 1 } else { 3 }
        $sum += $digits[$i] * $weight
    }
    $check = (10 - ($sum % 10)) % 10
    return $check
}

Write-Host ""
Write-Host "=== Проверка GTIN Check Digit ===" -ForegroundColor Yellow
$cd1 = Get-GTINCheckDigit $c1.GTIN
$cd2 = Get-GTINCheckDigit $c2.GTIN
Write-Host "GTIN 1: $($c1.GTIN) -> Рассчитанная КЦ: $cd1, Фактическая: $($c1.GTIN[-1])"
Write-Host "GTIN 2: $($c2.GTIN) -> Рассчитанная КЦ: $cd2, Фактическая: $($c2.GTIN[-1])"

# Попробуем разные хеши от разных частей кода
Write-Host ""
Write-Host "=== Хеши от различных частей ===" -ForegroundColor Yellow

$hashAlgos = @("MD5", "SHA1", "SHA256")

foreach ($algo in $hashAlgos) {
    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($algo)
    
    # Хеш от GTIN
    $bytes1 = [System.Text.Encoding]::UTF8.GetBytes($c1.GTIN)
    $bytes2 = [System.Text.Encoding]::UTF8.GetBytes($c2.GTIN)
    $h1 = [BitConverter]::ToString($hasher.ComputeHash($bytes1)) -replace '-'
    $h2 = [BitConverter]::ToString($hasher.ComputeHash($bytes2)) -replace '-'
    Write-Host "$algo(GTIN1): $h1"
    Write-Host "$algo(GTIN2): $h2"
    Write-Host "  Match: $($h1 -eq $h2)"
    
    # Хеш от GTIN+Serial
    $bytes1 = [System.Text.Encoding]::UTF8.GetBytes($c1.Identifier)
    $bytes2 = [System.Text.Encoding]::UTF8.GetBytes($c2.Identifier)
    $h1 = [BitConverter]::ToString($hasher.ComputeHash($bytes1)) -replace '-'
    $h2 = [BitConverter]::ToString($hasher.ComputeHash($bytes2)) -replace '-'
    Write-Host "$algo(GTIN+Ser1): $h1"
    Write-Host "$algo(GTIN+Ser2): $h2"
    Write-Host "  Match: $($h1 -eq $h2)"
    
    Write-Host ""
}

# Попробуем CRC32 от разных частей
Write-Host "=== CRC32 ===" -ForegroundColor Yellow

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
    return $crc -bxor 0xFFFFFFFF
}

# CRC32 от GTIN
$crc1 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($c1.GTIN))
$crc2 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($c2.GTIN))
Write-Host "CRC32(GTIN1): $("{0:X8}" -f $crc1)"
Write-Host "CRC32(GTIN2): $("{0:X8}" -f $crc2)"

# CRC32 от GTIN + Serial
$crc1 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($c1.Identifier))
$crc2 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($c2.Identifier))
Write-Host "CRC32(GTIN+Ser1): $("{0:X8}" -f $crc1)"
Write-Host "CRC32(GTIN+Ser2): $("{0:X8}" -f $crc2)"

# CRC32 от DataToSign
$crc1 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($c1.DataToSign))
$crc2 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($c2.DataToSign))
Write-Host "CRC32(DataToSign1): $("{0:X8}" -f $crc1)"
Write-Host "CRC32(DataToSign2): $("{0:X8}" -f $crc2)"

# Полный код без крипто
$full1 = "01$($c1.GTIN)21$($c1.Serial)"
$full2 = "01$($c2.GTIN)21$($c2.Serial)"
$crc1 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($full1))
$crc2 = Get-CRC32 ([System.Text.Encoding]::UTF8.GetBytes($full2))
Write-Host "CRC32(01+GTIN+21+Ser1): $("{0:X8}" -f $crc1)"
Write-Host "CRC32(01+GTIN+21+Ser2): $("{0:X8}" -f $crc2)"

# Декодируем base64 крипто-хвост
Write-Host ""
Write-Host "=== Крипто-хвост (Base64 decoded) ===" -ForegroundColor Yellow
try {
    $ct1_bytes = [Convert]::FromBase64String($c1.CryptoTail)
    $ct2_bytes = [Convert]::FromBase64String($c2.CryptoTail)
    Write-Host "CryptoTail1 length: $($ct1_bytes.Length) bytes"
    Write-Host "CryptoTail1 hex: $([BitConverter]::ToString($ct1_bytes) -replace '-')"
    Write-Host "CryptoTail2 length: $($ct2_bytes.Length) bytes"
    Write-Host "CryptoTail2 hex: $([BitConverter]::ToString($ct2_bytes) -replace '-')"
} catch {
    Write-Host "Error decoding base64: $_"
}
