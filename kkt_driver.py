# -*- coding: utf-8 -*-
"""
kkt_driver.py - Общий модуль для работы с COM-драйвером ККТ (Штрих-М / POS Center).

Содержит:
- create_driver() — создание COM-объекта
- safe_get() — безопасное чтение свойств
- connect_tcp() / connect_com() — подключение
- setup_encoding() — настройка кодировки консоли
- Константы (COM_PROG_IDS, DEFAULT_IP, DEFAULT_PORT, DEFAULT_PASSWORD)
"""
import sys
import struct
import win32com.client

# === Константы ===
COM_PROG_IDS = ["AddIn.DrvFR", "Addin.DrvFR"]
DEFAULT_IP = "192.168.137.111"
DEFAULT_PORT = 7778
DEFAULT_PASSWORD = 30
DEFAULT_TIMEOUT = 3000

# Коды скорости COM-порта
BAUD_RATES = {2400: 0, 4800: 1, 9600: 2, 19200: 3, 38400: 4, 57600: 5, 115200: 6}


def setup_encoding():
    """Настройка кодировки консоли Windows для корректного вывода кириллицы."""
    try:
        if hasattr(sys.stdout, 'reconfigure') and hasattr(sys.stdout, 'encoding') and sys.stdout.encoding != 'utf-8':
            sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass


def create_driver():
    """Создание COM-объекта драйвера ККТ (AddIn.DrvFR).
    Требует зарегистрированную DrvFR.dll соответствующей разрядности.

    Returns:
        COM-объект драйвера

    Raises:
        SystemExit: если COM-объект не удалось создать
    """
    errors = []

    for prog_id in COM_PROG_IDS:
        try:
            drv = win32com.client.Dispatch(prog_id)
            _ = drv.Password  # проверка интерфейса
            print(f"COM-объект создан: {prog_id}")
            return drv
        except AttributeError:
            errors.append(f"  {prog_id}: COM создан, но нет свойства Password (другой интерфейс)")
        except Exception as e:
            errors.append(f"  {prog_id}: {e}")

    bits = struct.calcsize("P") * 8
    print(f"Ошибка: не удалось создать COM-объект AddIn.DrvFR.")
    print(f"Python: {bits}-bit")
    for err in errors:
        print(err)
    print(f"\nРешение: запустите register_drvfr.bat от имени администратора")
    print(f"  Драйвер DrvFR.dll должен быть {bits}-битным, как и Python")
    sys.exit(1)


def safe_get(drv, attr, default=""):
    """Безопасное чтение свойства COM-объекта.

    Args:
        drv: COM-объект
        attr: имя свойства
        default: значение по умолчанию

    Returns:
        Значение свойства или default при ошибке
    """
    try:
        val = getattr(drv, attr)
        return val if val is not None else default
    except Exception:
        return default


def connect_tcp(drv, ip=None, port=None, timeout=None, password=None):
    """Подключение к ККТ по TCP.

    Args:
        drv: COM-объект драйвера
        ip: IP-адрес ККТ
        port: TCP-порт
        timeout: таймаут подключения (мс)
        password: пароль администратора

    Returns:
        True при успешном подключении
    """
    ip = ip or DEFAULT_IP
    port = port or DEFAULT_PORT
    timeout = timeout or DEFAULT_TIMEOUT
    password = password or DEFAULT_PASSWORD

    print(f"Подключение к ККТ по TCP {ip}:{port}...")
    drv.Password = password
    drv.SysAdminPassword = password
    drv.ConnectionType = 6  # TCP Socket
    drv.IPAddress = ip
    drv.TCPPort = port
    drv.UseIPAddress = True
    drv.Timeout = timeout
    drv.Connect()

    if drv.ResultCode == 0:
        print("Связь установлена.")
        return True
    else:
        print(f"Ошибка подключения: {drv.ResultCode} - {safe_get(drv, 'ResultCodeDescription')}")
        return False


def connect_com(drv, com_number, baud_rate=115200, password=None):
    """Подключение к ККТ по COM-порту.

    Args:
        drv: COM-объект драйвера
        com_number: номер COM-порта
        baud_rate: скорость (число или код). Если > 6, конвертируется в код.
        password: пароль администратора

    Returns:
        True при успешном подключении
    """
    password = password or DEFAULT_PASSWORD
    baud_code = BAUD_RATES.get(baud_rate, baud_rate) if baud_rate > 6 else baud_rate

    print(f"Подключение к ККТ по COM{com_number} (baud code {baud_code})...")
    drv.Password = password
    drv.SysAdminPassword = password
    drv.ConnectionType = 0  # Local COM
    drv.ComNumber = com_number
    drv.BaudRate = baud_code
    drv.Connect()

    if drv.ResultCode == 0:
        print("Связь установлена.")
        return True
    else:
        print(f"Ошибка подключения: {drv.ResultCode} - {safe_get(drv, 'ResultCodeDescription')}")
        return False


def read_table_field(drv, table, row, field):
    """Чтение значения из таблицы ККТ.

    Args:
        drv: COM-объект драйвера
        table: номер таблицы
        row: номер строки
        field: номер поля

    Returns:
        Значение поля (str или int) или None при ошибке
    """
    drv.TableNumber = table
    drv.RowNumber = row
    drv.FieldNumber = field
    if drv.ReadTable() == 0:
        # Определяем тип поля через GetFieldStruct
        drv.TableNumber = table
        drv.FieldNumber = field
        try:
            drv.GetFieldStruct()
            if drv.FieldType:  # True = String
                return drv.ValueOfFieldString
            else:
                return drv.ValueOfFieldInteger
        except Exception:
            # Если GetFieldStruct не сработал, пробуем оба варианта
            val_str = safe_get(drv, 'ValueOfFieldString', '')
            val_int = safe_get(drv, 'ValueOfFieldInteger', 0)
            return val_str if val_str else val_int
    return None


def add_connection_args(parser):
    """Добавляет стандартные аргументы подключения к argparse.ArgumentParser.

    Args:
        parser: argparse.ArgumentParser
    """
    parser.add_argument("--ip", default=DEFAULT_IP,
                        help=f"IP-адрес ККТ (default: {DEFAULT_IP})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"TCP порт ККТ (default: {DEFAULT_PORT})")
    parser.add_argument("--com", type=int, default=None,
                        help="COM порт (вместо TCP)")
    parser.add_argument("--baud", type=int, default=6,
                        help="Скорость COM: 6=115200 (default: 6)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                        help=f"Таймаут подключения мс (default: {DEFAULT_TIMEOUT})")


def connect_from_args(drv, args):
    """Подключение к ККТ на основе распарсенных аргументов.

    Args:
        drv: COM-объект драйвера
        args: результат argparse.parse_args() (должен содержать ip, port, com, baud, timeout)

    Returns:
        True при успешном подключении
    """
    if args.com is not None:
        return connect_com(drv, args.com, args.baud)
    else:
        return connect_tcp(drv, args.ip, args.port, args.timeout)
