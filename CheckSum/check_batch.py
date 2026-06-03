"""Поиск коллизий CRC16-CCITT среди списка кодов маркировки (base64)."""
import base64
from collections import defaultdict

def crc16_ccitt(data: bytes, init=0xFFFF):
    crc = init
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) & 0xFFFF) ^ 0x1021
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

# Base64-кодированные КМ
codes_b64 = """MDEwNDYwMjI5MDAwMTI2MDIxNTQ2TFQ2HTkzMTBvZw==
MDEwNDYwMjI5MDAwMTI2MDIxNTQ3RHlGHTkzL2J3dg==
MDEwNDYwMjI5MDAwMTI2MDIxNTQ3SCxGHTkzN25YVQ==
MDEwNDYwMjI5MDAwMTI2MDIxNTQ4WjRnHTkzUk00UA==
MDEwNDYwMjI5MDAwMTI2MDIxNTQ5Ok5KHTkzZWN3TA==
MDEwNDYwMjI5MDAwMTI2MDIxNTRCVmJTHTkzdmZvTg==
MDEwNDYwMjI5MDAwMTI2MDIxNTRCV0IzHTkzY0o5bw==
MDEwNDYwMjI5MDAwMTI2MDIxNTRDK1NqHTkzSm5QSA==
MDEwNDYwMjI5MDAwMTI2MDIxNUxTY2hsHTkzU3NxUg==
MDEwNDYwMjI5MDAwMTI2MDIxNUxTY1JnHTkzVUtOVA==
MDEwNDYwMjI5MDAwMTI2MDIxNU0xaHcrHTkzQVJ4eg==
MDEwNDY0MDEyMjU0MTE4ODIxNSxjcjhsdB05M1NobEU=
MDEwNDY0MDEyMjU0MTE4ODIxNSZQVUtfSx05M09oTEw=
MDEwNDY0MDEyMjU0MTE4ODIxNTJpRHZ1ax05M3dHNzg=
MDEwNDY0MDEyMjU0MTE4ODIxNTRQZDkwTB05M2pLZXU=
MDEwNDY0MDEyMjU0MTE4ODIxNTYsYVFKMB05M0lXUis=
MDEwNDY0MDEyMjU0MTE4ODIxNTdYVCpkcx05M2c2bHA=
MDEwNDY0MDEyMjU0MTE4ODIxNWM+eEJlVR05M1Nacm4=
MDEwNDY0MDEyMjU0MTE4ODIxNUQsRkw2Kx05M0lnK0Y=
MDEwNDY0MDEyMjU0MTE4ODIxNUU4MkZOTB05M3JTOU4=
MDEwNDY0MDEyMjU0MTE4ODIxNUY3eD9ERB05M2xBUnY=
MDEwNDY0MDEyMjU0MTE4ODIxNUpmKE91Tx05M1c4Qk4=
MDEwNDY0MDEyMjU0MTE4ODIxNWxBLENzLx05M3ByTHc=
MDEwNDY0MDEyMjU0MTE4ODIxNW1EZT5jTR05M1c0SzI=
MDEwNDY0MDEyMjU0MTE4ODIxNU5USlBIKR05M2hiTXE=
MDEwNDY0MDEyMjU0MTE4ODIxNU9nSk9TOx05M1dyb3c=
MDEwNDY0MDEyMjU0MTE4ODIxNVBMZk1kJR05M0JDRjE=
MDEwNDY0MDEyMjU0MTE4ODIxNXFKd09lKx05M01NY1Y=
MDEwNDY0MDEyMjU0MTE4ODIxNVIscztvTR05M29ZNys=
MDEwNDY0MDEyMjU0MTE4ODIxNXIpWXRkOx05Mzd2THU=
MDEwNDY0MDEyMjU0MTE4ODIxNXJVTnFUSh05M1lMOGY=
MDEwNDY0MDEyMjU0MTE4ODIxNVZoIm4/cx05M2lLSlk=
MDEwNDY0MDEyMjU0MTE4ODIxNVZpcVMmXx05M2U5MXQ=
MDEwNDY0MDEyMjU0MTE4ODIxNXdOMiZiLh05M0tLMVM=
MDEwNDY0MDEyMjU0MTE4ODIxNVhKd25iRh05Mzgralk=
MDQ2MDYyMDMwOTY1NDE/UjM1dlppQURJOGFGdUY=
MDQ2MDYyMDMwOTY1NDE+V0NxOXZlQURJOHBTVFo=
MDQ2MDYyMDMwOTY1NDFDLUlTOT43QURJOE1EbmM=
MDQ2MDYyMDMwOTY1NDE5NVFpVWxJQURJOEg4VkM=
MDQ2MDYyMDMwOTY1NDFjVGN5LSI9QURJODJ2NnY=
MDQ2MDYyMDMwOTY1NDFFTFo0d1dKQURJOEFaTHc=
MDQ2MDYyMDMwOTY1NDFtQy5IOTpXQURJOERlR2g=
MDQ2MDYyMDMwOTY1NDF0MVY/Q0lCQURJOGtmSnE=
MDQ2MDYyMDMwOTY1NDF2M1V5UldGQURJOGZVblA=
MDQ2MDYyMDMwOTY1NDFYWjBwPGFvQURJOGp2SEc=""".strip().split("\n")

