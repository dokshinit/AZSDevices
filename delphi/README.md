# AZSDevices (Delphi 7.0)

Возможно, кому-то пригодится реализация прямого управления банковским терминалом Сбербанк, ККМ, ТРК.
Ключевой "фишкой" тут является отсутствие необходимости устанавливать драйвера или софт от
производителя - модули работают с устройствами напрямую через порт по низкоуровневому протоколу!

Разрабатывалось и тестировалось с пинпадом Сбербанка "Verifone VX 820" с 19 прошивкой,
ККМ Штрих-Комбо/Штрих-Мини, ККМ Атол, ТРК Топаз/Нара с блоками управления Топаз
(на платформе: Windows XP x86 sp1).

## Модули Delphi проекта АРМ АЗС.
Вспомогательные модули:
* dant_utils.pas - общие вспомогательные функции.
* dant_crc.pas - функции вычисления контрольных сумм.
* dant_log.pas - логирование.
* dant_sync.pas - функции синхроницации.
* dant_utf8.pas - кодирование/декодирование UTF8 строк.
* dant_base64.pas - base64 кодирование/декодирование.
* dant_TimeoutUtils.pas - таймауты.

Парсинг и формирование:
* dant_DataBuffer.pas - вариант буфера данных для удобного формирования/парсинга данных.

Последовательный порт:
* jsscex.pas - реализация библиотеки jSSC 2.8.0 с доработками под проект.
* windows_jSSC-Ex-2.9_x86.dll - версия библиотеки jSSC 2.8.0 с доработками под проект.
* dant_SerialPort.pas - последовательный порт.
* dant_RS232Driver.pas - драйвер последовательного порта.

Прямое управление устройствами:
* dant_AtolFRDevice.pas - драйвер устройства "ККМ Атол по протоколу Атол 3.1 (нижний уровент v2)".
* dant_MSRCardReader.pas - драйвер устройства "Ридер магнитных карт MSR (в разрыв клавиатуры)".
* dant_SBPinpadDevice.pas - драйвер устройства "Банковский терминал (пинпад) Сбербанка по протоколу UPOS".
* dant_ShtrihFRDevice.pas - драйвер устройства "ККМ по протоколу Штрих".
* dant_TopazFDDevice.pas - драйвер устройства "ТРК Топаз по протоколу АЗТ 2.0".

Работа через сеть:
* dant_NetSocket.pas - работа с сокетами.
* dant_NetUDPClient.pas - работа с сетью по протоколу UDP.
* dant_RCClient.pas - клиент удаленного управления.
* dant_SBPinpadRCClient.pas - клиент удаленного управления термиалом Сбербанка.

Ввиду того, что проект больше не используется - выложен для истории.
