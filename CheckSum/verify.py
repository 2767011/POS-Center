"""Проверка: CRC16-CCITT (poly=0x1021) от полного кода маркировки."""

GS = chr(0x1D)

gtin1, serial1, vk1, ct1 = "04670008163685", "bvSqkCsuoAyR5", "EE09", "bil1m4L3i+LwU5EWxl4QsCrUD79hXRqrG3jNnnfoDvc="
gtin2, serial2, vk2, ct2 = "04640203820010", "1000000119818", "EE08", "SSX6lLpW6N1Z7/JiwxRSfExUkYQt545QnXh9zoymZJo="

code1 = f"01{gtin1}21{serial1}{GS}91{vk1}{GS}92{ct1}"
code2 = f"01{gtin2}21{serial2}{GS}91{vk2}{GS}92{ct2}"


def crc16_ccitt(data: bytes, init=0xFFFF):
    """CRC16-CCITT (poly=0x1021, MSB-first)"""
    crc = init
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) & 0xFFFF) ^ 0x1021
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


b1 = code1.encode("utf-8")
b2 = code2.encode("utf-8")

# Проверка с разными init
for init in [0x0000, 0xFFFF, 0x1D0F]:
    h1 = crc16_ccitt(b1, init)
    h2 = crc16_ccitt(b2, init)
    match = "[+] КОЛЛИЗИЯ" if h1 == h2 else "[-] разные"
    print(f"init=0x{init:04X}:  code1=0x{h1:04X}  code2=0x{h2:04X}  {match}")

print()
print(f"Код 1: {code1[:40]}...")
print(f"Код 2: {code2[:40]}...")
print()

# Проверка без крипто-хвоста — коллизии НЕТ
no_crypto1 = f"01{gtin1}21{serial1}{GS}91{vk1}"
no_crypto2 = f"01{gtin2}21{serial2}{GS}91{vk2}"
h1 = crc16_ccitt(no_crypto1.encode(), 0xFFFF)
h2 = crc16_ccitt(no_crypto2.encode(), 0xFFFF)
print(f"Без крипто-хвоста: code1=0x{h1:04X}  code2=0x{h2:04X}  {'КОЛЛИЗИЯ' if h1==h2 else 'разные (ожидаемо)'}")

# Только GTIN+Serial — коллизии НЕТ
id1 = f"01{gtin1}21{serial1}"
id2 = f"01{gtin2}21{serial2}"
h1 = crc16_ccitt(id1.encode(), 0xFFFF)
h2 = crc16_ccitt(id2.encode(), 0xFFFF)
print(f"Только GTIN+Serial: code1=0x{h1:04X}  code2=0x{h2:04X}  {'КОЛЛИЗИЯ' if h1==h2 else 'разные (ожидаемо)'}")

print()
print("=" * 60)
print("ВЫВОД: ФН использует CRC16-CCITT (poly=0x1021) от ПОЛНОГО")
print("кода маркировки для хеширования. Коллизия происходит из-за")
print("того, что CRC16 имеет только 65536 возможных значений.")
print("При миллионах уникальных КМ коллизии неизбежны.")
print("=" * 60)
