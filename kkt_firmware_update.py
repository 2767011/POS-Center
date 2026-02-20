# -*- coding: utf-8 -*-
import sys
import os
import time
import json
import argparse
import logging
from datetime import datetime

# Попытка использовать общий модуль драйвера.
# Если файл kkt_driver.py не скачался на удаленной машине,
# включаем локальный fallback, чтобы обновление не падало на импорте.
try:
    from kkt_driver import safe_get, DEFAULT_PASSWORD, create_driver as driver_create, connect_tcp as driver_connect_tcp
except Exception:
    import win32com.client

    DEFAULT_PASSWORD = 30

    def safe_get(drv, attr, default=""):
        try:
            val = getattr(drv, attr)
            return val if val is not None else default
        except Exception:
            return default

    def driver_create():
        try:
            return win32com.client.Dispatch("AddIn.DrvFR")
        except Exception as e:
            print(f"ОШИБКА: Не удалось создать объект драйвера AddIn.DrvFR: {e}")
            return None

    def driver_connect_tcp(drv, ip, port, password=DEFAULT_PASSWORD):
        print(f"Подключение к {ip}:{port}...")
        drv.Password = password
        drv.UseIPAddress = True
        drv.IPAddress = ip
        drv.TCPPort = port
        drv.ConnectionType = 6
        drv.Timeout = 3000
        drv.Connect()

        if safe_get(drv, 'ResultCode', 1) == 0:
            try:
                drv.GetDeviceMetrics()
                drv.GetECRStatus()
            except Exception:
                pass
            print(f"Связь установлена. {safe_get(drv, 'UDescription')} {safe_get(drv, 'SerialNumber')}")
            return True

        print(f"Ошибка подключения: {safe_get(drv, 'ResultCode')} ({safe_get(drv, 'ResultCodeDescription')})")
        return False

# === КОДЫ ЗАВЕРШЕНИЯ ===
EXIT_OK = 0
EXIT_GENERAL_ERROR = 1
EXIT_PRECHECK_FAILED = 2
EXIT_DRY_RUN_OK = 10


# === ЛОГИРОВАНИЕ ===
TERM_ENCODING = 'cp866'


def _detect_terminal_encoding():
    try:
        if sys.stdout.isatty() and getattr(sys.stdout, 'encoding', None):
            return sys.stdout.encoding
    except Exception:
        pass

    if sys.platform == 'win32':
        try:
            import ctypes
            return f"cp{ctypes.windll.kernel32.GetOEMCP()}"
        except Exception:
            return 'cp866'

    return 'utf-8'


def setup_logging(log_path):
    """Настройка logging только в файл UTF-8 (консоль пишем вручную для psexec/pipe)."""
    logger = logging.getLogger()
    logger.handlers.clear()
    logger.setLevel(logging.INFO)

    fmt = logging.Formatter('%(message)s')
    file_handler = logging.FileHandler(log_path, mode='w', encoding='utf-8')
    file_handler.setFormatter(fmt)
    logger.addHandler(file_handler)


log_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'update_kkt.log')
setup_logging(log_file)
TERM_ENCODING = _detect_terminal_encoding()


# Совместимость с существующим кодом print(...)
def print(*args, **kwargs):
    sep = kwargs.get('sep', ' ')
    end = kwargs.get('end', '\n')
    msg = sep.join(str(a) for a in args) + end

    # Консоль/pipe (устойчиво для psexec)
    try:
        buf = getattr(sys.stdout, 'buffer', None)
        if buf is not None:
            buf.write(msg.encode(TERM_ENCODING, errors='replace'))
            buf.flush()
        else:
            sys.stdout.write(msg)
            sys.stdout.flush()
    except Exception:
        pass

    # Лог-файл
    try:
        logging.getLogger().info(msg.rstrip('\n'))
    except Exception:
        pass

# Импортируем функционал дампа таблиц
try:
    import kkt_dump_tables
