# Agent Skill: Управление ККТ (Драйвер Штрих-М / POS Center)

## 1. Контекст и Назначение
Этот скилл предназначен для разработки скриптов (Python, PowerShell, Batch) управления фискальными регистраторами (ККТ) производства "Штрих-М" и "POS Center" (совместимых), использующих COM-драйвер.
Основная среда выполнения: Windows.

**Поддерживаемые COM-объекты (ProgID):**
- `AddIn.DrvFR` — драйвер Штрих-М (InprocServer, DLL). CLSID `{E187099F-8C5C-4723-8866-D8DBB6353ADE}`. Версия 5.21.0.1222.
  - 64-бит: `C:\Program Files\Poscenter\DrvKKT\Bin\DrvFR.dll` (работает с 64-бит Python)
  - 32-бит: `C:\Program Files (x86)\Poscenter\DrvKKT\Bin\DrvFR.dll` (НЕ работает с 64-бит Python!)
  - **DLL-зависимости** (должны лежать рядом с DrvFR.dll): `libeay32.dll`, `ssleay32.dll`, `sqlite3.dll`, `DrvFR.lic`
- `SrvFRLib.SrvFR` — драйвер POS Center (LocalServer, `C:\Program Files\POSCenter\DrvKKT\Bin\SrvFR.exe`). Другой интерфейс! Нет Password, TableNumber и пр. Для скриптов НЕ подходит.

**Регистрация DrvFR.dll:**
- `regsvr32 /s "C:\...\DrvFR.dll"` — при удалённой регистрации через WMI используй `schtasks`, не WMI напрямую (Session 0 блокирует GUI-регистрацию)
- **COM Surrogate (DllSurrogate) НЕ РАБОТАЕТ** для DrvFR.dll — нельзя использовать 32-бит DLL с 64-бит Python через surrogate
- **Решение:** копировать 64-бит DrvFR.dll + зависимости и регистрировать нативно
- **AppID в CLSID мешает работе InprocServer** — если ранее настраивался surrogate, обязательно удалить `AppID` из `HKLM\SOFTWARE\Classes\CLSID\{...}`

При инициализации всегда пробовать оба ProgID последовательно.

## 2. Архитектура Драйвера
Взаимодействие с ККТ происходит через OLE Automation сервер (COM-объект).
- **ProgID (Штрих-М):** `AddIn.DrvFR` (или `AddIn.DrvFR4`)
- **ProgID (POS Center):** `SrvFRLib.SrvFR`
- **Принцип работы:** Установка свойств объекта -> Вызов метода -> Проверка `ResultCode`.

### Базовый алгоритм работы (Pattern)
1. Создать COM-объект (пробуя оба ProgID).
2. Установить пароль администратора (`SysAdminPassword`, дефолт "30") или оператора (`Password`, дефолт "1").
3. Подключиться (`Connect()`).
4. Выполнить бизнес-логику (чтение таблиц, печать чека).
5. Отключиться (`Disconnect()`).

## 3. Примеры реализации (Code Patterns)

### Python (win32com)
```python
import win32com.client

COM_PROG_IDS = ["AddIn.DrvFR", "Addin.DrvFR"]

def create_driver():
    for prog_id in COM_PROG_IDS:
        try:
            drv = win32com.client.Dispatch(prog_id)
            _ = drv.Password  # проверка интерфейса
            return drv
        except Exception:
            continue
    raise RuntimeError(f"COM driver not found: {COM_PROG_IDS}")

drv = create_driver()
drv.Password = 30
drv.ConnectionType = 6  # TCP
drv.IPAddress = "192.168.1.10"
drv.TCPPort = 7778
drv.Connect()
if drv.ResultCode == 0:
    drv.GetShortECRStatus()
    print(f"Mode: {drv.ECRMode}, Desc: {drv.ECRModeDescription}")
drv.Disconnect()
```

### PowerShell
```powershell
$drv = $null
foreach ($progId in @("AddIn.DrvFR", "SrvFRLib.SrvFR")) {
    try { $drv = New-Object -ComObject $progId; break } catch {}
}
if (-not $drv) { throw "KKT driver not found" }
$drv.Password = "30"
$drv.Connect()
if ($drv.ResultCode -eq 0) {
    $drv.GetShortECRStatus()
    Write-Host "Mode: $($drv.ECRMode)"
}
$drv.Disconnect()
```

## 4. Ключевые операции

### 4.1. Работа с Таблицами (Настройки)
ККТ хранит настройки в таблицах. Доступ через методы `ReadTable()` и `WriteTable()`.
**Важные таблицы:**
*   **Таблица 1 (Тип и режим кассы):** Сетевые настройки, тайм-ауты.
*   **Таблица 6 (Налоговые ставки):** Программирование имен и величин налогов.
*   **Таблица 14 (Параметры ОФД):** Хост, порт ОФД, таймауты чтения.
*   **Таблица 18 (Наименования типов оплат):** "Наличными", "Безналичными" и т.д.

**Алгоритм записи в таблицу:**
1. `TableNumber = X`
2. `RowNumber = Y`
3. `FieldNumber = Z`
4. `ReadTable()` — Прочитать текущее значение (чтобы убедиться в доступе).
5. `ValueOfFieldInteger` или `ValueOfFieldString` = Новое значение.
6. `WriteTable()` — Записать.

### 4.2. Регистрация Чека (ФН)
Операции фискализации требуют строгой последовательности.
1. `OpenCheck()` — Открыть чек (Тип: 0-Приход, 1-Расход, 2-Возврат прихода).
2. `FNSendTag()` — (Опционально) Передача тега кассира (1021) или покупателя.
3. `Price`, `Quantity`, `Summ1` (сумма позиции), `StringForPrinting` (название) -> `FNOperation()` — Регистрация позиции.
4. `Summ1` (сумма оплаты нал) или `Summ4` (безнал) -> `FNCloseCheckEx()` — Закрытие чека.

### 4.3. Отчеты
*   **X-отчет (без гашения):** `PrintReportWithoutCleaning()`
*   **Z-отчет (с гашением/закрытие смены):** `FNBeginCloseSession()` -> `PrintReportWithCleaning()`

## 5. Типичные проблемы и решения
*   **ResultCode 11 (Нет связи):** Проверить `ComputerName` (если по сети) или COM-порт. Проверить скорость порта (`BaudRate`).
*   **Смена превысила 24 часа:** Выполнить Z-отчет (`PrintReportWithCleaning`).
*   **Ошибка ФН (неверное состояние):** Проверить статус ФН (`FNGetStatus`), убедиться, что смена открыта (`FNOpenSession`).
*   **Блокировка ввода:** ККТ ждет завершения операции (например, печати). Использовать `WaitForPrinting()`.

## 6. Справочная информация
*   **Режимы (ECRMode):**
    *   2: Открытая смена, < 24ч.
    *   3: Открытая смена, > 24ч (Блокировка).
    *   4: Закрытая смена.
*   **Пароли:** Админ: 30, Системный админ: 29, Оператор: 1.
*   **Типы оплаты (PaymentTypeSign):** 1-Безнал, 2-Предоплата, 3-Постоплата, 4-Встречное предоставление.

Этот скилл аккумулирует знания из официальной документации "Штрих-М" и практических примеров использования драйвера.
