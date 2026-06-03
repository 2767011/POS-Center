#!/usr/bin/env python3
"""Поиск алгоритма контрольной суммы ФН для кодов маркировки."""

import struct
import hashlib
import zlib

GS = chr(0x1D)

# Коды маркировки
gtin1, serial1, vk1, ct1 = "04670008163685", "bvSqkCsuoAyR5", "EE09", "bil1m4L3i+LwU5EWxl4QsCrUD79hXRqrG3jNnnfoDvc="
gtin2, serial2, vk2, ct2 = "04640203820010", "1000000119818", "EE08", "SSX6lLpW6N1Z7/JiwxRSfExUkYQt545QnXh9zoymZJo="

code1_full = f"01{gtin1}21{serial1}{GS}91{vk1}{GS}92{ct1}"
code2_full = f"01{gtin2}21{serial2}{GS}91{vk2}{GS}92{ct2}"


# ========== CRC алгоритмы ==========

def crc16_ccitt(data: bytes, init=0xFFFF, poly=0x1021):
    crc = init
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) & 0xFFFF) ^ poly
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

def crc16_ccitt_reflected(data: bytes, init=0x0000, poly=0x8408):
    """CRC16/KERMIT - reflected CRC-CCITT"""
    crc = init
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc >>= 1
    return crc

def crc16_ibm(data: bytes, init=0x0000, poly=0xA001):
    crc = init
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc >>= 1
    return crc

def crc16_modbus(data: bytes):
    return crc16_ibm(data, init=0xFFFF)

def crc16_usb(data: bytes):
    return crc16_ibm(data, init=0xFFFF) ^ 0xFFFF

def crc32(data: bytes):
    return zlib.crc32(data) & 0xFFFFFFFF

def xor8(data: bytes):
    r = 0
    for b in data:
        r ^= b
    return r

def xor16_be(data: bytes):
    r = 0
    for i in range(0, len(data), 2):
        if i + 1 < len(data):
            w = (data[i] << 8) | data[i+1]
        else:
            w = data[i] << 8
        r ^= w
    return r

def xor16_le(data: bytes):
    r = 0
    for i in range(0, len(data), 2):
        if i + 1 < len(data):
            w = data[i] | (data[i+1] << 8)
        else:
            w = data[i]
        r ^= w
    return r

def sum8(data: bytes):
    return sum(data) & 0xFF

def sum16(data: bytes):
    return sum(data) & 0xFFFF

def sum32(data: bytes):
    return sum(data) & 0xFFFFFFFF

def fletcher16(data: bytes):
    s1 = 0
    s2 = 0
    for b in data:
        s1 = (s1 + b) % 255
        s2 = (s2 + s1) % 255
    return (s2 << 8) | s1

def adler32(data: bytes):
    return zlib.adler32(data) & 0xFFFFFFFF

def md5_16(data: bytes):
    """First 2 bytes of MD5"""
    return int.from_bytes(hashlib.md5(data).digest()[:2], 'big')

def sha1_16(data: bytes):
    """First 2 bytes of SHA1"""
    return int.from_bytes(hashlib.sha1(data).digest()[:2], 'big')

def djb2(data: bytes):
    h = 5381
    for b in data:
        h = ((h * 33) + b) & 0xFFFFFFFF
    return h

def djb2_16(data: bytes):
    return djb2(data) & 0xFFFF

def fnv1a_32(data: bytes):
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h

def fnv1a_16(data: bytes):
    h = fnv1a_32(data)
    return ((h >> 16) ^ h) & 0xFFFF

def sdbm(data: bytes):
    h = 0
    for b in data:
        h = b + (h << 6) + (h << 16) - h
        h &= 0xFFFFFFFF
    return h

def sdbm_16(data: bytes):
    return sdbm(data) & 0xFFFF