except ImportError:
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    try:
        import kkt_dump_tables
    except ImportError:
        print("ОШИБКА: Не найден модуль kkt_dump_tables.py для создания бэкапа.")
        sys.exit(1)


def write_json_report(path, payload):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2, default=str)


def wait_for_completion(drv):
    """Ожидание завершения обновления прошивки"""
    print("\n--- НАЧАЛО ПРОЦЕССА ПРОШИВКИ ---")
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Ожидание завершения процесса обновления...")

    last_msg = ""
    start_time = time.time()

    while True:
        status = drv.UpdateFirmwareStatus
        msg = drv.UpdateFirmwareStatusMessage

        elapsed = int(time.time() - start_time)
        if msg != last_msg:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] [{elapsed}с] Статус: {msg} (Код: {status})")
            last_msg = msg
        elif elapsed > 0 and elapsed % 10 == 0:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] [{elapsed}с] ... процесс идет ... ({msg})")

        if status == 0:  # Успешно
            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Обновление прошивки УСПЕШНО завершено!")
            return True
        elif status == 2:  # Ошибка
            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] ОШИБКА обновления прошивки: {msg}")
            return False
        elif status == 1:  # В процессе
            time.sleep(1)
        else:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Неизвестный статус: {status}")
            time.sleep(1)


def update_firmware(drv, firmware_path):
    abs_path = os.path.abspath(firmware_path)
    if not os.path.exists(abs_path):
        print(f"ОШИБКА: Файл прошивки не найден: {abs_path}")
        return False

    print(f"Начинаем обновление прошивки из файла: {abs_path}")
    print("ВНИМАНИЕ: Не выключайте питание кассы и компьютера!")

    METHOD_DFU = 0

    drv.Password = DEFAULT_PASSWORD
    drv.UpdateFirmwareMethod = METHOD_DFU
    drv.FileName = abs_path

    res = drv.UpdateFirmware()

    if res != 0:
        print(f"Не удалось запустить обновление: {res} ({safe_get(drv, 'ResultCodeDescription')})")
        return False

    print("Процесс обновления запущен.")
    return wait_for_completion(drv)


def get_version_info(drv):
    """Получает информацию о версии ПО"""
    try:
        ver = drv.ECRSoftVersion
        build = drv.ECRBuild
        try:
            date = drv.ECRSoftDate
        except Exception:
            date = "Unknown"
        return {"version": ver, "build": build, "date": date}
    except Exception as e:
        print(f"Ошибка получения версии: {e}")
        return None


def check_and_close_shift(drv, _depth=0):
    """Проверяет статус смены и закрывает её при необходимости.

    Args:
        drv: COM-объект драйвера
        _depth: счётчик глубины рекурсии (защита от бесконечного цикла)
    """
    if _depth > 3:
        print("ОШИБКА: Превышено количество попыток подготовки ККТ.")
        return False

    print("\nПроверка статуса смены...")
    res = drv.GetECRStatus()
    if res != 0:
        print(f"Ошибка получения статуса ККТ: {safe_get(drv, 'ResultCodeDescription')}")
        return False

    mode = drv.ECRMode
    print(f"Текущий режим: {mode} ({safe_get(drv, 'ECRModeDescription')})")

    # Режимы открытой смены: 2 (Открытая смена), 3 (Открытая смена > 24 часов)
    if mode in [2, 3]:
        print("Смена ОТКРЫТА. Выполняется автоматическое закрытие смены (Z-отчет)...")

        drv.Password = DEFAULT_PASSWORD
        res = drv.PrintReportWithCleaning()

        if res != 0:
            print(f"ОШИБКА закрытия смены: {drv.ResultCode} - {safe_get(drv, 'ResultCodeDescription')}")
            return False

        print("Команда закрытия смены отправлена. Ожидание завершения...")

        for _ in range(30):  # до 60 секунд
            time.sleep(2)
            drv.GetECRStatus()
            if drv.ECRMode == 4:
                print("Смена успешно закрыта.")
                return True

        if drv.ECRMode == 4:
            return True
        else:
            print(f"Таймаут закрытия смены. Текущий режим: {drv.ECRMode}")
            return False

    elif mode == 4:
        print("Смена закрыта. Можно продолжать.")
        return True
    else:
        print(f"ВНИМАНИЕ: ККТ находится в нестандартном режиме ({mode}).")
        if mode == 8:
            print("Открыт чек. Попытка отмены чека...")
            drv.Password = DEFAULT_PASSWORD
            drv.CancelCheck()
            time.sleep(1)
            return check_and_close_shift(drv, _depth + 1)

        return True


