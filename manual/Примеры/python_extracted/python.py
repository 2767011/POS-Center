# -*- coding: utf-8 -*-
from __future__ import print_function
import win32com.client as win32
import sys
import json

"""
Адаптер нативного windows-драйвера ККМ Штрих-М, через COM-объект 
"""

device = None
settings = {
    'password': '30',
    'admin_password': '30',
}

connection_types = {
    0: u'Локально',
    1: u'Сервер ККМ (TCP)',
    2: u'Сервер ККМ (DCOM)',
    3: u'ESCAPE',
    4: u'unknown-4',  # Не используется
    5: u'Эмулятор',
    6: u'Подключение через ТСР-сокет',
}
ecr_modes = {
    0: u'Принтер в рабочем режиме',
    1: u'Выдача данных',
    2: u'Открытая смена, 24 часа не кончились',
    3: u'Открытая смена, 24 часа кончились',
    4: u'Закрытая смена',
    5: u'Блокировка по неправильному паролю налогового инспектора',
    6: u'Ожидание подтверждения ввода даты',
    7: u'Разрешение изменения положения десятичной точки',
    8: u'Открытый документ',
    9: u'Режим разрешения технологического обнуления',
    10: u'Тестовый прогон',
    11: u'Печать полного фискального отчета',
    12: u'Печать длинного отчета ЭКЛЗ',
    13: u'Работа с фискальным подкладным документом',
    14: u'Печать подкладного документа',
    15: u'Фискальный подкладной документ сформирован',
}

import codecs, sys
reload(sys)
sys.setdefaultencoding('utf-8')
sys.stdout = codecs.getwriter('utf8')(sys.stdout)
sys.stderr = codecs.getwriter('utf8')(sys.stderr)


# печать в stderr (попадает в лог tray_proxy)
def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)
    sys.stderr.flush()


def next_command():
    buf = ""
    dec = json.JSONDecoder()
    while True:
        try:
            line = raw_input()
        except EOFError:
            break
        line = line.strip()
        buf = buf + line
        while len(buf) > 0:
            try:
                r = dec.raw_decode(buf)
            except Exception as e:
                break
            yield r[0]
            buf = buf[r[1]+1:]


def _send_kassir_name(args):
    if 'operator_name' in args:
        device.TagNumber = 1021
        device.TagType = 7  # string
        device.TagValueStr = args['operator_name']
        device.FNSendTag()
    # TODO: тег 1203 (ИНН кассира)


def _print_check(args, is_storno):
    # готовим данные
    op_summa = float(args['op_summa'])
    is_cash = bool(args['is_cash'])
    descr = args['descr']
    other_text = args.get('other_text', None)
    # открываем чек нужной операции
    device.CheckType = 2 if is_storno else 0  # 0-приход 1-расход 2-возврат прихода 3-возврат расхода
    device.OpenCheck()
    if not check_result(print_ok=False):
        return
    device.UseReceiptRibbon = True
    device.UseJournalRibbon = False
    _send_kassir_name(args)
    if not check_result(print_ok=False):
        return
    # добавляем позицию
    device.StringForPrinting = descr
    device.Price = op_summa
    device.Quantity = 1
    device.Summ1Enabled = True
    device.Summ1 = op_summa
    device.TaxValueEnabled = False
    device.PaymentTypeSign = 3  # ПризнакСпособаРасчета = Аванс
    device.PaymentItemSign = 10  # ПризнакПредметаРасчета = Платеж
    device.FNOperation()
    if not check_result(print_ok=False):
        return
    # печатаем прочую информацию
    if other_text:
        _do_print_text(other_text)
        if not check_result(print_ok=False):
            return
    # закрываем чек с нужным способом оплаты
    if is_cash:
        device.Summ1 = op_summa
    else:
        device.Summ4 = op_summa
    device.FNCloseCheckEx()
    if not check_result(print_ok=False):
        return
    fa = device.FiscalSignAsString
    fdn = device.DocumentNumber
    print(json.dumps({'status': 'ok', 'fiscal_attribute': fa, 'fiscal_dn': fdn}))


# проверка результата выполнения команды, с выводом ошибки
def check_result(die=False, print_ok=False):
    if 0 == device.ResultCode:
        if print_ok:
            print(json.dumps({'status': 'ok'}))
        return True
    errstr = u"[{}] {}".format(device.ResultCode, device.ResultCodeDescription)
    eprint(u"Operation error: {}".format(errstr))
    print(json.dumps({'error': errstr}))
    if die:
        sys.stdout.flush()
        exit(2)
    return False


# попытка (пере)открытия смены
def _try_open_shift(args, force=False):
    if 2 == device.ECRMode:
        # смена уже открыта и не кончилась
        return True
    if 3 == device.ECRMode:
        # переоткрываем закончившуюся смену
        if not force and args.get('only_manual_shift_open'):
            print(json.dumps({'error': u'Смена превысила 24 часа. Необходимо закрыть её и открыть снова'}))
            return False
        else:
            device.FNCloseSession()
            if not check_result(print_ok=False):
                return False
            device.GetShortECRStatus()
    # открыть смену можем только из состояния закрытой смены
    if 4 != device.ECRMode:
        err_str = u'Неверный режим ККМ: [{}] {}'.format(device.ECRMode, ecr_modes.get(device.ECRMode, '-unknown-'))
        print(json.dumps({'error': err_str}))
        return False
    # открываем смену
    device.FNBeginOpenSession()
    if not check_result(print_ok=False):
        return False
    _send_kassir_name(args)
    if not check_result(print_ok=False):
        return False
    device.FNOpenSession()
    if not check_result(print_ok=False):
        return False
    return True


