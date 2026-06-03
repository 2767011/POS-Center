# KKT Toolkit

## Факты

- Проект управляет ККТ POS Center / Штрих-М через COM-драйвер `AddIn.DrvFR` и Python `win32com.client`.
- Основной общий слой: `kkt_driver.py` (`create_driver`, `connect_tcp`, `connect_com`, `safe_get`, чтение таблиц, стандартные argparse-аргументы).
- Диагностика вынесена в `kkt_info.py`, дамп таблиц в `kkt_dump_tables.py`, прошивка в `kkt_firmware_update.py`, COM-инспекция в `probe_com.py`.
- Основные обёртки: `run.bat` для локального меню, `run_update.bat` для прямой прошивки, `auto_update.bat` для удалённого автообновления, `download.ps1` для скачивания файлов и прошивок.
- Окружение ставится через portable Python и `pywin32`; для старых Windows предусмотрен отдельный Python-пакет.
- `download.ps1` скачивает `VCOM+DFU.zip` из updater-раздела веб-сервера, распаковывает в рабочую директорию и проверяет наличие DFU/VCOM INF-файлов.
- `auto_update.bat` пытается установить USB VCOM/DFU-драйверы отдельным шагом до проверки `.bin` и запуска `kkt_firmware_update.py`; ошибка установки не блокирует прошивку.

## Ограничения

- Не сохранять в памяти конкретные внутренние адреса, URL, пароли, хэши и серверные пути из документации или `server_snapshot/`.
- Для `AddIn.DrvFR` нужна нативная DLL той же разрядности, что и Python; 32-битный драйвер с 64-битным Python через COM Surrogate не подходит.
- Удалённый `auto_update.bat` требует прав администратора из-за регистрации COM-драйвера.

## Грабли

- ⚠️ При запуске через PsExec `%~dp0` может указывать на системную директорию, поэтому автообновление использует временную KKT-директорию.
- ⚠️ Для совместимости с PsExec/pipe в `kkt_firmware_update.py` вывод в консоль кодируется отдельно, а лог пишется в UTF-8.
- ⚠️ Для Windows 7/старых PowerShell распаковка ZIP в `download.ps1` должна иметь fallback без `Expand-Archive`; используется совместимая функция `Expand-ZipCompat`.
- ⚠️ DFU/VCOM-драйвер — вспомогательный preflight: при ошибке установки писать лог/крупное предупреждение, но не останавливать прошивку.
- ⚠️ На кассе установка DFU прошла, а VCOM (`lpc-ucom-vcom.inf`) упал с `0xe0000242`: издатель Authenticode-каталога NXP не находится в доверенных издателях; в non-interactive запуске Windows не может показать UI подтверждения.
- Решение для `0xe0000242`: перед `pnputil` добавить подписанта `.cat` в `LocalMachine\TrustedPublisher` через `Get-AuthenticodeSignature` и `X509Store`; после этого DFU и VCOM ставятся non-interactive.