def read_table_field(drv, table, row, field, password=DEFAULT_PASSWORD):
    drv.Password = password
    drv.TableNumber = table
    drv.RowNumber = row
    drv.FieldNumber = field

    res = drv.GetFieldStruct()
    if res != 0:
        print(f"Ошибка чтения структуры поля {table}.{row}.{field}: {safe_get(drv, 'ResultCodeDescription')}")
        return None

    res = drv.ReadTable()
    if res != 0:
        print(f"Ошибка чтения таблицы {table}.{row}.{field}: {safe_get(drv, 'ResultCodeDescription')}")
        return None

    if drv.FieldType:  # True = String
        return drv.ValueOfFieldString
    else:  # False = Integer
        return drv.ValueOfFieldInteger


def check_kkt_variant(drv):
    """
    Проверяет тип ККТ (с ключами или без) по таблице 23 поле 11.
    Возвращает:
    0 - Без ключей (нужна прошивка old_frs)
    1 - С ключами (нужна обычная прошивка)
    None - Ошибка чтения
    """
    print("Проверка конфигурации ККТ (Таблица 23, Поле 11)...")
    val = read_table_field(drv, 23, 1, 11)

    if val is None:
        print("Не удалось определить наличие ключей.")
        return None

    print(f"Значение поля 23.1.11: '{val}'")

    if "---" in str(val):
        print("Тип ККТ: БЕЗ ключей (требуется прошивка 'old_frs')")
        return 0
    else:
        print("Тип ККТ: С ключами (требуется стандартная прошивка)")
        return 1


def select_firmware(kkt_variant, input_path, force=False):
    """
    Выбирает подходящий файл прошивки или проверяет указанный.
    input_path: путь к файлу или папке
    force: автоматический режим (без интерактивных запросов)
    """
    target_file = None

    if os.path.isdir(input_path):
        files = [f for f in os.listdir(input_path) if f.lower().endswith('.bin')]
        print(f"Найдено .bin файлов в папке: {len(files)}")
        for f in files:
            print(f"  - {f}")

        for f in files:
            is_old = "old_frs" in f.lower()
            if kkt_variant == 0 and is_old:
                target_file = os.path.join(input_path, f)
                break
            if kkt_variant != 0 and not is_old and "upd_app" in f.lower():
                target_file = os.path.join(input_path, f)
                break

        if not target_file:
            print(f"В папке {input_path} не найдена подходящая прошивка.")
            print(f"Ожидался файл с {'old_frs' if kkt_variant == 0 else 'upd_app'} в названии.")
            return None
    else:
        target_file = input_path
        filename = os.path.basename(target_file).lower()
        is_old_fw = "old_frs" in filename

        if kkt_variant == 0 and not is_old_fw:
            print("\nВНИМАНИЕ! ККТ без ключей, а выбрана прошивка НЕ для старых ФР!")
            print("Рекомендуется использовать файл с 'old_frs' в названии.")
            if force:
                print("Режим --force: ОТМЕНА (несовместимая прошивка).")
                return None
            if input("Всё равно продолжить? (y/n): ").lower() != 'y':
                return None
        elif kkt_variant != 0 and is_old_fw:
            print("\nВНИМАНИЕ! ККТ с ключами, а выбрана прошивка для старых ФР!")
            print("Рекомендуется использовать стандартный файл прошивки.")
            if force:
                print("Режим --force: ОТМЕНА (несовместимая прошивка).")
                return None
            if input("Всё равно продолжить? (y/n): ").lower() != 'y':
                return None

    return target_file