# ========== Варианты данных ==========
variants = {
    "full_code":           (code1_full, code2_full),
    "gtin":                (gtin1, gtin2),
    "serial":              (serial1, serial2),
    "gtin+serial":         (f"{gtin1}{serial1}", f"{gtin2}{serial2}"),
    "01gtin21serial":      (f"01{gtin1}21{serial1}", f"01{gtin2}21{serial2}"),
    "01gtin21serial_GS":   (f"01{gtin1}21{serial1}{GS}", f"01{gtin2}21{serial2}{GS}"),
    "gtin+serial+vk":      (f"{gtin1}{serial1}{vk1}", f"{gtin2}{serial2}{vk2}"),
    "01gtin21ser_GS91vk":  (f"01{gtin1}21{serial1}{GS}91{vk1}", f"01{gtin2}21{serial2}{GS}91{vk2}"),
    "vk":                  (vk1, vk2),
    "crypto_tail":         (ct1, ct2),
    "vk+crypto":           (f"{vk1}{ct1}", f"{vk2}{ct2}"),
    "91vk_GS_92ct":        (f"91{vk1}{GS}92{ct1}", f"91{vk2}{GS}92{ct2}"),
    "no_crypto":           (f"01{gtin1}21{serial1}{GS}91{vk1}", f"01{gtin2}21{serial2}{GS}91{vk2}"),
    "serial+vk":           (f"{serial1}{vk1}", f"{serial2}{vk2}"),
    # Без AI, только данные
    "gtin_only_digits":    (gtin1, gtin2),
    # Первые N символов
    "first_6_gtin":        (gtin1[:6], gtin2[:6]),
    "first_8_gtin":        (gtin1[:8], gtin2[:8]),
    # Только серийный номер
    "21serial":            (f"21{serial1}", f"21{serial2}"),
    "21serial_GS":         (f"21{serial1}{GS}", f"21{serial2}{GS}"),
}

# ========== Алгоритмы ==========
algorithms = {
    "CRC16-CCITT(0xFFFF)":  lambda d: crc16_ccitt(d, 0xFFFF),
    "CRC16-CCITT(0x0000)":  lambda d: crc16_ccitt(d, 0x0000),
    "CRC16-CCITT(0x1D0F)":  lambda d: crc16_ccitt(d, 0x1D0F),
    "CRC16-Kermit":         lambda d: crc16_ccitt_reflected(d),
    "CRC16-IBM":            lambda d: crc16_ibm(d),
    "CRC16-Modbus":         lambda d: crc16_modbus(d),
    "CRC16-USB":            lambda d: crc16_usb(d),
    "CRC32":                lambda d: crc32(d),
    "XOR8":                 lambda d: xor8(d),
    "XOR16-BE":             lambda d: xor16_be(d),
    "XOR16-LE":             lambda d: xor16_le(d),
    "Sum8":                 lambda d: sum8(d),
    "Sum16":                lambda d: sum16(d),
    "Sum32":                lambda d: sum32(d),
    "Fletcher16":           lambda d: fletcher16(d),
    "Adler32":              lambda d: adler32(d),
    "MD5-16":               lambda d: md5_16(d),
    "SHA1-16":              lambda d: sha1_16(d),
    "DJB2":                 lambda d: djb2(d),
    "DJB2-16":              lambda d: djb2_16(d),
    "FNV1a-32":             lambda d: fnv1a_32(d),
    "FNV1a-16":             lambda d: fnv1a_16(d),
    "SDBM":                 lambda d: sdbm(d),
    "SDBM-16":              lambda d: sdbm_16(d),
}

encodings = {
    "UTF-8": "utf-8",
    "ASCII": "ascii",
    "CP1251": "cp1251",
}

print("=" * 60)
print("ПОИСК КОЛЛИЗИИ - стандартные алгоритмы")
print("=" * 60)

found = []

for enc_name, enc in encodings.items():
    for algo_name, algo_func in algorithms.items():
        for var_name, (s1, s2) in variants.items():
            try:
                b1 = s1.encode(enc)
                b2 = s2.encode(enc)
            except (UnicodeEncodeError, UnicodeDecodeError):
                continue
            
            h1 = algo_func(b1)
            h2 = algo_func(b2)
            
            if h1 == h2:
                msg = f"{enc_name} | {algo_name} | {var_name} => 0x{h1:X}"
                found.append(msg)
                print(f"  [MATCH] {msg}")

print()
if found:
    print(f"Найдено {len(found)} совпадений!")
else:
    print("Совпадений со стандартными алгоритмами не найдено.")

