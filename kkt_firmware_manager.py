# -*- coding: utf-8 -*-
import sys
import struct
import argparse
import win32com.client
import time

# Установка кодировки вывода для консоли Windows
if hasattr(sys.stdout, 'reconfigure') and sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')

"""
Скрипт для управления прошивкой ККТ (POS Center / Штрих-М)
Функции:
1. Получение детальной информации о версии ПО (Прошивка, Загрузчик).
2. Попытка инициации обновления через сервер обновлений (для ККТ с поддержкой этой функции).
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

class KKTFirmwareManager:
    def __init__(self):
        self.drv = create_driver()
            
        self.drv.Password = 30 # Стандартный пароль админа
        self.drv.SysAdminPassword = 30

    def connect_tcp(self, ip, port=7778):
        print(f"Подключение к ККТ по TCP {ip}:{port}...")
        self.drv.ConnectionType = 6 # TCP Socket
        self.drv.IPAddress = ip
        self.drv.TCPPort = port
        self.drv.UseIPAddress = True
        self.drv.Timeout = 3000 # 3 сек
        self.drv.Connect()
        return self._check_connection()

    def connect_com(self, port_num, baud_rate=115200):
        print(f"Подключение к ККТ по COM{port_num} ({baud_rate})...")
        self.drv.ConnectionType = 0 # Local COM
        self.drv.ComNumber = port_num
        self.drv.BaudRate = self._get_baud_rate_index(baud_rate)
        self.drv.Connect()
        return self._check_connection()

    def disconnect(self):
        self.drv.Disconnect()
        print("Отключено.")

    def _get_baud_rate_index(self, rate):
        rates = {2400: 0, 4800: 1, 9600: 2, 19200: 3, 38400: 4, 57600: 5, 115200: 6}
        return rates.get(rate, 6)

    def _check_connection(self):
        if self.drv.ResultCode == 0:
            print("Связь установлена успешно.")
            return True
        else:
            print(f"Ошибка подключения: {self.drv.ResultCode} - {self.drv.ResultCodeDescription}")
            return False

    def show_version_info(self):
        print("\n--- Информация о системе ---")
        
        # Запрос основных метрик
        self.drv.GetDeviceMetrics()
        print(f"Модель: {self.drv.UDescription}")
        
        # Получение длинного запроса состояния для версий
        if self.drv.GetECRStatus() == 0:
             print(f"Версия ПО: {self.drv.ECRSoftVersion}")
             print(f"Сборка ПО: {self.drv.ECRBuild}")
             try:
                 print(f"Дата ПО: {self.drv.ECRSoftDate}")
             except:
                 pass
             print(f"Версия ФН: {self.drv.FNSoftVersion}")
             print(f"Режим кассы: {self.drv.ECRModeDescription}")
        else:
            print("Не удалось получить статус ККТ.")

        # Попытка получить версию загрузчика (через таблицы или прямую команду, если доступна)
        # Стандартного свойства LoaderVersion в DrvFR может не быть, зависит от версии драйвера.

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="KKT Firmware Manager")
    parser.add_argument("--ip", default="192.168.137.111",
                        help="IP-adres KKT (default: 192.168.137.111)")
    parser.add_argument("--port", type=int, default=7778,
                        help="TCP port KKT (default: 7778)")
    parser.add_argument("--timeout", type=int, default=3000,
                        help="Connection timeout ms (default: 3000)")
    args = parser.parse_args()

    manager = KKTFirmwareManager()
    
    print(f"Connecting via TCP {args.ip}:{args.port}...")
    if manager.connect_tcp(args.ip, args.port):
        manager.show_version_info()
        manager.disconnect()
    
    print("\nДля обновления прошивки используйте пункт 4 в меню run.bat")
