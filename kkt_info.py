# -*- coding: utf-8 -*-
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
import sys
import argparse
from kkt_driver import setup_encoding, create_driver, safe_get, add_connection_args, connect_from_args

setup_encoding()


class KKTInfoGatherer:
    def __init__(self):
        self.drv = create_driver()
        self.drv.Password = 30
        self.drv.SysAdminPassword = 30

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
            print(f"Ошибка подключения: {self.drv.ResultCode} - {safe_get(self.drv, 'ResultCodeDescription')}")
            return False

    def disconnect(self):
        self.drv.Disconnect()

    def get_device_info(self):
        print("\n--- ОБЩАЯ ИНФОРМАЦИЯ ---")
        try:
            self.drv.GetDeviceMetrics()
            print(f"Модель: {safe_get(self.drv, 'UDescription')}")
            print(f"Код модели: {safe_get(self.drv, 'UModel')}")
        except Exception as e:
            print(f"GetDeviceMetrics ошибка: {e}")

        if self.drv.GetECRStatus() == 0:
            print(f"Заводской номер: {safe_get(self.drv, 'SerialNumber')}")
            print(f"ИНН: {safe_get(self.drv, 'INN')}")
            print(f"Версия ПО: {safe_get(self.drv, 'ECRSoftVersion')}")
            print(f"Сборка ПО: {safe_get(self.drv, 'ECRBuild')}")
            print(f"Дата ПО: {safe_get(self.drv, 'ECRSoftDate')}")
            ecr_mode = safe_get(self.drv, 'ECRMode', -1)
            print(f"Режим работы: {safe_get(self.drv, 'ECRModeDescription')} (Code: {ecr_mode})")
            print(f"Номер документа: {safe_get(self.drv, 'DocumentNumber')}")
            print(f"Текущая смена: {safe_get(self.drv, 'SessionNumber')}")
            shift_state = "Открыта" if ecr_mode in [2, 3] else "Закрыта"
            print(f"Состояние смены: {shift_state}")
            print(f"Дата ККТ: {safe_get(self.drv, 'Date')}")
            print(f"Время ККТ: {safe_get(self.drv, 'Time')}")
        else:
            print(f"Не удалось получить статус ККТ: {self.drv.ResultCode} - {safe_get(self.drv, 'ResultCodeDescription')}")

    def get_fn_info(self):
        print("\n--- СТАТУС ФН ---")
        try:
            rc = self.drv.FNGetStatus()
        except Exception as e:
            print(f"FNGetStatus не поддерживается: {e}")
            return
        if rc == 0:
            fn_ver = safe_get(self.drv, 'FNSoftVersion')
            if fn_ver:
                print(f"Версия ПО ФН: {fn_ver}")
            fn_state = safe_get(self.drv, 'FNSessionState', None)
            if fn_state is not None:
                states = {0: "Закрыта", 1: "Открыта"}
                print(f"Состояние смены ФН: {states.get(fn_state, fn_state)}")
            fn_doc = safe_get(self.drv, 'FNCurrentDocument', None)
            if fn_doc is not None:
                print(f"Текущий документ ФН: {fn_doc}")
            fn_warn = safe_get(self.drv, 'FNWarningFlags', None)
            if fn_warn is not None and fn_warn != 0:
                print(f"Предупреждения ФН: {fn_warn}")
            elif fn_warn == 0:
                print("Предупреждения ФН: нет")
        else:
            print(f"Ошибка чтения статуса ФН: {self.drv.ResultCode} - {safe_get(self.drv, 'ResultCodeDescription')}")

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
            return safe_get(self.drv, 'FieldName', f'Field{field}')
        except Exception:
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
    add_connection_args(parser)
    args = parser.parse_args()

    gatherer = KKTInfoGatherer()

    if connect_from_args(gatherer.drv, args):
        gatherer.get_device_info()
        gatherer.get_fn_info()
        gatherer.get_ofd_settings()
        gatherer.get_network_settings()
        gatherer.get_license_info()
        gatherer.disconnect()

    print("\nScript finished.")