# ========== Перебор init для CRC16-CCITT ==========
print()
print("=" * 60)
print("ПЕРЕБОР init value для CRC16-CCITT (poly=0x1021)")
print("=" * 60)

test_data_sets = {
    "full_code":      (code1_full.encode("utf-8"), code2_full.encode("utf-8")),
    "01gtin21serial": (f"01{gtin1}21{serial1}".encode("utf-8"), f"01{gtin2}21{serial2}".encode("utf-8")),
    "gtin+serial":    (f"{gtin1}{serial1}".encode("utf-8"), f"{gtin2}{serial2}".encode("utf-8")),
    "no_crypto":      (f"01{gtin1}21{serial1}{GS}91{vk1}".encode("utf-8"), f"01{gtin2}21{serial2}{GS}91{vk2}".encode("utf-8")),
    "serial":         (serial1.encode("utf-8"), serial2.encode("utf-8")),
    "21serial":       (f"21{serial1}".encode("utf-8"), f"21{serial2}".encode("utf-8")),
}

for ds_name, (d1, d2) in test_data_sets.items():
    matches = []
    for init in range(0x10000):
        h1 = crc16_ccitt(d1, init)
        h2 = crc16_ccitt(d2, init)
        if h1 == h2:
            matches.append((init, h1))
    if matches:
        print(f"  {ds_name}: {len(matches)} коллизий")
        for init, val in matches[:5]:
            print(f"    init=0x{init:04X} => 0x{val:04X}")
        if len(matches) > 5:
            print(f"    ... и ещё {len(matches) - 5}")
    else:
        print(f"  {ds_name}: нет коллизий")

# ========== Перебор poly для CRC16 ==========
print()
print("=" * 60)
print("ПЕРЕБОР poly для CRC16 (init=0xFFFF и init=0x0000)")
print("=" * 60)

# Используем full_code для перебора
d1 = code1_full.encode("utf-8")
d2 = code2_full.encode("utf-8")

for init_val in [0xFFFF, 0x0000]:
    match_polys = []
    for poly in range(1, 0x10000):
        h1 = crc16_ccitt(d1, init_val, poly)
        h2 = crc16_ccitt(d2, init_val, poly)
        if h1 == h2:
            match_polys.append((poly, h1))
    if match_polys:
        print(f"  init=0x{init_val:04X}: {len(match_polys)} полиномов дают коллизию на full_code")
        for p, v in match_polys[:10]:
            print(f"    poly=0x{p:04X} => 0x{v:04X}")
    else:
        print(f"  init=0x{init_val:04X}: нет")

# Reflected CRC16 перебор
print()
print("=" * 60)
print("ПЕРЕБОР init для reflected CRC16 (poly=0x8408)")
print("=" * 60)

for ds_name, (d1, d2) in test_data_sets.items():
    matches = []
    for init in range(0x10000):
        h1 = crc16_ccitt_reflected(d1, init)
        h2 = crc16_ccitt_reflected(d2, init)
        if h1 == h2:
            matches.append((init, h1))
    if matches:
        print(f"  {ds_name}: {len(matches)} коллизий")
        for init, val in matches[:5]:
            print(f"    init=0x{init:04X} => 0x{val:04X}")
        if len(matches) > 5:
            print(f"    ... и ещё {len(matches) - 5}")
    else:
        print(f"  {ds_name}: нет коллизий")

# IBM/Modbus перебор
print()
print("=" * 60)
print("ПЕРЕБОР init для CRC16-IBM (poly=0xA001)")
print("=" * 60)

for ds_name, (d1, d2) in test_data_sets.items():
    matches = []
    for init in range(0x10000):
        h1 = crc16_ibm(d1, init)
        h2 = crc16_ibm(d2, init)
        if h1 == h2:
            matches.append((init, h1))
    if matches:
        print(f"  {ds_name}: {len(matches)} коллизий")
        for init, val in matches[:5]:
            print(f"    init=0x{init:04X} => 0x{val:04X}")
        if len(matches) > 5:
            print(f"    ... и ещё {len(matches) - 5}")
    else:
        print(f"  {ds_name}: нет коллизий")

print()
print("=" * 60)
print("ГОТОВО")
print("=" * 60)