def reconnect_after_update(drv, ip, port, max_attempts=30):
    """Ожидание перезагрузки ККТ и переподключение"""
    print("\nОжидание перезагрузки ККТ (это может занять 1-2 минуты)...")
    drv.Disconnect()

    for i in range(max_attempts):
        time.sleep(2)
        print(f"Попытка подключения {i+1}/{max_attempts}...", end="\r")
        drv.IPAddress = ip
        drv.TCPPort = port
        drv.Timeout = 1000
        if drv.Connect() == 0:
            print(f"\nУспешное подключение!")
            return True

    print("\nНе удалось подключиться к ККТ после обновления.")
    return False


def main():
    parser = argparse.ArgumentParser(description='KKT Firmware Updater')
    parser.add_argument('--ip', default='192.168.137.111', help='IP address of KKT')
    parser.add_argument('--port', type=int, default=7778, help='TCP port')
    parser.add_argument('--file', default=r"C:\1c\dist\FR\FirmwareUpd", help='Path to firmware file (.bin) OR directory containing firmware')
    parser.add_argument('--skip-backup', action='store_true', help='Skip table backup')
    parser.add_argument('--force', action='store_true', help='Non-interactive mode (answer YES to all)')
    parser.add_argument('--dry-run', action='store_true', help='Only prechecks and compatibility checks, no firmware update')
    parser.add_argument('--report-json', default='update_report.json', help='Path to JSON report file')

    args = parser.parse_args()
    report = {
        'timestamp': datetime.now().isoformat(),
        'mode': 'dry-run' if args.dry_run else 'update',
        'ip': args.ip,
        'port': args.port,
        'firmware_input': args.file,
        'success': False,
        'details': {}
    }

    drv = driver_create()
    if not drv:
        report['details']['error'] = 'driver_create_failed'
        write_json_report(args.report_json, report)
        sys.exit(EXIT_GENERAL_ERROR)

    if not driver_connect_tcp(drv, args.ip, args.port, password=DEFAULT_PASSWORD):
        report['details']['error'] = 'connect_failed'
        write_json_report(args.report_json, report)
        sys.exit(EXIT_PRECHECK_FAILED)

    # Получаем текущую версию
    old_version = get_version_info(drv)
    if old_version:
        print(f"\nТекущая версия: {old_version['version']}, Сборка: {old_version['build']}, Дата: {old_version['date']}")

    # ПРОВЕРКА И ЗАКРЫТИЕ СМЕНЫ
    if not check_and_close_shift(drv):
        print("Не удалось подготовить ККТ (смена не закрыта). Обновление отменено.")
        report['details']['error'] = 'shift_prepare_failed'
        write_json_report(args.report_json, report)
        drv.Disconnect()
        sys.exit(EXIT_PRECHECK_FAILED)

    # Проверка ключей
    kkt_variant = check_kkt_variant(drv)

    if kkt_variant is None:
        print("ОШИБКА: Не удалось определить тип ККТ. Обновление отменено.")
        report['details']['error'] = 'kkt_variant_undefined'
        write_json_report(args.report_json, report)
        drv.Disconnect()
        sys.exit(EXIT_PRECHECK_FAILED)

    variant_str = "БЕЗ КЛЮЧЕЙ (OLD)" if kkt_variant == 0 else "С КЛЮЧАМИ (NEW)"
    report['details']['kkt_variant'] = variant_str
    print(f"\n==========================================")
    print(f"ОПРЕДЕЛЕН ТИП ККТ: {variant_str}")
    print(f"==========================================\n")

    # Выбор/Проверка файла
    fw_file = select_firmware(kkt_variant, args.file, force=args.force)
    if not fw_file:
        print("Отмена операции.")
        report['details']['error'] = 'firmware_not_selected'
        write_json_report(args.report_json, report)
        drv.Disconnect()
        sys.exit(EXIT_PRECHECK_FAILED)

    print(f"Выбран файл прошивки: {fw_file}")
    report['details']['firmware_selected'] = os.path.abspath(fw_file)

    if args.dry_run:
        print("\n=== DRY-RUN: проверка завершена, прошивка не выполнялась ===")
        report['success'] = True
        report['details']['dry_run_result'] = 'prechecks_passed'
        write_json_report(args.report_json, report)
        drv.Disconnect()
        sys.exit(EXIT_DRY_RUN_OK)

    # 1. Бэкап таблиц
    if not args.skip_backup:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        serial = str(drv.SerialNumber).strip()
        backup_filename = f"tables_backup_{serial}_{timestamp}.csv"
        backup_path = os.path.abspath(backup_filename)

        print(f"\n=== ЭТАП 1: БЭКАП ТАБЛИЦ ===")
        print(f"Сохранение таблиц в {backup_path}...")

        try:
            kkt_dump_tables.dump_tables(drv, backup_path, table_filter=None)
            print("Бэкап успешно создан.")
        except Exception as e:
            print(f"ОШИБКА при создании бэкапа: {e}")
            if args.force:
                print("Режим --force: Остановка из-за ошибки бэкапа для безопасности.")
                report['details']['error'] = 'backup_failed_force_stop'
                write_json_report(args.report_json, report)
                drv.Disconnect()
                sys.exit(EXIT_PRECHECK_FAILED)

            choice = input("Продолжить без бэкапа? (y/n): ")
            if choice.lower() != 'y':
                report['details']['error'] = 'backup_failed_user_cancel'
                write_json_report(args.report_json, report)
                drv.Disconnect()
                sys.exit(EXIT_PRECHECK_FAILED)
    else:
        print("\n=== Бэкап таблиц пропущен ===")

    # 2. Обновление прошивки
    print(f"\n=== ЭТАП 2: ОБНОВЛЕНИЕ ПРОШИВКИ ===")

    print(f"Вы собираетесь прошить кассу файлом: {fw_file}")

    if not args.force:
        confirm = input("Введите 'YES' (большими буквами) для подтверждения: ")
        if confirm != 'YES':
            print("Операция отменена пользователем.")
            report['details']['error'] = 'user_cancelled'
            write_json_report(args.report_json, report)
            drv.Disconnect()
            sys.exit(EXIT_OK)
    else:
        print("Режим --force: Автоматическое подтверждение.")

    if update_firmware(drv, fw_file):
        print("\nКасса отправлена на перезагрузку...")

        if reconnect_after_update(drv, args.ip, args.port):
            new_version = get_version_info(drv)

            print("\n" + "="*40)
            print("ОТЧЕТ ОБ ОБНОВЛЕНИИ")
            print("="*40)

            if old_version:
                print(f"БЫЛО:  Версия: {old_version['version']}, Сборка: {old_version['build']}, Дата: {old_version['date']}")
            else:
                print("БЫЛО:  <нет данных>")

            if new_version:
                print(f"СТАЛО: Версия: {new_version['version']}, Сборка: {new_version['build']}, Дата: {new_version['date']}")
                report['details']['new_version'] = new_version
            else:
                print("СТАЛО: <не удалось получить данные>")
            print("="*40 + "\n")

            if old_version:
                report['details']['old_version'] = old_version
            print("Рекомендуется проверить таблицы и настройки.")
            report['success'] = True
        else:
            report['details']['error'] = 'reconnect_failed_after_update'
            write_json_report(args.report_json, report)
            drv.Disconnect()
            sys.exit(EXIT_GENERAL_ERROR)
    else:
        print("\nОбновление завершилось неудачей.")
        report['details']['error'] = 'firmware_update_failed'
        write_json_report(args.report_json, report)
        drv.Disconnect()
        sys.exit(EXIT_GENERAL_ERROR)

    write_json_report(args.report_json, report)
    drv.Disconnect()

if __name__ == '__main__':
    main()
