# -*- coding: utf-8 -*-
import sys
import struct
import argparse
import win32com.client

# Установка кодировки вывода для консоли Windows
try:
    if hasattr(sys.stdout, 'reconfigure') and hasattr(sys.stdout, 'encoding') and sys.stdout.encoding != 'utf-8':
        sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

"""
Скрипт для получения детальной информации о ККТ (POS Center / Штрих-М)
Выводит:
- Версии ПО и железа
- Состояние ФН (Фискального Накопителя)
- Сетевые настройки
- Настройки ОФД
- Текущий статус смены
- Лицензии
"""

COM_PROG_IDS = ["AddIn.DrvFR", "Addin.DrvFR"]

def create_driver():
    """Создание COM-объекта драйвера ККТ (AddIn.DrvFR).
    Требует зарегистрированную DrvFR.dll соответствующей разрядности."""
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

class KKTInfoGatherer:
    def __init__(self):
        self.drv = create_driver()
        self.drv.Password = 30
        self.drv.SysAdminPassword = 30

    def _safe_get(self, attr, default="N/A"):
        """Безопасное чтение свойства COM-объекта."""
        try:
            val = getattr(self.drv, attr)
            return val if val is not None else default
        except (AttributeError, Exception):
            return default

    def connect(self, connection_params):
        """
        connection_params: dict с параметрами подключения
        Пример: {'ConnectionType': 6, 'IPAddress': '192.168.1.10', 'TCPPort': 7778}
        """
        print("Подключение к ККТ...")
        for key, value in connection_params.items():
            setattr(self.drv, key, value)
            
        self.drv.Connect()
        if self.drv.ResultCode == 0:
            print("Связь установлена.")
            return True
        else:
            print(f"Ошибка подключения: {self.drv.ResultCode} - {self._safe_get('ResultCodeDescription')}")
            return False

    def disconnect(self):
        self.drv.Disconnect()

    def get_device_info(self):
        print("\n--- ОБЩАЯ ИНФОРМАЦИЯ ---")
        try:
            self.drv.GetDeviceMetrics()
            print(f"Модель: {self._safe_get('UDescription')}")
            print(f"Код модели: {self._safe_get('UModel')}")
        except Exception as e:
            print(f"GetDeviceMetrics ошибка: {e}")

        if self.drv.GetECRStatus() == 0:
            print(f"Заводской номер: {self._safe_get('SerialNumber')}")
            print(f"ИНН: {self._safe_get('INN')}")
            print(f"Версия ПО: {self._safe_get('ECRSoftVersion')}")
            print(f"Сборка ПО: {self._safe_get('ECRBuild')}")
            print(f"Дата ПО: {self._safe_get('ECRSoftDate')}")
            ecr_mode = self._safe_get('ECRMode', -1)
            print(f"Режим работы: {self._safe_get('ECRModeDescription')} (Code: {ecr_mode})")
            print(f"Номер документа: {self._safe_get('DocumentNumber')}")
            print(f"Текущая смена: {self._safe_get('SessionNumber')}")
            shift_state = "Открыта" if ecr_mode in [2, 3] else "Закрыта"
            print(f"Состояние смены: {shift_state}")
            print(f"Дата ККТ: {self._safe_get('Date')}")
            print(f"Время ККТ: {self._safe_get('Time')}")
        else:
            print(f"Не удалось получить статус ККТ: {self.drv.ResultCode} - {self._safe_get('ResultCodeDescription')}")

    def get_fn_info(self):
        print("\n--- СТАТУС ФН ---")
        try:
            rc = self.drv.FNGetStatus()
        except Exception as e:
            print(f"FNGetStatus не поддерживается: {e}")
            return
        if rc == 0:
            fn_ver = self._safe_get('FNSoftVersion')
            if fn_ver:
                print(f"Версия ПО ФН: {fn_ver}")
            fn_state = self._safe_get('FNSessionState', None)
            if fn_state is not None:
                states = {0: "Закрыта", 1: "Открыта"}
                print(f"Состояние смены ФН: {states.get(fn_state, fn_state)}")
            fn_doc = self._safe_get('FNCurrentDocument', None)
            if fn_doc is not None:
                print(f"Текущий документ ФН: {fn_doc}")
            fn_warn = self._safe_get('FNWarningFlags', None)
            if fn_warn is not None and fn_warn != 0:
                print(f"Предупреждения ФН: {fn_warn}")
            elif fn_warn == 0:
                print("Предупреждения ФН: нет")
        else:
            print(f"Ошибка чтения статуса ФН: {self.drv.ResultCode} - {self._safe_get('ResultCodeDescription')}")

    def _read_table_value(self, table, row, field, field_type='String'):
        self.drv.TableNumber = table
        self.drv.RowNumber = row
        self.drv.FieldNumber = field
        if self.drv.ReadTable() == 0:
            if field_type == 'String':
                return self.drv.ValueOfFieldString
            else:
                return self.drv.ValueOfFieldInteger
        return None

    def _get_field_name(self, table, field):
        """Получить название поля таблицы."""
        try:
            self.drv.TableNumber = table
            self.drv.FieldNumber = field
            self.drv.GetFieldStruct()
            return self._safe_get('FieldName', f'Field{field}')
        except:
            return f'Field{field}'

    def get_ofd_settings(self):
        print("\n--- НАСТРОЙКИ ОФД (Таблица 19) ---")
        # Поле 1 - Сервер ОФД, Поле 2 - Порт ОФД
        server = self._read_table_value(19, 1, 1)
        port = self._read_table_value(19, 1, 2, 'Int')
        timeout = self._read_table_value(19, 1, 3, 'Int')
        
        print(f"Сервер ОФД: {server}")
        print(f"Порт ОФД: {port}")
        if timeout is not None:
            print(f"Таймаут чтения ответа: {timeout}")

        # Поля 5-8: Сервер КМ (код маркировки)
        km_server = self._read_table_value(19, 1, 5)
        km_port = self._read_table_value(19, 1, 6, 'Int')
        if km_server:
            print(f"Сервер КМ: {km_server}")
            print(f"Порт КМ: {km_port}")

        # Поле 9: Сервер АС ОКП
        okp_server = self._read_table_value(19, 1, 9)
        if okp_server:
            print(f"Сервер АС ОКП: {okp_server}")

    def get_license_info(self):
        print("\n--- ЛИЦЕНЗИИ И КОДЫ ЗАЩИТЫ ---")
        # Таблица 10 - Коды защиты
        print("Коды защиты (Таблица 10):")
        kz1 = self._read_table_value(10, 1, 1, 'Int')
        print(f"  КЗ 1 (базовый): {'Введен' if kz1 else 'Не введен/Нет доступа'}")
        
        kz4 = self._read_table_value(10, 4, 1, 'Int')
        print(f"  КЗ 4 (Маркировка): {'Введен' if kz4 else 'Не введен/Нет доступа'}")

    def get_network_settings(self):
        print("\n--- СЕТЕВЫЕ НАСТРОЙКИ (Таблица 21) ---")
        # Таблица 21 - СЕТЕВЫЕ ИНТЕРФЕЙСЫ
        # Поля: 1-PPP, 2-Обмен ОФД, 3-TCP-сервер, 4-Порт TCP, 5-WIFI наличие,
        #        6-WIFI исп., 7-SSID, 8-Passphrase, 9-RNDIS
        
        ppp_mode = self._read_table_value(21, 1, 1, 'Int')
        ofd_mode = self._read_table_value(21, 1, 2, 'Int')
        tcp_server = self._read_table_value(21, 1, 3, 'Int')
        tcp_port = self._read_table_value(21, 1, 4, 'Int')
        wifi_present = self._read_table_value(21, 1, 5, 'Int')
        wifi_use = self._read_table_value(21, 1, 6, 'Int')
        wifi_ssid = self._read_table_value(21, 1, 7)
        rndis = self._read_table_value(21, 1, 9, 'Int')

        ofd_modes = {0: "PPP", 1: "WiFi", 2: "Ethernet", 3: "RNDIS"}
        print(f"Режим PPP: {ppp_mode}")
        print(f"Режим обмена с ОФД: {ofd_modes.get(ofd_mode, ofd_mode)}")
        print(f"TCP-сервер: {'Вкл' if tcp_server else 'Выкл'} (порт: {tcp_port})")
        print(f"WiFi: {'Есть' if wifi_present else 'Нет'}, {'Используется' if wifi_use else 'Не используется'}")
        if wifi_ssid:
            print(f"WiFi SSID: {wifi_ssid}")
        print(f"RNDIS: {'Вкл' if rndis else 'Выкл'}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="KKT Info - diagnostics tool")
    parser.add_argument("--ip", default="192.168.137.111",
                        help="IP-adres KKT (default: 192.168.137.111)")
    parser.add_argument("--port", type=int, default=7778,
                        help="TCP port KKT (default: 7778)")
    parser.add_argument("--com", type=int, default=None,
                        help="COM port number (instead of TCP)")
    parser.add_argument("--baud", type=int, default=6,
                        help="Baud rate code: 6=115200 (default: 6)")
    parser.add_argument("--timeout", type=int, default=3000,
                        help="Connection timeout ms (default: 3000)")
    args = parser.parse_args()

    gatherer = KKTInfoGatherer()
    
    if args.com is not None:
        params = {
            'ConnectionType': 0,
            'ComNumber': args.com,
            'BaudRate': args.baud
        }
        print(f"Connecting via COM{args.com} (baud code {args.baud})...")
    else:
        params = {
            'ConnectionType': 6,
            'IPAddress': args.ip,
            'TCPPort': args.port,
            'UseIPAddress': True,
            'Timeout': args.timeout
        }
        print(f"Connecting via TCP {args.ip}:{args.port}...")

    if gatherer.connect(params):
        gatherer.get_device_info()
        gatherer.get_fn_info()
        gatherer.get_ofd_settings()
        gatherer.get_network_settings()
        gatherer.get_license_info()
        gatherer.disconnect()
    
    print("\nScript finished.")
