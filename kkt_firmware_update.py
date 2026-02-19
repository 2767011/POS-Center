# -*- coding: utf-8 -*-
import sys
import os
import time
import argparse
import win32com.client
from datetime import datetime

# === ЛОГИРОВАНИЕ ===
def _detect_terminal_encoding():
    """Определяет кодировку для вывода в консоль/pipe."""
    if sys.stdout.isatty():
        # Консоль - используем UTF-8 (после chcp 65001)
        return 'utf-8'
    else:
        # Pipe (PsExec, SSH, перенаправление) - используем OEM-кодировку
        # PsExec передает байты как есть, клиент отображает в своей OEM cp
        # На русской Windows OEM = cp866
        try:
            import ctypes
            oem_cp = ctypes.windll.kernel32.GetOEMCP()
            return f'cp{oem_cp}'
        except Exception:
            return 'cp866'

class DualLogger:
    """Пишет и в консоль (в OEM/UTF-8), и в файл (всегда UTF-8)"""
    def __init__(self, filename, encoding='utf-8'):
        self.terminal = sys.stdout
        self.terminal_buf = getattr(self.terminal, 'buffer', None)
        self.filename = filename
        self.encoding = encoding
        self.term_encoding = _detect_terminal_encoding()
        # Очищаем файл лога при старте
        with open(self.filename, 'w', encoding=self.encoding) as f:
            f.write('')
            
    def write(self, message):
        # В консоль/pipe - в правильной кодировке
        try:
            if self.terminal_buf:
                # Пишем байты напрямую, минуя TextIOWrapper
                self.terminal_buf.write(message.encode(self.term_encoding, errors='replace'))
                self.terminal_buf.flush()
            else:
                self.terminal.write(message)
                self.terminal.flush()
        except Exception:
            pass

        # В файл - всегда UTF-8
        try:
            with open(self.filename, 'a', encoding=self.encoding) as f:
                f.write(message)
        except Exception:
            pass

    def flush(self):
        try:
            if self.terminal_buf:
                self.terminal_buf.flush()
            else:
                self.terminal.flush()
        except Exception:
            pass

# Для консоли - переключаем codepage на UTF-8
if sys.platform == 'win32' and sys.stdout.isatty():
    os.system('chcp 65001 > nul')

# Настраиваем логирование
log_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'update_kkt.log')
sys.stdout = DualLogger(log_file)
sys.stderr = sys.stdout # Ошибки туда же

# Импортируем функционал дампа таблиц
try:
    import kkt_dump_tables
except ImportError:
    # Если запускаем из другой директории, пробуем добавить текущую в путь
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    try:
        import kkt_dump_tables
    except ImportError:
        print("ОШИБКА: Не найден модуль kkt_dump_tables.py для создания бэкапа.")
        sys.exit(1)

def create_driver():
    try:
        drv = win32com.client.Dispatch("AddIn.DrvFR")
        return drv
    except Exception as e:
        print(f"ОШИБКА: Не удалось создать объект драйвера AddIn.DrvFR: {e}")
        return None

def connect_tcp(drv, ip, port, password=30):
    print(f"Подключение к {ip}:{port}...")
    drv.Password = password
    drv.UseIPAddress = True
    drv.IPAddress = ip
    drv.TCPPort = port
    drv.ConnectionType = 6  # TCP Socket
    
    res = drv.Connect()
    if res == 0:
        print(f"Связь установлена. {drv.UDescription} {drv.SerialNumber}")
        return True
    else:
        print(f"Ошибка подключения: {res} ({drv.ResultCodeDescription})")
        return False

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
        # Выводим сообщение, только если оно изменилось или прошло 10 секунд
        if msg != last_msg:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] [{elapsed}с] Статус: {msg} (Код: {status})")
            last_msg = msg
        elif elapsed > 0 and elapsed % 10 == 0:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] [{elapsed}с] ... процесс идет ... ({msg})")
            
        if status == 0: # Успешно
            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Обновление прошивки УСПЕШНО завершено!")
            return True
        elif status == 2: # Ошибка
            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] ОШИБКА обновления прошивки: {msg}")
            return False
        elif status == 1: # В процессе
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
    
    # Настройки для РИТЕЙЛ-01ФМ
    # UpdateFirmwareMethod:
    # 0 – DFU (USB) - Требуется для обновления по RNDIS/USB
    # 1 – XMODEM (RS-232)
    # 2 – SD Card / Flash 
    METHOD_DFU = 0
    
    drv.Password = 30
    drv.UpdateFirmwareMethod = METHOD_DFU
    drv.FileName = abs_path
    
    # Запуск обновления
    # Метод UpdateFirmware асинхронный
    res = drv.UpdateFirmware()
    
    if res != 0:
        print(f"Не удалось запустить обновление: {res} ({drv.ResultCodeDescription})")
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
        except:
            date = "Unknown"
        return {"version": ver, "build": build, "date": date}
    except Exception as e:
        print(f"Ошибка получения версии: {e}")
        return None