# проверка текущего режима ккм
def _check_ecr_mode(allowed_modes, invert=False):
    if 0 != device.GetShortECRStatus():  # есть аппараты, не умеющие отдавать короткий статус
        if 0 != device.GetECRStatus():
            check_result(die=True)
    res = device.ECRMode in allowed_modes
    if invert:
        res = not res
    if not res:
        msg = u'Неверный режим ККМ: [{}] {}'.format(device.ECRMode, ecr_modes.get(device.ECRMode, '-unknown-'))
        print(json.dumps({'error': msg}))
    return res


def _do_print_text(text):
    for s in text.splitlines():
        if '~S' == s:
            device.FeedAfterCut = False
            device.CutType = True  # неполная отрезка
            device.CutCheck()
        else:
            device.StringForPrinting = s.rstrip()
            device.UseReceiptRibbon = True
            device.UseJournalRibbon = False
            device.PrintString()


# TODO GetShortECRStatus ??
if __name__ == '__main__':
    for _cmd in next_command():
        cmd = _cmd.get('cmd')
        args = _cmd.get('args', {})

        # Инициализация обработчика (команда от самого TrayProxy)
        if 'init' == cmd:
            """
            TODO: реализовать выбор устройства (сейчас используется девайс по умолчанию)  
            1) get list of logical devices
            2) die if no devices
            3) inform if >1
            4) connect to args.get('device_num', 0) device
            """
            settings.update(args)
            device = win32.gencache.EnsureDispatch('Addin.DRvFR')
            if not device:
                print(json.dumps({'error': 'Can\'t load COM object Addin.DRvFR of native driver'}))
                exit(1)
            device.SysAdminPassword = settings['admin_password']
            device.Password = settings['password']
            device.Connect()
            check_result(die=True)
            device.GetDeviceMetrics()
            ct = connection_types.get(device.ConnectionType, '-error-')
            device.GetShortECRStatus()
            print(json.dumps({'status': 'ok', 'connection': ct, 'dev_info': device.UDescription, 'mode': device.ECRMode}))
            sys.stdout.flush()
            continue
        else:
            # для прочих команд применяем общие настройки
            if 'password_admin' in args:
                device.SysAdminPassword = args['password_admin']
            if 'password_operator' in args:
                device.Password = args['password_operator']

        # Запустить ККМ
        if 'open_device' == cmd:
            # just ping
            device.CheckConnection()
            check_result(print_ok=True)

        # Открыть смену
        elif 'open_shift' == cmd:
            if _try_open_shift(args, force=True):
                print(json.dumps({'status': 'ok'}))

        # Создать чек прихода
        elif 'print_check_for_op' == cmd:
            if _try_open_shift(args):
                _print_check(args, False)
                device.WaitForPrinting()

        # Создать чек возврата прихода
        elif 'print_storno_check_for_op' == cmd:
            if _try_open_shift(args):
                _print_check(args, True)
                device.WaitForPrinting()

        # внесение наличных в кассу
        elif 'introduction_cash' == cmd:
            if _check_ecr_mode((2, 3, 4, 7,9,)) and _try_open_shift(args):
                summ = int(args['summ'])
                if summ > 0:
                    if _try_open_shift(args):
                        device.CashIncome(summ/100)
                        check_result(print_ok=True)
                else:
                    print(json.dumps({'error': u'Сумма не может быть ниже нуля'}))

        # выемка наличных из кассы
        elif 'withdrawal_cash' == cmd:
            if _check_ecr_mode((2, 3, 4, 7,9,)) and _try_open_shift(args):
                summ = int(args['summ'])
                if summ > 0:
                    if _try_open_shift(args):
                        device.CashOutcome(summ/100)
                        check_result(print_ok=True)
                else:
                    print(json.dumps({'error': u'Сумма не может быть ниже нуля'}))

        # Z-отчет / Отчет с гашением
        elif 'close_cash_shift' == cmd:
            if _check_ecr_mode((2, 3,)):  # смена должна быть открыта
                device.FNBeginCloseSession()
                if check_result(print_ok=False):
                    _send_kassir_name(args)
                    if check_result(print_ok=False):
                        device.PrintReportWithCleaning()
                        if check_result(print_ok=False):
                            device.WaitForPrinting()
                            check_result(print_ok=True)

        # X-отчет / Отчет без гашения TODO: kassir_name
        elif 'simple_report' == cmd:
            if _check_ecr_mode((2, 3, 4)):
                _send_kassir_name(args)
                device.PrintReportWithoutCleaning()
                if check_result(print_ok=False):
                    device.WaitForPrinting()
                    check_result(print_ok=True)

        # Печать произвольного текста
        elif 'print_text' == cmd:
            if _check_ecr_mode((11, 12, 14), invert=True):
                device.BeginDocument()  # включение буферизации команд
                text = args['text']
                _do_print_text(text)
                device.FinishDocumentMode = 0
                device.FinishDocument()
                device.EndDocument()  # выключение буферизации команд
                device.WaitForPrinting()
                check_result(print_ok=True)

        # повтор печати последнего документа
        elif 'reprint_last_doc' == cmd:
            device.RepeatDocument()
            if check_result(print_ok=False):
                device.WaitForPrinting()
                check_result(print_ok=True)

        else:
            print(json.dumps({'error': u'Unsupported command {}'.format(cmd)}))

        sys.stdout.flush()
    if device:
        device.disconnect()
    eprint("Driver exited")