# Декодируем
codes_raw = []
for b64 in codes_b64:
    raw = base64.b64decode(b64.strip())
    codes_raw.append(raw)

# Вывод декодированных кодов
print("=" * 70)
print(f"Всего кодов: {len(codes_raw)}")
print("=" * 70)

for i, raw in enumerate(codes_raw):
    # Заменяем GS на <GS> для отображения
    display = raw.decode("ascii", errors="replace").replace("\x1d", "<GS>")
    print(f"  [{i+1:2d}] {display}")

# Вычисляем CRC16 и ищем коллизии
print()
print("=" * 70)
print("CRC16-CCITT (init=0xFFFF)")
print("=" * 70)

crc_map = defaultdict(list)

for i, raw in enumerate(codes_raw):
    crc = crc16_ccitt(raw, 0xFFFF)
    display = raw.decode("ascii", errors="replace").replace("\x1d", "<GS>")
    crc_map[crc].append((i + 1, display))

# Показать коллизии
collisions = {k: v for k, v in crc_map.items() if len(v) > 1}

if collisions:
    print(f"\n!!! НАЙДЕНО {len(collisions)} КОЛЛИЗИЙ !!!\n")
    for crc_val, items in sorted(collisions.items()):
        print(f"  CRC=0x{crc_val:04X} ({len(items)} кодов):")
        for idx, display in items:
            print(f"    [{idx:2d}] {display}")
        print()
else:
    print("\nКоллизий НЕТ (init=0xFFFF)")

# Проверим с init=0x0000
print("=" * 70)
print("CRC16-CCITT (init=0x0000)")
print("=" * 70)

crc_map0 = defaultdict(list)
for i, raw in enumerate(codes_raw):
    crc = crc16_ccitt(raw, 0x0000)
    crc_map0[crc].append((i + 1, raw.decode("ascii", errors="replace").replace("\x1d", "<GS>")))

collisions0 = {k: v for k, v in crc_map0.items() if len(v) > 1}
if collisions0:
    print(f"\n!!! НАЙДЕНО {len(collisions0)} КОЛЛИЗИЙ !!!\n")
    for crc_val, items in sorted(collisions0.items()):
        print(f"  CRC=0x{crc_val:04X} ({len(items)} кодов):")
        for idx, display in items:
            print(f"    [{idx:2d}] {display}")
        print()
else:
    print("\nКоллизий НЕТ (init=0x0000)")

# Сводка
print("=" * 70)
print("СВОДКА CRC16 значений:")
print("=" * 70)
for i, raw in enumerate(codes_raw):
    crc_ffff = crc16_ccitt(raw, 0xFFFF)
    crc_0000 = crc16_ccitt(raw, 0x0000)
    display = raw.decode("ascii", errors="replace").replace("\x1d", "<GS>")
    # Показываем только GTIN и Serial для компактности
    parts = raw.split(b'\x1d')
    gtin_ser = parts[0].decode("ascii", errors="replace") if parts else "?"
    flag = " <-- КОЛЛИЗИЯ" if any(crc_ffff == crc16_ccitt(codes_raw[j], 0xFFFF) for j in range(len(codes_raw)) if j != i) else ""
    print(f"  [{i+1:2d}] 0x{crc_ffff:04X}  {gtin_ser}{flag}")
