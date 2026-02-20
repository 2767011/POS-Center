# POS Center — KKT Management Toolkit

Набор скриптов для управления фискальными регистраторами (ККТ) **POS Center / Штрих-М** через COM-драйвер `AddIn.DrvFR`.

## Структура проекта

```
POS Center/
├── config.bat               # Централизованные настройки (IP, порт, пути)
├── auto_update.bat          # Автоматическое обновление прошивки (PsExec/удалённо)
├── download.ps1             # Загрузка всех файлов с веб-сервера
├── run.bat                  # Интерактивное меню (локальный запуск)
├── run_update.bat           # Прямой запуск обновления (без меню)
├── setup.bat                # Установка окружения (обёртка)
├── install_python.ps1       # Установка Portable Python 3.11 + pip + pywin32
├── setup_env.ps1            # Установка окружения (расширенная, с winget)
├── register_drvfr.bat       # Регистрация DrvFR.dll (32/64 бит)
│
├── kkt_driver.py            # Общий модуль: COM-драйвер, подключение, утилиты
├── kkt_firmware_update.py   # Обновление прошивки ККТ (основной скрипт)
├── kkt_info.py              # Диагностика ККТ (версия, ФН, ОФД, сеть)
├── kkt_dump_tables.py       # Дамп всех таблиц ККТ в файл
├── probe_com.py             # Инспекция COM-интерфейса драйвера
│
├── run_dump_remote.bat      # Запуск дампа таблиц на удалённой кассе
├── AgentSkill_KKT.md        # Справочник по COM-драйверу (для AI-агента)
│
└── manual/                  # PDF-документация Штрих-М
    ├── Руководство программиста.pdf
    ├── Общее руководство по настройке ККТ.pdf
    ├── Протокол работы ККТ с ФН.pdf
    └── Примеры/
```

## Быстрый старт

### Локально (на машине с подключённой ККТ)

```batch
:: 1. Установить окружение
setup.bat

:: 2. Запустить меню
run.bat
```

### Удалённо (через PsExec с рабочей станции)

```batch
:: Скачать и запустить на удалённой кассе
PsExec \\KASSA -s -c auto_update.bat
```

### Автоматическое обновление прошивки

```batch
:: auto_update.bat сам скачивает всё с веб-сервера:
:: http://192.168.20.229/KKT/Updater/  — скрипты
:: http://192.168.20.229/KKT/FW_FR/    — прошивки (.bin)
auto_update.bat
```

## Описание скриптов

### Общий модуль

| Модуль | Назначение |
|--------|-----------|
| `kkt_driver.py` | Создание COM-объекта, подключение TCP/COM, безопасное чтение свойств, чтение таблиц, константы |

### Основные Python-скрипты

| Скрипт | Назначение | Пример запуска |
|--------|-----------|----------------|
| `kkt_info.py` | Диагностика: модель, серийник, ИНН, версия ПО, ФН, ОФД, сеть, лицензии | `python kkt_info.py --ip 192.168.137.111` |
| `kkt_dump_tables.py` | Полный дамп всех таблиц настроек ККТ в текстовый файл | `python kkt_dump_tables.py --ip 192.168.137.111 --tables 1,17,19,21` |
| `kkt_firmware_update.py` | Обновление прошивки: бэкап → проверка смены → выбор прошивки → DFU-прошивка → реконнект | `python kkt_firmware_update.py --ip 192.168.137.111 --file firmware/ --force` |
| `probe_com.py` | Перечисление всех свойств/методов COM-объекта DrvFR | `python probe_com.py` |

### Batch/PowerShell скрипты

| Скрипт | Назначение |
|--------|-----------| 
| `config.bat` | Централизованные настройки: IP, порт, путь к прошивкам |
| `auto_update.bat` | Полный цикл: загрузка файлов → установка Python → pywin32 → регистрация COM → прошивка |
| `download.ps1` | Загрузка всех скриптов и прошивок с веб-сервера (вызывается из auto_update.bat) |
| `run.bat` | Интерактивное меню с 5 пунктами (info, dump, update, probe, setup) |
| `run_update.bat` | Прямой запуск прошивки без меню (использует локальный `python/python.exe`) |
| `setup.bat` | Установка Portable Python (обёртка для install_python.ps1) |
| `install_python.ps1` | Скачивание Python 3.11.5 embed, распаковка, настройка pip, установка pywin32 |
| `setup_env.ps1` | Расширенная установка: поиск Python (py/python/python3), winget, проверка COM-драйвера |
| `register_drvfr.bat` | Универсальная регистрация DrvFR.dll (32/64 бит, PosCenter/Штрих-М) |