def check_and_close_shift(drv):
    """Проверяет статус смены и закрывает её при необходимости"""
    print("\nПроверка статуса смены...")
    res = drv.GetECRStatus()
    if res != 0:
        print(f"Ошибка получения статуса ККТ: {drv.ResultCodeDescription}")
        return False

    mode = drv.ECRMode
    print(f"Текущий режим: {mode} ({drv.ECRModeDescription})")

    # Режимы открытой смены: 2 (Открытая смена), 3 (Открытая смена > 24 часов)
    if mode in [2, 3]:
        print("Смена ОТКРЫТА. Выполняется автоматическое закрытие смены (Z-отчет)...")
        
        drv.Password = 30
        res = drv.PrintReportWithCleaning()
        
        if res != 0:
            print(f"ОШИБКА закрытия смены: {drv.ResultCode} - {drv.ResultCodeDescription}")
            # Пытаемся понять, критично ли это. Для прошивки - да.
            return False
            
        print("Команда закрытия смены отправлена. Ожидание завершения...")
        
        # Ждем завершения печати/операции
        # Обычно это занимает время (печать чека + обмен с ОФД)
        for _ in range(30): # до 60 секунд
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
        # Режим 0 - принтер в рабочем режиме (странно для ФР), и т.д.
        # Для прошивки режим 4 идеален.
        # Но если режим, например, 8 (Открытый документ), надо отменять чек.
        if mode == 8:
            print("Открыт чек. Попытка отмены чека...")
            drv.Password = 30
            drv.CancelCheck()
            time.sleep(1)
            return check_and_close_shift(drv) # Рекурсия для повторной проверки
            
        return True # Попробуем продолжить на страх и риск, если это не открытая смена

def read_table_field(drv, table, row, field, password=30):
    drv.Password = password
    drv.TableNumber = table
    drv.RowNumber = row
    drv.FieldNumber = field
    
    # Сначала получаем структуру поля
    res = drv.GetFieldStruct()
    if res != 0:
        print(f"Ошибка чтения структуры поля {table}.{row}.{field}: {drv.ResultCodeDescription}")
        return None
        
    # Читаем значение
    res = drv.ReadTable()
    if res != 0:
        print(f"Ошибка чтения таблицы {table}.{row}.{field}: {drv.ResultCodeDescription}")
        return None
        
    if drv.FieldType: # True = String
        return drv.ValueOfFieldString
    else: # False = Integer
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
    
    # "---" означает отсутствие ключей (по информации от пользователя)
    # Используем нечеткое сравнение на случай пробелов
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
        # Если это папка, ищем подходящий файл
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
        # Если это файл, проверяем совместимость
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
        # Пробуем подключиться без вывода лишних сообщений об ошибках
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
    
    args = parser.parse_args()
    
    if not args.file:
        print("Необходимо указать путь к файлу или папке с прошивкой (--file)")
        sys.exit(1)
    
    drv = create_driver()
    if not drv:
        sys.exit(1)
        
    if not connect_tcp(drv, args.ip, args.port):
        sys.exit(1)
        
    # Получаем текущую версию
    old_version = get_version_info(drv)
    if old_version:
        print(f"\nТекущая версия: {old_version['version']}, Сборка: {old_version['build']}, Дата: {old_version['date']}")
    
    # ПРОВЕРКА И ЗАКРЫТИЕ СМЕНЫ
    if not check_and_close_shift(drv):
        print("Не удалось подготовить ККТ (смена не закрыта). Обновление отменено.")
        drv.Disconnect()
        sys.exit(1)

    # Проверка ключей
    kkt_variant = check_kkt_variant(drv)
    
    variant_str = "БЕЗ КЛЮЧЕЙ (OLD)" if kkt_variant == 0 else "С КЛЮЧАМИ (NEW)"
    print(f"\n==========================================")
    print(f"ОПРЕДЕЛЕН ТИП ККТ: {variant_str}")
    print(f"==========================================\n")
    
    # Выбор/Проверка файла
    fw_file = select_firmware(kkt_variant, args.file, force=args.force)
    if not fw_file:
        print("Отмена операции.")
        sys.exit(1)
        
    print(f"Выбран файл прошивки: {fw_file}")

    # 1. Бэкап таблиц
    if not args.skip_backup:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        serial = str(drv.SerialNumber).strip()
        backup_filename = f"tables_backup_{serial}_{timestamp}.csv"
        backup_path = os.path.abspath(backup_filename)
        
        print(f"\n=== ЭТАП 1: БЭКАП ТАБЛИЦ ===")
        print(f"Сохранение таблиц в {backup_path}...")
        
        try:
            # Используем функцию из соседнего модуля
            # Передаем None в table_filter, чтобы сохранить ВСЕ таблицы
            kkt_dump_tables.dump_tables(drv, backup_path, table_filter=None)
            print("Бэкап успешно создан.")
        except Exception as e:
            print(f"ОШИБКА при создании бэкапа: {e}")
            if args.force:
                print("Режим --force: Остановка из-за ошибки бэкапа для безопасности.")
                sys.exit(1)
            
            choice = input("Продолжить без бэкапа? (y/n): ")
            if choice.lower() != 'y':
                sys.exit(1)
    else:
        print("\n=== Бэкап таблиц пропущен ===")

    # 2. Обновление прошивки
    print(f"\n=== ЭТАП 2: ОБНОВЛЕНИЕ ПРОШИВКИ ===")
    
    # Подтверждение пользователя
    print(f"Вы собираетесь прошить кассу файлом: {fw_file}")
    
    if not args.force:
        confirm = input("Введите 'YES' (большими буквами) для подтверждения: ")
        if confirm != 'YES':
            print("Операция отменена пользователем.")
            sys.exit(0)
    else:
        print("Режим --force: Автоматическое подтверждение.")
        
    if update_firmware(drv, fw_file):
        print("\nКасса отправлена на перезагрузку...")
        
        # Реконнект и проверка версии
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
            else:
                print("СТАЛО: <не удалось получить данные>")
            print("="*40 + "\n")
            
        print("Рекомендуется проверить таблицы и настройки.")
    else:
        print("\nОбновление завершилось неудачей.")
        sys.exit(1)

    drv.Disconnect()

if __name__ == '__main__':
    main()
