# -*- coding: utf-8 -*-
"""
kkt_dump_tables.py - Считывание всех таблиц ККТ и сохранение в файл.

Алгоритм:
1. Подключение к ККТ через TCP (или COM)
2. Перебор таблиц 1..N (пока GetTableStruct возвращает 0)
3. Для каждой таблицы: GetFieldStruct для всех полей
4. ReadTable для каждой ячейки (row x field)
5. Сохранение в текстовый файл

Использование:
  python kkt_dump_tables.py --ip 192.168.137.111
  python kkt_dump_tables.py --ip 192.168.137.111 --output tables_dump.txt
  python kkt_dump_tables.py --ip 192.168.137.111 --tables 1,17,19,21
"""
import sys
import argparse
import datetime
from kkt_driver import setup_encoding, create_driver, safe_get, add_connection_args, connect_from_args


def dump_tables(drv, output_file, table_filter=None):
    """Считать все (или указанные) таблицы ККТ и записать в файл."""

    # Получаем информацию о ККТ для заголовка
    drv.GetDeviceMetrics()
    model = safe_get(drv, 'UDescription', '?')
    drv.GetECRStatus()
    serial = safe_get(drv, 'SerialNumber', '?')

    lines = []
    lines.append("=" * 80)
    lines.append(f"ДАМП ТАБЛИЦ ККТ")
    lines.append(f"Модель: {model}")
    lines.append(f"Серийный номер: {serial}")
    lines.append(f"Дата дампа: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("=" * 80)

    tables_read = 0
    max_tables = 100  # Ограничение поиска

    for t in range(1, max_tables + 1):
        if table_filter and t not in table_filter:
            continue

        drv.TableNumber = t
        rc = drv.GetTableStruct()
        if rc != 0:
            # Таблица не существует
            if table_filter:
                lines.append(f"\n--- Таблица {t}: НЕ СУЩЕСТВУЕТ (код {rc}) ---")
            continue

        table_name = safe_get(drv, 'TableName', f'Table_{t}')
        num_rows = safe_get(drv, 'RowNumber', 0)
        num_fields = safe_get(drv, 'FieldNumber', 0)

        if num_rows == 0 or num_fields == 0:
            lines.append(f"\n--- Таблица {t}: {table_name} (пустая: {num_rows} рядов, {num_fields} полей) ---")
            tables_read += 1
            continue

        lines.append(f"\n{'=' * 80}")
        lines.append(f"Таблица {t}: {table_name}")
        lines.append(f"Рядов: {num_rows}, Полей: {num_fields}")
        lines.append("-" * 80)

        # Считываем структуру полей
        fields = []
        for f in range(1, num_fields + 1):
            drv.TableNumber = t
            drv.FieldNumber = f
            rc = drv.GetFieldStruct()
            if rc != 0:
                fields.append({'num': f, 'name': f'Field{f}', 'type': '?', 'size': 0})
                continue
            fname = safe_get(drv, 'FieldName', f'Field{f}')
            ftype = safe_get(drv, 'FieldType', False)  # True=string, False=int
            fsize = safe_get(drv, 'FieldSize', 0)
            fields.append({
                'num': f,
                'name': fname,
                'type': 'String' if ftype else 'Int',
                'size': fsize
            })

        # Заголовок полей
        header = "Row | "
        header += " | ".join([f"{fl['name']}({fl['type']},{fl['size']})" for fl in fields])
        lines.append(header)
        lines.append("-" * len(header))

        # Считываем данные
        for row in range(1, num_rows + 1):
            values = []
            for fl in fields:
                drv.TableNumber = t
                drv.RowNumber = row
                drv.FieldNumber = fl['num']
                rc = drv.ReadTable()
                if rc != 0:
                    values.append(f"ERR:{rc}")
                    continue
                if fl['type'] == 'String':
                    val = safe_get(drv, 'ValueOfFieldString', '')
                    values.append(f'"{val}"')
                else:
                    val = safe_get(drv, 'ValueOfFieldInteger', 0)
                    values.append(str(val))

            row_line = f"{row:3d} | " + " | ".join(values)
            lines.append(row_line)

        tables_read += 1
        print(f"  Таблица {t}: {table_name} ({num_rows}x{num_fields}) - OK")

    lines.append(f"\n{'=' * 80}")
    lines.append(f"Итого таблиц: {tables_read}")
    lines.append("=" * 80)

    # Запись в файл
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"\nДамп сохранён: {output_file} ({tables_read} таблиц)")


if __name__ == "__main__":
    setup_encoding()
    parser = argparse.ArgumentParser(description="KKT Table Dump - считывание всех таблиц ККТ")
    add_connection_args(parser)
    parser.add_argument("--output", "-o", default=None,
                        help="Имя выходного файла (default: tables_<serial>.txt)")
    parser.add_argument("--tables", "-t", default=None,
                        help="Номера таблиц через запятую, например: 1,17,19,21")
    args = parser.parse_args()

    # Фильтр таблиц
    table_filter = None
    if args.tables:
        table_filter = set(int(x.strip()) for x in args.tables.split(','))

    drv = create_driver()
    drv.Password = 30
    drv.SysAdminPassword = 30

    # Подключение
    if not connect_from_args(drv, args):
        sys.exit(1)
    print("Подключено.\n")

    # Определяем имя файла
    if args.output:
        output_file = args.output
    else:
        drv.GetECRStatus()
        serial = safe_get(drv, 'SerialNumber', 'unknown')
        output_file = f"tables_{serial}.txt"

    print(f"Считывание таблиц...")
    dump_tables(drv, output_file, table_filter)

    drv.Disconnect()
    print("Готово.")