## Архитектура

### Подключение к ККТ

```
[Python/PowerShell] → win32com.client.Dispatch("AddIn.DrvFR") → DrvFR.dll → TCP:7778 → ККТ
```

- **COM-объект:** `AddIn.DrvFR` (InprocServer, DLL)
- **Подключение:** TCP Socket (ConnectionType=6), IP `192.168.137.111`, порт `7778` (RNDIS через USB)
- **Пароли:** Админ=30, Системный админ=30, Оператор=1

### Процесс обновления прошивки (`kkt_firmware_update.py`)

```
1. Подключение к ККТ по TCP
2. Получение текущей версии ПО
3. Проверка и закрытие смены (ECRMode 2/3 → Z-отчет → ECRMode 4)
4. Определение типа ККТ (Таблица 23, Поле 11):
   - "---" → без ключей → прошивка old_frs
   - иначе → с ключами → стандартная прошивка
5. Бэкап всех таблиц → tables_backup_{serial}_{timestamp}.csv
6. Прошивка через DFU (UpdateFirmwareMethod=0)
7. Ожидание завершения (polling UpdateFirmwareStatus)
8. Реконнект и проверка новой версии
```

### Автоматическое обновление (`auto_update.bat`)

```
0. Скачать download.ps1 с сервера → запустить (скачает остальные скрипты + прошивки)
1. Проверить/установить Portable Python 3.11.5
2. Проверить/установить pywin32
3. Проверить/зарегистрировать COM-драйвер DrvFR.dll
4. Проверить наличие .bin файлов прошивки
5. Запустить kkt_firmware_update.py --force
```

## Веб-сервер

Файлы хранятся на Apache-сервере `192.168.20.229` (Debian):

| URL | Серверный путь | Содержимое |
|-----|---------------|------------|
| `http://192.168.20.229/KKT/Updater/` | `/var/www/files/KKT/Updater/` | Скрипты (.py, .bat, .ps1) |
| `http://192.168.20.229/KKT/FW_FR/` | `/var/www/files/KKT/FW_FR/` | Прошивки (.bin) + table_after_update.csv |

### Загрузка файлов на сервер

```bash
scp *.py *.bat *.ps1 root@192.168.20.229:/var/www/files/KKT/Updater/
scp *.bin table_after_update.csv root@192.168.20.229:/var/www/files/KKT/FW_FR/
```

## Зависимости

- **Python 3.11+** (embedded/portable — устанавливается автоматически)
- **pywin32** — для `win32com.client.Dispatch`
- **DrvFR.dll** — COM-драйвер Штрих-М/POS Center (64-бит для 64-бит Python)
- **ККТ:** Retail-01FM / POS Center совместимая, подключена по RNDIS (USB), IP `192.168.137.111`

## Кодировки

- Python-скрипты: UTF-8
- `kkt_firmware_update.py` использует `DualLogger` — дуальный вывод:
  - Консоль/PsExec pipe: OEM-кодировка (cp866) для корректного отображения кириллицы
  - Лог-файл: UTF-8
- Batch-файлы: `chcp 65001` (UTF-8 codepage)

## Известные особенности

- **COM Surrogate НЕ работает** для DrvFR.dll — нужна нативная 64-бит DLL
- **PsExec:** `%~dp0` разрешается в `C:\Windows\System32\` — используем `%TEMP%\KKT`
- **Windows Defender:** `certutil` заблокирован как LOLBIN — используем `Invoke-WebRequest`
- **Тип ККТ:** Определяется по Таблице 23, Строка 1, Поле 11 — если `---`, нужна прошивка `old_frs`
