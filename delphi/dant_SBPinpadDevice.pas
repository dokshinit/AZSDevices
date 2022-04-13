////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_SBPinpadDevice;

interface

uses
  Windows, WinSock,
  SysUtils, dant_utils, dant_log, dant_crc, dant_sync, dant_DataBuffer, dant_RS232Driver;

//  "SberBank Pinpad Device" Драйвер для управления пинпадом СБЕРБАНК по новому протоколу UPOS.
//  Разрабатывалось и тестировалось с пинпадом "Verifone VX 820".
//
//  0. Физический уровень RS232:
//     {маркер начала}[1] + {'#'}[1] + {base64 данные}[K] + {маркер конца}[1]
//
//     Блок base64 декодируется и результат содержит данные транспортного уровня.
//
//  1. Транспортный уровень:
//     {Номер фрагмента+флаг незавершенности}[1] + {длина данных}[1] + {данные}[M] + {crc16}[2].
//
//     Требует подтверждения получения\передачи данных или промежуточного подтверждения, при
//     фрагментации данных уровня команды (отправка\получение по частям - когда размер данных для
//     транспортировки превышает максимально возможный).
//
//  2. Уровень команды:
//     {код команды\ответа}[1] + {длина данных}[2] + {idsync+флаг ответа}[4] + {данные}[N]
//
//     В ответ на команду требует ответ (команда). У команды и ответа должны совпадать младшие 31 бит
//     idsync, последний бит - индикатор ответа (0-команда, 1-ответ).
//     У ответа в коде команды передаётся результат выполнения команды, 0 - успех, иначе код ошибки.
//     Если код ошибки = $E и длина данных = 2, то расширенный результат в данных (2 байта).
//
//  3. Уровень управления (Команда = $A0: CMD_MASTERCALL):
//     {код инструкции}[1] + {код устройства}[1] + {0x00}[1] + {длина данных}[2] + {данные}[N-5]
//
//     В ответ на команду требует ответ (команду того же уровня). В отличии от других команд - эта
//     двусторонняя, т.е. команду может подавать как ПК, так и терминал.
//     Используется для связи терминала с ПЦ через ПК и для "печати" чеков терминалом на ПК.

type

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Исключения.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Общее исключение для TSBPinpadDevice.
  TExSBPinpadDevice = class(TExError);
  // Ошибка при построении команды\результата.
  TExBuilding = class(TExSBPinpadDevice);
  // Неверная контрольная сумма.
  TExCRC = class(TExSBPinpadDevice);
  // При отказе терминала от переданного транспортного пакета.
  TExNAK = class(TExSBPinpadDevice);

  // Прочие ошибки.
  TExOtherError = class(TExSBPinpadDevice);
  // Ошибки при неверных физических данных.
  TExProtocol = class(TExSBPinpadDevice);
  // Ответ с ненулевым кодом ошибки.
  TExResultCode = class(TExSBPinpadDevice);
  // Ошибка структуры данных (в заголовке команды или субкоманды).
  TExStructure = class(TExSBPinpadDevice);
  // Неверная команда ответа.
  TExWrongAnswer = class(TExSBPinpadDevice);

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Метаданные команды первого уровня.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TMeta = class
    public
      cmdID: int;
      syncID: int;
      isAnswer: boolean;
      dataLength: int;
      extResultCode: int; // Расширенный результат. Только для ответа, при cmdID = $E.

      constructor Create();
      function setup(cmdid, datalength, syncid: int; isanswer: boolean; extresultcode: int): TMeta;
      function getResultCode(): int;
      procedure setResultCode(code, extcode: int);

      class function getMetaLength(): int;
      function getDataLength(): int;
      procedure setDataLength(datalength: int);

      function getRawLength(): int;
      class function setAreaToMeta(const buf: TDataBuffer): TDataBuffer;
      function setAreaToData(const buf: TDataBuffer): TDataBuffer;
      function setAreaToRAW(const buf: TDataBuffer): TDataBuffer;

      function setAsCmd(cmdid, datalength, extresultcode: int): TMeta;
      function setAsAnswer(const meta: TMeta; errid, dataLength: int): TMeta; overload;
      function setAsAnswer(): TMeta; overload;

      class function metaTo(const meta: TMeta; const raw: TDataBuffer): TMeta; overload;
      function metaTo(const raw: TDataBuffer): TMeta; overload; virtual;
      class function metaFrom(const meta: TMeta; const raw: TDataBuffer; size: int): TMeta; overload;
      function metaFrom(const raw: TDataBuffer; size: int): TMeta; overload; virtual;

      class function command(const cmdid, datalength: int): TMeta;
      class function answer(): TMeta; overload;
      class function answer(const meta: TMeta; errid, datalength: int): TMeta; overload;

      class function cidCMD(id: int; isanswer: boolean): string; overload;
      function cidCMD(): string; overload;
  end;


  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Метаданные команды второго уровня: 0xA0 (CMD_MASTERCALL). Управление устройствами МА или УК.
  //  Расширяет метаданные команды первого уровня!
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TMCMeta = class(TMeta)
    public
      mcDevType: int;
      mcOpType: int;
      mcDataLength: int;

      constructor Create();
      function setup(devtype, optype, datalength: int): TMCMeta;
      function getMCDataLength(): int;
      procedure setMCDataLength(datalength: int);
      procedure setDataLength(datalength: int);

      class function getMCMetaOffset(): int;
      class function getMCMetaLength(): int;
      class function getMCDataOffset(): int;

      function getMCRawLength(): int;
      class function setAreaToMCMeta(const buf: TDataBuffer): TDataBuffer;
      function setAreaToMCData(const buf: TDataBuffer): TDataBuffer;
      function setAreaToMCRAW(const buf: TDataBuffer): TDataBuffer;

      function setAsCmd(cmdid, datalength, extresultcode: int): TMCMeta;
      function setAsAnswer(const req: TMCMeta; errid, datalength: int): TMCMeta; overload;
      function setAsAnswer(): TMCMeta; overload;

      class function metaTo(const mc: TMCMeta; const raw: TDataBuffer): TMCMeta; overload;
      function metaTo(const raw: TDataBuffer): TMeta; overload; override;
      class function metaFrom(const mc: TMCMeta; const raw: TDataBuffer; size: int): TMCMeta; overload;
      function metaFrom(const raw: TDataBuffer; size: int): TMeta; overload; override;

      class function command(devtype, optype, dataLength: int): TMCMeta;
      class function answer(): TMCMeta; overload;
      class function answer(const mc: TMCMeta; errid, datalength: int): TMCMeta; overload;

      class function cidDEV(id: int): string; overload;
      function cidDEV(): string; overload;
      class function cidOP(id: int): string; overload;
      function cidOP(): string; overload;
  end;


  TSBPrinterTextLine = record
    mode: int;
    text: string;
  end;

  TSBPrinterText = array of TSBPrinterTextLine;

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Данные команды CMD_TRANSACTION.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TTRCommand = class
    public
      amount: int; // [4] сумма в копейках
      cardType: int; // [1] тип карты = 0 - авто
      currencyType: int; // [1] валюта = 0
      opType: int; // [1] тип операции: TR_XXX
      track2: string; // [40] вторая дорожка, Если первый символ 'E', то остальное - HEX!!!
      requestID: int; // [4] cmdID запроса (<0)
      RRN: string; //[12+1]
      flags: int; // [4]
      //public int extraData; // [MAX_PILOT_EXTRA] - не будет использоваться?!
      //ber-tlv coded buffer. len in first byte.
      //in T_Message translate only signefed part of ExtraData (ExtraData[0])

      constructor Create(amount, optype: int);

      class function cidOP(id: int): string; overload;
      function cidOP(): string; overload;
  end;


  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Данные результата выполнения команды CMD_TRANSACTION.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TTRResult = class // в 16.0 размер = $9F.
    public
      resultCode: int; // [2] =0 - платеж выполнен, иначе - код ошибки.
      authCode: string; // [6+1]
      RRN: string; // [12+1]
      opNumber: string; // [4+1]
      cardNumber: string; // [19+1]
      cardExpire: string; // [5+1]
      messageText: string; // [32]
      date: int; // [4]
      time: int; // [4]
      isSberbankCard: int; // [1]
      terminalNumber: string; // [8+1]
      cardName: string; // [16]
      merchantID: string; // [12]
      spasiboAmt: int; // [4]
      SHA1: string; // [20] HEX
      encryptedData: string; // [32] HEX Зашифрованные данные карты (в 19.0 размер = $BF).
      cardID: string; // [1] (в 24.0 размер = $D3)
      requestID: int; // [4] Есть только если в запросе был requestID < 0.
      // Остальные поля только если в ответе есть RequestID и он меньше ноля.
      res2: string; // [19] (в 24.0 размер = $D3)

      // Конструктор. Считывание данных из буфера с текущей позиции.
      constructor Create(const buf: TDataBuffer);
      function parse(const buf: TDataBuffer): TDataBuffer;
      function build(const buf: TDataBuffer): TDataBuffer;
  end;



  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Устройство-пинпад СБ.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TSBPinpadDevice = class
    private
      // Коммуникационный драйвер.
      driver: TRS232Driver;
      // Имя устройства (для логов).
      devname: String;

      // Таймаут получения каждого байта (100 мсек.).
      transportTimeout: int;
      // Таймаут получения подтверждения об отправке на транспортном уровне (300 мсек.).
      transportConfirmationTimeout: int; // = 300;
      // Таймаут получения первого байта ответа на команду (35 сек.).
      answerTimeout: int; // = 35000;
      // Кодировка для текстовых данных команд.
      //charset: Charset;

      // Временный буфер для формирования фреймов транспортного (физического) уровня.
      tmpbuffer: TByteArray;
      // Буфер для кодирования\декодирования base64 данных.
      base64buffer: TByteArray;

      // Буфер для передаваемых команд. Рабочее окно на весь буфер - длина команды определяется метаданными.
      outcmdbuffer: TDataBuffer;
      // Буфер для принимаемых команд. Рабочее окно на весь буфер - длина команды определяется метаданными.
      incmdbuffer: TDataBuffer;

      // Последний сгенерированный ID команды.
      lastCommandID: int;

      // LAN
      lanSocket: TSocket;
      // PRINTER
      printerMode: int;
      printerText: TSBPrinterText;
      printerTextSize: int;
      // REBOOT
      rebootTimeout: int; // 0 - не выставлен.

      syncLock: TCriticalSectionExt;
      
    public  
      isPortLogging, isCmdLogging, isMCLogging, isTRLogging: boolean;

    public
      constructor Create(const devname: String; const portname: string);
      destructor Destroy(); override;
      function getDriver(): TRS232Driver;
      function getDeviceName(): String;
      procedure open();
      function  openSafe(): boolean;
      procedure closeSafe();
      procedure createNewPort();

      function TryLock(): boolean;
      procedure Lock();
      procedure Unlock();

      function cmd_GetReady(devanswertimeout: int = -1): String;
      function cmd_CardTest(devanswertimeout: int = -1): int;

      procedure cmd_MC_Display(row: int; const text: string; devanswertimeout: int = -1);
      procedure cmd_MC_DisplayCls(devanswertimeout: int = -1);
      procedure cmd_MC_DisplayFmt(row: int; const fmt: string; const args: array of const; devanswertimeout: int = -1);
      procedure cmd_MC_Beep(mode: int; devanswertimeout: int = -1);

      function getLastPrintedMode(): int;
      procedure clearLastPrintedText();
      function getLastPrintedText(): TSBPrinterText;
      function getLastPrintedTextAsString(): string;

      function cmd_TR_CloseSession(): TTRResult;
      function cmd_TR_Totals(mode: int): TTRResult;
      function cmd_TR_Help(): TTRResult;
      function cmd_TR_ServiceMenu(): TTRResult;

      function cmd_TR_Purchase(amount: int): TTRResult;
      function cmd_TR_Refund(amount: int; const rrn, hexencdata: string): TTRResult;
      function cmd_TR_Cancel(amount: int; const rrn, hexencdata: string): TTRResult;

    protected
      procedure fireOnMCPrintOpen(mode: int); virtual;
      procedure fireOnMCPrintWrite(var line: TSBPrinterTextLine); virtual;
      procedure fireOnMCPrintClose(mode: int; var text: TSBPrinterText; linecount: int); virtual;
      procedure fireOnTRStart(const meta: TTRCommand); virtual;
      procedure fireOnTRFinish(const meta: TTRCommand; const res: TTRResult; const errmsg: string = ''); virtual;

    private
      procedure dropReadSafe();
      procedure write(const buffer: TByteArray; len: int);
      function read(const buffer: TByteArray; devanswertimeout: int): int;

      procedure sendCmd(const meta: TMeta);
      procedure receiveCmd(const meta: TMeta; devanswertimeout: int; isloglater: boolean = false);
      procedure testAnswer(const req: TMeta; const answ: TMeta; ischeckresult: boolean = false);
      function generateCommandID(): int;

      procedure execute_MasterCall(const mc: TMCMeta);
      function cmd_MasterCall(const mc: TMCMeta; devanswertimeout: int = -1): TMCMeta;
      function cmd_Transaction(const meta: TTRCommand): TTRResult;
      function cmd_TR_Custom(amount, cmdid: int; rrn: string = ''; hexencdata: string = ''): TTRResult;
  end;

  TExWSA = class (TExError);

implementation

uses
  Math, dant_base64;


  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  ПЕРВЫЙ УРОВЕНЬ: СООБЩЕНИЯ + ТРАНСПОРТНЫЙ (фреймы) + ФИЗИЧЕСКИЙ
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Служебные байт-коды протокола.
  const STX = $02; // Начало транспортного фрейма.
  const STX2 = $23; // '#' - индикатор нового протокола.
  const ETX = $03; // Конец транспортного фрейма.
  const ACK = $04; // Подтверждение успешной передачи сообщения (все части переданы).
  const ACKEVEN = $06; // Подтверждение промежуточной передачи (четные пакеты).
  const ACKODD = $07; // Подтверждение промежуточной передачи (нечетные пакеты).
  const NAK = $15; // Подтверждение ошибки передачи.

  // Ограничение на длину данных для транспортного уровня.
  const MAX_TRANSPORT_DATASIZE = $B4;

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  ВТОРОЙ УРОВЕНЬ:  КОМАНДНЫЙ
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Типы команд первого уровня.
  const CMDID_GETREADY = $50;   // Опрос готовности МА.
  const CMDID_CARDTEST = $EF;   // Проверка наличия карты в ридере.
  const CMDID_MASTERCALL = $A0; // Управление устройствами.
  const CMDID_TRANSACTION = $6D; // Транзакция.

  // Для команды CMD_MASTERCALL: Типы исполняющих устройств.
  const MCDEV_NO = $00;
  const MCDEV_DISPLAY = $01;
  const MCDEV_KEYBOARD = $02;
  const MCDEV_PRINTER = $03;
  const MCDEV_MAGREADER = $04;
  const MCDEV_CLOCK = $05;
  const MCDEV_LAN = $19;
  const MCDEV_MENU = $1E;
  const MCDEV_INPUTLINE = $1F;
  const MCDEV_BEEPER = $20;
  const MCDEV_REBOOT = $29;

  // Для команды CMD_MASTERCALL: Типы операций.
  const MCOPER_OPEN = $01;
  const MCOPER_READ = $02;
  const MCOPER_WRITE = $03;
  const MCOPER_CLOSE = $04;

  // Типы операций в команде транзакции.
  // Торговые операции.
  const TR_PURCHASE = $01; // 0x01: Продажа.
  const TR_CASH = $02; // 0x02: Выдача наличных.
  const TR_REFUND = $03; // 0x03: Возврат платежа.
  const TR_BALANCE = $04; // 0x04: Запрос баланса.
  const TR_PAYMENT = $05; // 0x05: Оплата.
  const TR_FUNDS = $06; // 0x06: Безналичный перевод.
  const TR_CANCEL = $08; // 0x08: Отмена операции.
  const TR_ROLLBACK = $0D; // Откат последней транзакции.
  const TR_SUSPEND = $0F; // Перевод последней транзакции в подвешенное состояние.
  const TR_COMMIT = $10; // Закрепление последней транзакции.
  const TR_PRE_AUTH = $11; // 0x11: Преавторизация.
  const TR_PRE_COMPLETE = $12; // 0x12: Завершение преавторизации.

  // Регламентные операции.
  const TR_CLOSESESSION = $07; // 0x07: Закрытие смены (дня).
  const TR_TOTALS = $09; // 0x09: Отчеты (Контрольная лента, сводный). [ИЗ ИССЛЕДОВАНИЯ ПРОТОКОЛА]
  const TR_GETTLVDATA = $0A; // Чтение данных из настроек??? [Тэг]
  const TR_SERVICEMENU = $0B; // 0x0B: Вход в сервисное меню (отчеты,итоги,...). [ИЗ ИССЛЕДОВАНИЯ ПРОТОКОЛА]
  const TR_REPRINT = $0C; // 0x0C: Повтор печати последнего чека.
  const TR_READTRACK = $14; // 0x14: Чтение трека карты. [ИЗ ИССЛЕДОВАНИЯ ПРОТОКОЛА]
  const TR_SHOWSCREEN = $1B; // 0x1B: Вывод на экран пинпада экранной формы с указанным номером. [номер в amount]
  const TR_WAITCARD_ON = $1D; // 0x1D: Включить режим ожидания карты.
  const TR_WAITCARD_CHECK = $1E; // 0x1E: Проверить наличие карты в режиме ожидания карты.
  const TR_WAITCARD_OFF = $1F; // 0x1F: Выключить режим ожидания карты.
  const TR_PRINTHELP = $24; // 0x24: Распечатать чек «Помощь».

var
  WSAInited: boolean = false;
  WSAData: TWSAData;

  // Предварительное объявление процедур и функций для использования внутри модуля.
  procedure ExWSA(msg: string = ''); forward;
  procedure ExWSAIf(exp: boolean; msg: string = ''); forward;
  procedure InitWSA(); forward;
  procedure DoneWSA(); forward;
  procedure openLanSocket(var socket: TSocket; var addr: TSockAddr); forward;
  function readLanSocket(var socket: TSocket; const buffer: TDataBuffer; size: int): int; forward;
  function writeLanSocket(var socket: TSocket; const buffer: TDataBuffer; size: int): int; forward;
  procedure closeLanSocket(var socket: TSocket); forward;

  
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TMeta.Create();
begin
  setup(0, 0, 0, false, 0);
end;


function TMeta.setup(cmdid, datalength, syncid: int; isanswer: boolean; extresultcode: int): TMeta;
begin
  self.cmdID := cmdid;
  self.dataLength := datalength;
  self.syncID := syncid and $7FFFFFFF;
  self.isAnswer := isanswer;
  // Установка расширенного кода ошибки, если параметры это подразумевают - см. setResultCode().
  setResultCode(cmdid, extresultcode);
  Result := self;
end;


function TMeta.getResultCode(): int;
begin
  if (isAnswer) then
    Result := iif((cmdID = $E) and (dataLength = 2), extResultCode, cmdID)
  else
    Result := 0;
end;


procedure TMeta.setResultCode(code, extcode: int);
begin
  if (isAnswer) then
  begin
    cmdID := code; // Обычный код ошибки в коде команды.
    extResultCode := iif((code = $E) and (dataLength = 2), extcode, 0); // Если вернулся расширенный код - присваиваем.
  end else
  begin
    extResultCode := 0; // Сбрасываем расширенный код ошибки для команды.
  end;
end;


class function TMeta.getMetaLength(): int;
begin
  Result := 7;
end;


function TMeta.getDataLength(): int;
begin
  Result := dataLength;;
end;


procedure TMeta.setDataLength(datalength: int);
begin
  self.dataLength := datalength;;
end;


function TMeta.getRawLength(): int;
begin
  Result := getMetaLength() + getDataLength();
end;


class function TMeta.setAreaToMeta(const buf: TDataBuffer): TDataBuffer;
begin
  Result := buf.area(0, getMetaLength());
end;


function TMeta.setAreaToData(const buf: TDataBuffer): TDataBuffer;
begin
  Result := buf.area(getMetaLength(), getDataLength());
end;


function TMeta.setAreaToRAW(const buf: TDataBuffer): TDataBuffer;
begin
  Result := buf.area(0, getRawLength());
end;


function TMeta.setAsCmd(cmdid, datalength, extresultcode: int): TMeta;
begin
  Result := setup(cmdid, datalength, 0, false, extresultcode);
end;


function TMeta.setAsAnswer(const meta: TMeta; errid, dataLength: int): TMeta;
begin
  Result := setup(errid, dataLength, meta.syncID, true, 0);
end;


function TMeta.setAsAnswer(): TMeta;
begin
  Result := setup(0, 0, 0, true, 0);
end;


class function TMeta.metaTo(const meta: TMeta; const raw: TDataBuffer): TMeta;
begin
  // Заголовок = 7 байт.
  TMeta.setAreaToMeta(raw);
  raw.putAt(0, meta.cmdID);
  raw.putInt2At(1, meta.dataLength);
  raw.putIntAt(3, int((meta.syncID and $7FFFFFFF) or iif(meta.isAnswer, int($80000000), $00)));

  meta.setAreaToData(raw);
  // Заполняем блок данных в случае расширенной ошибки.
  if ((meta.isAnswer) and (meta.cmdID = $E) and (meta.dataLength = 2)) then raw.putInt2At(0, meta.extResultCode);
  Result := meta;
end;


function TMeta.metaTo(const raw: TDataBuffer): TMeta;
begin
  Result := TMeta.metaTo(self, raw);
end;


class function TMeta.metaFrom(const meta: TMeta; const raw: TDataBuffer; size: int): TMeta;
var
  cmdid, datalength, syncid: int;
  isanswer: boolean;
begin
  if (meta = nil) then Result := TMeta.Create() else Result := meta;
  if (size < TMeta.getMetaLength()) then
    raise TExStructure.Create('Недостаточная длина принятого сообщения! {%d < %d}', [size, TMeta.getMetaLength()]);

  TMeta.setAreaToMeta(raw);
  cmdid      := raw.getAt(0);
  datalength := raw.getInt2At(1);
  syncid     := raw.getIntAt(3);
  isanswer   := (syncid and $80000000) <> 0;
  Result.setup(cmdid, datalength, syncid and $7FFFFFFF, isanswer, 0);

  if (size <> Result.getRawLength()) then
    raise TExStructure.Create('Неверная длина сообщения! {readed=%d <> rawlen=%d}', [size, Result.getRawLength()]);

  if ((Result.syncID < 1) or (Result.syncID > 999999)) then
    raise TExStructure.Create('Номер сообщения выходит за рамки! {%d}', [Result.syncID]);

  Result.setAreaToData(raw);
  if ((cmdid = $E) and (isanswer) and (datalength = 2)) then Result.extResultCode := raw.getInt2At(0);
end;


function TMeta.metaFrom(const raw: TDataBuffer; size: int): TMeta;
begin
  Result := TMeta.metaFrom(self, raw, size);
end;


class function TMeta.command(const cmdid, datalength: int): TMeta;
begin
  Result := TMeta.Create().setAsCmd(cmdid, datalength, 0);
end;


class function TMeta.answer(): TMeta;
begin
  Result := TMeta.Create().setAsAnswer();
end;


class function TMeta.answer(const meta: TMeta; errid, datalength: int): TMeta;
begin
  Result := TMeta.Create().setAsAnswer(meta, errid, datalength);
end;


class function TMeta.cidCMD(id: int; isanswer: boolean): string;
begin
  if (not isanswer) then
  begin
    case id of
      // Типы команд первого уровня.
      CMDID_GETREADY: Result := 'GETREADY';
      CMDID_CARDTEST: Result := 'CARDTEST';
      CMDID_MASTERCALL: Result := 'MASTERCALL';
      CMDID_TRANSACTION: Result := 'TRANSACTION';
      else Result := Format('UNDEF=%02X', [id]); // Если неверный код.
    end;
  end else
  begin
    Result := Format('%02X', [id]); // Если это ответ.
  end;
end;

function TMeta.cidCMD(): string;
begin
  Result := TMeta.cidCMD(cmdID, isAnswer);
end;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TMCMeta.Create();
begin
  inherited Create();
  setup(0, 0, 0);
end;


function TMCMeta.setup(devtype, optype, datalength: int): TMCMeta;
begin
  self.mcDevType := devtype;
  self.mcOpType := optype;
  setMCDataLength(datalength);
  Result := self;
end;


function TMCMeta.getMCDataLength(): int;
begin
  Result := mcDataLength;
end;


procedure TMCMeta.setMCDataLength(datalength: int);
begin
  inherited setDataLength(datalength + TMCMeta.getMCMetaLength());
  self.mcDataLength := datalength;
end;

procedure TMCMeta.setDataLength(datalength: int);
begin
  inherited setDataLength(datalength);
  self.mcDataLength := datalength - TMCMeta.getMCMetaLength();
end;


class function TMCMeta.getMCMetaOffset(): int;
begin
  Result := getMetaLength();
end;


class function TMCMeta.getMCMetaLength(): int;
begin
  Result := 5;
end;


class function TMCMeta.getMCDataOffset(): int;
begin
  Result := getMCMetaOffset() + getMCMetaLength();
end;


function TMCMeta.getMCRawLength(): int;
begin
  Result := getMCMetaLength() + getMCDataLength();
end;


class function TMCMeta.setAreaToMCMeta(const buf: TDataBuffer): TDataBuffer;
begin
  Result := buf.area(getMCMetaOffset(), getMCMetaLength());
end;


function TMCMeta.setAreaToMCData(const buf: TDataBuffer): TDataBuffer;
begin
  Result := buf.area(getMCDataOffset(), getMCDataLength());
end;


function TMCMeta.setAreaToMCRAW(const buf: TDataBuffer): TDataBuffer;
begin
  Result := buf.area(getMCMetaOffset(), getMCRawLength());
end;

function TMCMeta.setAsCmd(cmdid, datalength, extresultcode: int): TMCMeta;
begin
  inherited setAsCmd(CMDID_MASTERCALL, 0, 0);
  Result := setup(cmdid, datalength, extresultcode);
end;


function TMCMeta.setAsAnswer(const req: TMCMeta; errid, datalength: int): TMCMeta;
begin
  inherited setAsAnswer(req, errid, 0);
  Result := setup(req.mcDevType, req.mcOpType, datalength);
end;


function TMCMeta.setAsAnswer(): TMCMeta;
begin
  inherited setAsAnswer();
  Result := setup(0, 0, 0);
end;


class function TMCMeta.metaTo(const mc: TMCMeta; const raw: TDataBuffer): TMCMeta;
begin
  // Заголовок команды = 7 байт.
  TMeta.metaTo(mc, raw);

  // Заголовок = 5 байт.
  TMCMeta.setAreaToMCMeta(raw);
  raw.putAt(0, mc.mcOpType);
  raw.putAt(1, mc.mcDevType);
  raw.putAt(2, 0); // резерв.
  raw.putInt2At(3, mc.mcDataLength);

  mc.setAreaToMCData(raw);
  Result := mc;
end;


function TMCMeta.metaTo(const raw: TDataBuffer): TMeta;
begin
  Result := TMCMeta.metaTo(self, raw);
end;


class function TMCMeta.metaFrom(const mc: TMCMeta; const raw: TDataBuffer; size: int): TMCMeta;
begin
  if (mc = nil) then Result := TMCMeta.Create() else Result := mc;
  // Заголовок команды = 7 байт.
  TMeta.metaFrom(Result, raw, size);
  if (size < TMCMeta.getMCDataOffset()) then
    raise TExStructure.Create('Недостаточная длина принятого сообщения! {%d < %d}',
                              [size, TMCMeta.getMCDataOffset()]);
  // Заголовок = 5 байт.
  TMCMeta.setAreaToMCMeta(raw);
  Result.setup(raw.getAt(1), raw.getAt(0), raw.getInt2At(3));
  if (size <> TMCMeta.getMCDataOffset() + Result.getMCDataLength()) then
    raise TExStructure.Create('Неверная длина сообщения! {readed=%d <> rawlen=%d}',
                              [size, TMCMeta.getMCDataOffset() + Result.getMCDataLength()]);
  Result.setAreaToMCData(raw);
end;


function TMCMeta.metaFrom(const raw: TDataBuffer; size: int): TMeta;
begin
  Result := TMCMeta.metaFrom(self, raw, size);
end;


class function TMCMeta.command(devtype, optype, dataLength: int): TMCMeta;
begin
  Result := TMCMeta.Create().setAsCmd(devtype, optype, dataLength);
end;


class function TMCMeta.answer(): TMCMeta;
begin
  Result := TMCMeta.Create().setAsAnswer();
end;


class function TMCMeta.answer(const mc: TMCMeta; errid, datalength: int): TMCMeta;
begin
  Result := TMCMeta.Create().setAsAnswer(mc, errid, datalength);
end;


class function TMCMeta.cidDEV(id: int): string;
begin
  case id of
    MCDEV_NO: Result := 'NO';
    MCDEV_DISPLAY: Result := 'DISPLAY';
    MCDEV_KEYBOARD: Result := 'KEYBOARD';
    MCDEV_PRINTER: Result := 'PRINTER';
    MCDEV_MAGREADER: Result := 'MAGREADER';
    MCDEV_CLOCK: Result := 'CLOCK';
    MCDEV_LAN: Result := 'LAN';
    MCDEV_MENU: Result := 'MENU';
    MCDEV_INPUTLINE: Result := 'INPUTLINE';
    MCDEV_BEEPER: Result := 'BEEPER';
    MCDEV_REBOOT: Result := 'REBOOT';
    else Result := Format('UNDEF=%02X', [id]); // Если неверный код.
  end;
end;


function TMCMeta.cidDEV(): string;
begin
  Result := TMCMeta.cidDEV(mcDevType);
end;


class function TMCMeta.cidOP(id: int): string;
begin
  case id of
    MCOPER_OPEN: Result := 'OPEN';
    MCOPER_READ: Result := 'READ';
    MCOPER_WRITE: Result := 'WRITE';
    MCOPER_CLOSE: Result := 'CLOSE';
    else Result := Format('UNDEF=%02X', [id]); // Если неверный код.
  end;
end;


function TMCMeta.cidOP(): string;
begin
  Result := TMCMeta.cidOP(mcOpType);
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Данные команды CMD_TRANSACTION.
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TTRCommand.Create(amount, optype: int);
begin
  self.amount       := amount;
  self.cardType     := 0;
  self.currencyType := 0;
  self.opType       := optype;
  self.track2       := '';
  self.requestID    := int((GetNowInMilliseconds() and $7FFFFFFF) or $80000000);
  self.RRN          := '';
  self.flags        := 0;
end;

class function TTRCommand.cidOP(id: int): string;
begin
  case id of
    TR_PURCHASE:       Result := 'PURCHASE';
    TR_CASH:           Result := 'CASH';
    TR_REFUND:         Result := 'REFUND';
    TR_BALANCE:        Result := 'BALANCE';
    TR_PAYMENT:        Result := 'PAYMENT';
    TR_FUNDS:          Result := 'FUNDS';
    TR_CANCEL:         Result := 'CANCEL';
    TR_ROLLBACK:       Result := 'ROLLBACK';
    TR_SUSPEND:        Result := 'SUSPEND';
    TR_COMMIT:         Result := 'COMMIT';
    TR_PRE_AUTH:       Result := 'AUTH';
    TR_PRE_COMPLETE:   Result := 'COMPLETE';
    TR_CLOSESESSION:   Result := 'CLOSESESSION';
    TR_TOTALS:         Result := 'TOTALS';
    TR_GETTLVDATA:     Result := 'GETTLVDATA';
    TR_SERVICEMENU:    Result := 'SERVICEMENU';
    TR_REPRINT:        Result := 'REPRINT';
    TR_READTRACK:      Result := 'READTRACK';
    TR_SHOWSCREEN:     Result := 'SHOWSCREEN';
    TR_WAITCARD_ON:    Result := 'ON';
    TR_WAITCARD_CHECK: Result := 'CHECK';
    TR_WAITCARD_OFF:   Result := 'OFF';
    TR_PRINTHELP:      Result := 'PRINTHELP';
    else               Result := Format('UNDEF=%02X', [id]); // Если неверный код.
  end;
end;


function TTRCommand.cidOP(): string;
begin
  Result := TTRCommand.cidOP(opType);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Данные результата выполнения команды CMD_TRANSACTION.
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор. Считывание данных из буфера с текущей позиции.
constructor TTRResult.Create(const buf: TDataBuffer);
begin
  parse(buf);
end;

// Чтение данных из буфера с текущей позиции и заполнение полей считанными значениями.
function TTRResult.parse(const buf: TDataBuffer): TDataBuffer;
begin
  resultCode := buf.getInt2();
  authCode   := buf.getZString(7);
  RRN        := buf.getZString(13);
  opNumber   := buf.getZString(5);
  cardNumber := buf.getZString(20);
  cardExpire := buf.getZString(6);
  messageText := buf.getZString(32);
  date       := buf.getInt();
  time       := buf.getInt();
  isSberbankCard := buf.get();
  terminalNumber := buf.getZString(9);
  cardName   := buf.getZString(16);
  merchantID := buf.getZString(12);
  spasiboAmt := buf.getInt();
  SHA1       := buf.getHex(20);
  if (buf.remaining() >= 32 + 4) then // if (len == $BF) then  v19.0
  begin
    encryptedData := buf.getHex(32);
  end else
  begin
    encryptedData := '';
  end;
  if (buf.remaining() >= 1 + 4) then // if (len == $D3) {  v24.0
  begin
    cardID := buf.getHex(1);
  end else
  begin
    cardID := '';
  end;
  requestID := buf.getInt();
  if (buf.remaining() >= 19) then  // if (len == $D3) {  v24.0
  begin
    res2 := buf.getHex(19);
  end else
  begin
    res2 := '';
  end;
  Result := buf;
end;

// Запись значений полей в буфер с текущей позиции.
function TTRResult.build(const buf: TDataBuffer): TDataBuffer;
begin
  buf.putInt2(resultCode).putZString(authCode, 7);
  buf.putZString(RRN, 13);
  buf.putZString(opNumber, 5);
  buf.putZString(cardNumber, 20);
  buf.putZString(cardExpire, 6);
  buf.putZString(messageText, 32);
  buf.putInt(date);
  buf.putInt(time);
  buf.put(isSberbankCard);
  buf.putZString(terminalNumber, 9);
  buf.putZString(cardName, 16);
  buf.putZString(merchantID, 12);
  buf.putInt(spasiboAmt);
  buf.putHex(SHA1, 20);
  if (encryptedData <> '') then buf.putHex(encryptedData, 32);
  if (cardID <> '') then buf.putHex(cardID, 1);
  buf.putInt(requestID);
  if (res2 <> '') then buf.putHex(res2, 19);
  Result := buf;
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Пинпад.
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TSBPinpadDevice.Create(const devname: string; const portname: string);
var i: int;
begin
  inherited Create();

  self.devname := devname;

  // Синхронизатор доступа. Для внешних программ.
  syncLock := TCriticalSectionExt.Create();
  syncLock.Enter();
  try
    // Временный буфер для формирования фреймов транспортного (физического) уровня.
    SetLength(tmpbuffer, 3000);
    // Буфер для кодирования\декодирования base64 данных.
    SetLength(base64buffer, 4000);

    // Буферы для команд.
    outcmdbuffer := TDataBuffer.Create(3000, CHARSET_OEM866);
    incmdbuffer  := TDataBuffer.Create(3000, CHARSET_OEM866);

    transportTimeout             := 100;
    transportConfirmationTimeout := 300;
    answerTimeout                := 35000;
    lastCommandID := (GetNowInMilliseconds() div 100) mod 999999;

    // RS232
    self.driver := TRS232Driver.Create(devname, portname).bitrate(115200).timeout(transportTimeout);

    // LAN
    lanSocket := INVALID_SOCKET;
    // PRINTER
    printerMode := 0;
    SetLength(printerText, 100);
    clearLastPrintedText();
    // REBOOT
    rebootTimeout := 0; // 0 - не выставлен.

    isPortLogging := false;
    isCmdLogging := false;
    isMCLogging := false;
    isTRLogging := false;
  finally
    syncLock.Leave();
  end;
end;


destructor TSBPinpadDevice.Destroy();
begin
  syncLock.Enter();
  try
    closeSafe();

    FreeAndNilSafe(driver);
    FreeAndNilSafe(lanSocket);
    FreeAndNilSafe(tmpbuffer);
    FreeAndNilSafe(base64buffer);
    FreeAndNilSafe(outcmdbuffer);
    FreeAndNilSafe(incmdbuffer);
    FreeAndNilSafe(printerText);
  finally
    syncLock.Leave();
  end;
  FreeAndNilSafe(syncLock);

  inherited;
end;


// Получение драйвера устройства (RS232).
function TSBPinpadDevice.getDriver(): TRS232Driver;
begin
  Result := driver;
end;


// Получение имени устройства.
function TSBPinpadDevice.getDeviceName(): String;
begin
  Result := devname;
end;


procedure TSBPinpadDevice.open();
begin
  driver.open();
end;


function TSBPinpadDevice.openSafe(): boolean;
begin
  try
    driver.open();
    Result := true;
  except
    Result := false;
  end;
end;


// Метод автозавершения работы с устройством.
procedure TSBPinpadDevice.closeSafe();
begin
  // Освобождаем сокет, если не освобожден (чтобы не было утечки).
  if (lanSocket <> INVALID_SOCKET) then closeLanSocket(lanSocket);
  // Закрываем драйвер.
  if (driver <> nil) then driver.closeSafe();
end;

procedure TSBPinpadDevice.createNewPort();
begin
  driver.CreateNewPort();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Обеспечение межпотоковой синхронизации для внешних обращений.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function TSBPinpadDevice.TryLock(): boolean;
begin
  Result := syncLock.TryEnter();
end;

procedure TSBPinpadDevice.Lock();
begin
  syncLock.Enter();
end;

procedure TSBPinpadDevice.Unlock();
begin
  syncLock.Leave();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Управление на уровне низового протокола (базовый уровень).
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Выполнение отмены приёма передаваемых устройством данных. Повторяется цикл: очистка входного потока и отправка
// NAK, до тех пор пока во входной поток не перестанут поступать данные в ответ на NAK.
procedure TSBPinpadDevice.dropReadSafe();
var count: int;
begin
  try
    while (true) do
    begin
      count := driver.readAllAndDrop();
      if (isPortLogging) then logMsg('dropReadSafe(): %d bytes', [count]);
      
      driver.write(NAK);
      // Когда нет входящих данных - цикл завершится исключением по таймауту.
      driver.read(transportConfirmationTimeout);
    end;
  except
  end;
end;


// Отправка сообщения (с формированием транспортного фрейма (или фреймов, если в один не помещается)).
//            ExProtocol, ExBuilding, ExNAK, ExOtherError, ExDisconnect {
procedure TSBPinpadDevice.write(const buffer: TByteArray; len: int);
var
  writed, part, attempt: int;
  notlast: boolean;
  psize, msglen, n: int;
  crc, len64, i, confirm: int;
begin
  // Команда уже подготовлена в буфере.
  writed  := 0; // Кол-во переданных байт.
  part    := 0; // Номер части (при фрагментации данных).
  attempt := 0; // Текущее кол-во ошибок передачи (подряд, при успешной передаче обнуляется).

  if (isPortLogging) then logMsg('WRITE(): BUFFER[%d]=%s', [len, BufferToHex(pbyte(buffer), 0, len)], true);

  while (writed < len) do
  begin
    try
      notlast := false;
      psize := len - writed; // остаток к передаче
      if (psize > MAX_TRANSPORT_DATASIZE) then // если остаток больше максимального размера для одной части
      begin
        psize := MAX_TRANSPORT_DATASIZE;
        notlast := true; // не последний!
      end;
      // Формируем транспортный пакет.
      msglen := 0;
      tmpbuffer[msglen] := ((part and $7F) or (iif(notlast, $80, $00)));
      tmpbuffer[msglen+1] := (psize and $FF); // Длина сообщения (контрольная сумма не включается).
      inc(msglen, 2);
      // Заполняем блок данных.
      n := copyArraySafe(buffer, writed, psize, tmpbuffer, msglen);
      if (n <> psize) then raise TExBuilding.Create('Потеря данных при копировании! {cкопировано %d из %d}', [n, psize]);
      inc(msglen, n);
      crc := CalcCRC16Sberbank(tmpbuffer, 0, msglen); // Контрольная сумма включ рассчитывается по всем данным.
      tmpbuffer[msglen] := (crc and $FF);
      tmpbuffer[msglen+1] := ((crc shr 8) and $FF);
      inc(msglen, 2);
      // Транспортный пакет сформирован.
      if (isPortLogging) then logMsg('WRITE(): -> FRAME[%d]=%s', [msglen, BufferToHex(pbyte(tmpbuffer), 0, msglen)], true);
      // На основе сформированного тела запроса формируем кодированный фрейм для передачи.
      len64 := Base64Encode(tmpbuffer, 0, msglen, base64buffer, 0);
      if (isPortLogging) then logMsg('WRITE(): -> BASE64[%d]=%s', [len64, BufferToHex(pbyte(base64buffer), 0, len64)], true);

      // Передаём маркеры начала фрейма.
      driver.write(STX);
      driver.write(STX2);
      // Передаём сообщение.
      for i := 0 to len64-1 do driver.write(base64buffer[i]);
      // Передаём маркер конца фрейма.
      driver.write(ETX);

      // Проверяем подтверждение приёма (ACK-принят, NAK-отвергнут, NEXT... - принята часть).
      confirm := driver.read(transportConfirmationTimeout);
      if (isPortLogging) then logMsg('WRITE(): <- CONFIRM=0x%.2X', [confirm], true);
      
      if (notlast) then // Если это не последняя часть, то ожидается промежуточное подтверждение.
      begin
        if (confirm = NAK) then raise TExNAK.Create();
        if (confirm <> iif((part and $1) = 0, ACKEVEN, ACKODD)) then // Некорретное подтверждение!
          raise TExProtocol.Create('Неверный маркер промежуточного подтверждения записи! {0x%02X}', [confirm]);
      end else
      begin // Если это последняя часть или единственная.
        if (confirm = NAK) then raise TExNAK.Create();
        if (confirm <> ACK) then // Некорретное подтверждение!
          raise TExProtocol.Create('Неверный маркер подтверждения записи! {0x%02X}', [confirm]);
      end;
      // Подтверждение корректное - продолжаем передачу (если есть что передавать).
      inc(writed, psize);
      inc(part);
      attempt := 0;

    except
      on ex: TExNAK do
      begin
        if (isPortLogging) then logMsg('Получен NAK!');
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExProtocol do
      begin
        if (isPortLogging) then logMsg('Ошибка протокола - %s!', [ex.Message]);
        dropReadSafe();
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExBuilding do
      begin
        if (isPortLogging) then logMsg('Ошибка протокола - %s!', [ex.Message]);
        dropReadSafe();
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExDisconnect do
      begin
        if (isPortLogging) then logMsg('Дисконнект - %s!', [ex.Message]);
        raise;
      end;
      on ex: TExDevice do
      begin
        if (isPortLogging) then logMsg('Ошибка операции - %s!', [ex.Message]);
        raise;
      end;
      on ex: Exception do
      begin
        if (isPortLogging) then logMsg('Прочая ошибка (%s) - %s!', [ex.ClassType.ClassName, ex.Message]);
        dropReadSafe();
        raise TExOtherError.Create(ex.Message);
      end;
    end;
  end;
end;


// Получение сообщения (с декодированием из транспортного пакета(ов)).
//
// @param buffer           Буфер для данных.
// @param devanswertimeout Таймаут ожидания первого байта. Если < 0, то берется таймаут по умолчанию для
//                         устройства.
// @return Кол-во считанных байт.
// throws ExProtocol, ExStructure, ExBuilding, ExCRC, ExOtherError, ExDisconnect {
function TSBPinpadDevice.read(const buffer: TByteArray; devanswertimeout: int): int;
var
  readed, part, attempt: int;
  notlast: boolean;
  value, len64: int;
  msglen, p, psize: int;
  crc, c, n, confirm: int;
begin
  // Если таймаут не задан - берем по умолчанию для этого устройства.
  if (devanswertimeout < 0) then devanswertimeout := answerTimeout;
  readed := 0; // Кол-во принятых байт.
  part := 0; // Номер части (при фрагментации данных).
  notlast := true;
  attempt := 0;
  Result := 0;

  while (notlast) do
  begin
    try
      // Чтение маркеров начала фрейма.
      while (true) do
      begin
        value := driver.read(devanswertimeout);
        if (value = STX) then break;
        devanswertimeout := -1;
        // После получения первого байта - остальные считываем с дефолтным для устройства таймаутом.
      end;
      value := driver.read();
      if (value <> STX2) then raise TExProtocol.Create('Неверный маркер нового протокола! (0x%02X)', [value]);
      // Считываем закодированный фрейм (до маркера конца фрейма).
      len64 := 0;
      while (true) do
      begin
        value := driver.read();
        if (value = ETX) then break; // Маркер конца фрейма.
        base64buffer[len64] := (value and $FF);
        inc(len64);
      end;

      if (isPortLogging) then logMsg('READ(): <- BASE64[%d]=%s', [len64, BufferToHex(pbyte(base64buffer), 0, len64)], true);
      // Раскодируем во временный буфер.
      msglen := Base64Decode(base64buffer, 0, len64, tmpbuffer, 0);
      if (isPortLogging) then logMsg('READ(): <- FRAME[%d]=%s', [msglen, BufferToHex(pbyte(tmpbuffer), 0, msglen)], true);

      notlast := (tmpbuffer[0] and $80) <> 0;
      p := (tmpbuffer[0] and $7F);
      if (p <> part) then raise TExStructure.Create('Неверный номер фрейма! %d <> pc=%d', [p, part]);
      psize := (tmpbuffer[1] and $FF);
      if (psize <> msglen - 2 - 2) then TExStructure.Create('Неверная длина фрейма! %d <> msglen-4=%d', [psize, msglen - 2 - 2]);

      crc := CalcCRC16Sberbank(tmpbuffer, 0, msglen - 2); // Контрольная сумма включ рассчитывается по всем данным.
      c := (tmpbuffer[msglen - 2] and $FF) or ((tmpbuffer[msglen - 1] and $FF) shl 8);
      if (crc <> c) then raise TExCRC.Create('Неверная контрольная сумма! %d <> calc=%d', [c, crc]);

      n := copyArraySafe(tmpbuffer, 2, psize, buffer, readed);
      if (n <> psize) then raise TExBuilding.Create('Потеря данных при копировании! Скопировано: %d из %d', [n, psize]);

      confirm := iif(notlast, iif((part and $1) = 0, ACKEVEN, ACKODD), ACK);
      if (isPortLogging) then logMsg('READ(): -> CONFIRM=0x%.2X', [confirm], true);
      driver.write(confirm);

      inc(readed, psize);
      inc(part);
      attempt := 0;

    except
      on ex: TExCRC do
      begin
        //logRaw.errorf("Error! %s", ex.getMessage());
        dropReadSafe();
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExProtocol do
      begin
        //logRaw.errorf("Error! %s", ex.getMessage());
        dropReadSafe();
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExStructure do
      begin
        //logRaw.errorf("Error! %s", ex.getMessage());
        dropReadSafe();
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExBuilding do
      begin
        //logRaw.errorf("Error! %s", ex.getMessage());
        dropReadSafe();
        inc(attempt); if (attempt >= 3) then raise;
      end;
      on ex: TExDisconnect do
      begin
        //logRaw.errorf("Disconnect! %s", ex.getMessage());
        raise;
      end;
      on ex: TExDevice do
      begin
        //logMsg('Ошибка операции - %s!', [ex.Message]);
        raise;
      end;
      on ex: Exception do
      begin
        //logRaw.errorf(ex, "Other exception - break! %s", ex.getMessage());
        dropReadSafe();
        raise TExOtherError.Create(ex.Message);
      end;
    end;
  end;
  if (isPortLogging) then logMsg('READ(): BUFFER[%d]=%s', [readed, BufferToHex(pbyte(buffer), 0, readed)], true);
  Result := readed;
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure logCmd(const name: string; const meta: TMeta; const buffer: TDataBuffer);
var s1, s2: string;
  mc: TMCMeta;
begin
  s1 := Format('cmdid=0x%.2X syncid=0x%.8X type=%s [%d]', [meta.cmdID, meta.syncID, iif(meta.isAnswer, 'ANS', 'REQ'), meta.getDataLength()]);
  if (meta.ClassType = TMCMeta) then
  begin
    mc := TMCMeta(meta);
    s2 := Format('MC: %s %s [%d] { %s }', [mc.cidDEV(), mc.cidOP(), mc.getMCDataLength(),
      BufferToHex(buffer.bufferPtr(), mc.getMCDataOffset(), mc.getMCDataLength())]);
  end else
  begin
    s2 := BufferToHex(buffer.bufferPtr(), meta.getMetaLength(), meta.getDataLength());
  end;
  logMsg('%s(): %s { %s }', [name, s1, s2], true);
end;


// Отправка команды/ответа устройству (команда записана в outcmddata => outcmdbuffer[7]. Если это ответ -
// расширенный результат, то он берется из метаданных, а не из данных!!!
//        ExProtocol, ExBuilding, ExNAK, ExOtherError, ExDisconnect {
procedure TSBPinpadDevice.sendCmd(const meta: TMeta);
begin
  // Если это команда и не задан syncID - присваиваем новый.
  if ((not meta.isAnswer) and (meta.syncID = 0)) then meta.syncID := generateCommandID();
  try
    meta.metaTo(outcmdbuffer);
    if (isCmdLogging) then logCmd('SENDCMD', meta, outcmdbuffer);
    write(outcmdbuffer.buffer(), meta.getRawLength());
  except
    on ex: TExNAK do raise;
    on ex: TExBuilding do raise;
    on ex: TExOtherError do raise;
    // Реагируем только на генерируемые ошибки.
  end;
end;


// Получение команды/ответа от устройства в буфер для поступающих команд (incmdbuffer).
// После выполнения команды рабочая область в incmdbuffer установлена на данные!
//        ExProtocol, ExStructure, ExBuilding, ExCRC, ExOtherError, ExDisconnect
procedure TSBPinpadDevice.receiveCmd(const meta: TMeta; devanswertimeout: int; isloglater: boolean = false);
var size: int;
begin
  size := read(incmdbuffer.buffer(), devanswertimeout);
  // Выделяем и проверяем транспортные параметры.
  meta.metaFrom(incmdbuffer, size);
  if ((not isloglater) and (isCmdLogging)) then logCmd('RECEIVECMD', meta, incmdbuffer);
end;


//  throws ExWrongAnswer
procedure TSBPinpadDevice.testAnswer(const req: TMeta; const answ: TMeta; ischeckresult: boolean = false);
var errcode: int;
begin
  if (req.syncID <> answ.syncID) then raise TExWrongAnswer.Create('Не совпадают номера сообщений у команды и ответа!');
  if (not answ.isAnswer) then raise TExWrongAnswer.Create('Сообщение не является ответом!');
  if (ischeckresult) then
  begin
    errcode := answ.getResultCode();
    if (errcode <> 0) then raise TExResultCode.Create(errcode, 'Возвращен код ошибки! {%d}', [errcode]);
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  РЕАЛИЗАЦИЯ КОМАНД КОМАНДНОГО УРОВНЯ
//
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Получение (генерация) нового ID для команды.
function TSBPinpadDevice.generateCommandID(): int;
begin
  inc(lastCommandID);
  if (lastCommandID > 999999) then lastCommandID := 1;
  Result := lastCommandID;
end;


// 0x50 (CMD_GETREADY): Опрос готовности МА.
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_GetReady(devanswertimeout: int = -1): String;
var meta, res: TMeta;
begin
  meta := nil; res := nil;
  try
    meta := TMeta.command(CMDID_GETREADY, 0);
    res := TMeta.answer();
    //
    sendCmd(meta);
    receiveCmd(res, devanswertimeout);
    //
    testAnswer(meta, res);
    Result := incmdbuffer.getZStringAt(0, res.getDataLength());
  finally
    FreeAndNilSafe(meta);
    FreeAndNilSafe(res);
  end;
end;


// 0xEF (CMD_CARDTEST): Проверка наличия карты в ридере.
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_CardTest(devanswertimeout: int = -1): int;
var meta, res: TMeta;
begin
  meta := nil; res := nil;
  try
    meta := TMeta.command(CMDID_CARDTEST, 1);
    meta.setAreaToData(outcmdbuffer).put(0); // 0 = клиентский ридер.
    res := TMeta.answer();
    //
    sendCmd(meta);
    receiveCmd(res, devanswertimeout);
    //
    testAnswer(meta, res);
    Result := res.getResultCode();
  finally
    FreeAndNilSafe(meta);
    FreeAndNilSafe(res);
  end;
end;


// 0xA0 (CMD_MASTERCALL) : Управление устройствами.
// Посылка команды MASTERCALL терминалу. Данные команды находятся в исходящем буфере. Результат выполнения команды
// имеет тот же тип, что и команда!
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_MasterCall(const mc: TMCMeta; devanswertimeout: int = -1): TMCMeta;
begin
  Result := nil;
  try
    Result := TMCMeta.answer();
    //
    sendCmd(mc);
    receiveCmd(Result, devanswertimeout);
    //
    testAnswer(mc, Result);
  except
    FreeAndNilSafe(Result); // В случае ошибок - освобождаем память!
    raise;
  end;
end;

// Вывод на дисплей пинпада строки текста. Дисплей может иметь разлиное разрешение у разных устройств!!!
//      ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
procedure TSBPinpadDevice.cmd_MC_Display(row: int; const text: string; devanswertimeout: int = -1);
var
  n: int;
  mc, res: TMCMeta;
begin
  mc := nil; res := nil;
  try
    n := Length(text);
    mc := TMCMeta.command(MCDEV_DISPLAY, MCOPER_WRITE, n + 2);
    mc.setAreaToMCData(outcmdbuffer).putAt(0, row).putZStringAt(1, text, n + 1);
    res := cmd_MasterCall(mc, devanswertimeout);
  finally
    FreeAndNilSafe(mc);
    FreeAndNilSafe(res);
  end;
end;


// Искусственная надстройка над cmd_MC_Display - очистка эркана. "СРАБАТЫВАЕТ ТОЛЬКО ПОСЛЕ ПОСЛЕДУЮЩЕГО ВЫВОДА ЧЕГО-ЛИБО НА ДИСПЛЕЙ!"
procedure TSBPinpadDevice.cmd_MC_DisplayCls(devanswertimeout: int = -1);
begin
  cmd_MC_Display(-100, '', devanswertimeout);
end;


// Искусственная надстройка над cmd_MC_Display - для удобного вывода форматированного текста.
procedure TSBPinpadDevice.cmd_MC_DisplayFmt(row: int; const fmt: string; const args: array of const; devanswertimeout: int = -1);
begin
  cmd_MC_Display(row, Format(fmt, args), devanswertimeout);
end;


// Подача пинпадом звукового сигнала. "НЕ РАБОТАЕТ!"
procedure TSBPinpadDevice.cmd_MC_Beep(mode: int; devanswertimeout: int = -1);
var mc, res: TMCMeta;
begin
  mc := nil; res := nil;
  try
    mc := TMCMeta.command(MCDEV_BEEPER, MCOPER_WRITE, 1);
    mc.setAreaToMCData(outcmdbuffer).putAt(0, mode);
    res := cmd_MasterCall(mc, devanswertimeout);
  finally
    FreeAndNilSafe(mc);
    FreeAndNilSafe(res);
  end;
end;


function TSBPinpadDevice.getLastPrintedMode(): int;
begin
  Result := printerMode;
end;


procedure TSBPinpadDevice.clearLastPrintedText();
var i: int;
begin
  for i := 0 to Length(printerText)-1 do
  begin
    printerText[i].mode := 0;
    printerText[i].text := '';
  end;
  printerTextSize := 0;
end;


function TSBPinpadDevice.getLastPrintedText(): TSBPrinterText;
var i: int;
begin
  SetLength(Result, printerTextSize);
  for i:=0 to printerTextSize-1 do
  begin
    Result[i].mode := printerText[i].mode;
    Result[i].text := '' + printerText[i].text;
  end;  
end;


// Получение текущего (последнего) текста (чека) выведенного на принтер командами MASTERCALL (MCDEV_PRINTER,
// MCOPER_WRITE) в виде одной форматированной строки с переносами строк.
// ФОРМАТ: {Режим вывода строки в HEX виде (2 символа)} + {текст строки} + {\n} + ...
function TSBPinpadDevice.getLastPrintedTextAsString(): string;
var i: int;
begin
  Result := '';
  for i := 0 to printerTextSize-1 do Result := Result + printerText[i].text + #13#10;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Операции с сокетами.
//
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExWSA(msg: string = '');
begin
  raise TExWSA.Create(trim(msg+' ['+IntToStr(WSAGetLastError())+']'));
end;

procedure ExWSAIf(exp: boolean; msg: string = '');
begin
  if (exp) then ExWSA(msg);
end;

procedure InitWSA();
begin
  if (not WSAInited) then
  begin
    if (WSAStartup(MAKEWORD(1,0), WSAData) <> 0) then ExWSA('Ошибка при инициализации механизма сокетов!');
    WSAInited := true;
  end;
end;

procedure DoneWSA();
begin
  if (WSAInited) then
  begin
    WSAInited := false;
    if (WSACleanup() <> 0) then ExWSA('Ошибка при освобождении механизма сокетов!');
  end;
end;

procedure openLanSocket(var socket: TSocket; var addr: TSockAddr);
var res: int;
begin
  try
    // Создание сокета.
    socket := WinSock.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    ExWSAIf(socket = INVALID_SOCKET, 'Ошибка создания сокета!');
    // Перевод сокета в неблокирующий режим.
    res := 1;
    ExWSAIf(WinSock.ioctlsocket(socket, FIONBIO, res) = SOCKET_ERROR, 'Ошибка перевода сокета в неблокируемый режим!');
    // Соединение.
    if (WinSock.connect(socket, addr, sizeof(addr)) = SOCKET_ERROR) then
    begin
      res := WSAGetLastError();
      if (res <> WSAEWOULDBLOCK) then ExWSA(Format('Ошибка соединения! (0x%X)', [res]));
    end;
  except
    closeLanSocket(socket);
    raise;
  end;
end;

function readLanSocket(var socket: TSocket; const buffer: TDataBuffer; size: int): int;
var addrlen: Integer;
begin
  if (ioctlsocket(socket, FIONREAD, Result) = SOCKET_ERROR) then
    ExWSA('Ошибка запроса наличия данных во входящем буфере сокета!');

  Result := WinSock.recv(socket, buffer.offsetPtr()^, size, 0);
  if (Result = SOCKET_ERROR) then // Если ошибка - проверяем.
  begin
    if (WSAGetLastError() <> WSAEWOULDBLOCK) then ExWSA('Ошибка чтения данных из сокета!');
    Result := 0; // Если асинхронный режим и операция блокирована (нет данных).
  end;
end;

function writeLanSocket(var socket: TSocket; const buffer: TDataBuffer; size: int): int;
begin
  Result := WinSock.send(socket, buffer.offsetPtr()^, size, 0);
  if (Result = SOCKET_ERROR) then
  begin
    if (WSAGetLastError() <> WSAEWOULDBLOCK) then ExWSA('Ошибка записи данных в сокет!');
    Result := 0; // Если асинхронный режим и операция блокирована.
  end;
end;

// Маскирует все ошибки, подразумевается закрытие сокета в любом случае.
procedure closeLanSocket(var socket: TSocket);
var res: int;
begin
  if (socket = INVALID_SOCKET) then exit;
  // Перевод сокета в блокирующий режим перед закрытием!
  res := 0;
  if (ioctlsocket(socket, FIONBIO, res) = SOCKET_ERROR) then
  begin
    // Ошибка перевода - надо в лог выдать? Надо прекратить закрытие и выдать ошибку?
  end;
  // Завершение работы сокета (прекращение сетевых операций).
  if (WinSock.shutdown(socket, SD_BOTH) = SOCKET_ERROR) then
  begin
    // Ошибка завершения - надо в лог выдать? Надо прекратить закрытие и выдать ошибку?
  end;
  // Закрытие и освобождение сокета.
  if (WinSock.closesocket(socket) = SOCKET_ERROR) then
  begin
    // Если сокет закрыт - это не ошибка, иначе - логируем ошибку.
  end;
  socket := INVALID_SOCKET;
end;

function SockAddrToStr(var addr: TSockAddr): String;
begin
  with addr.sin_addr.S_un_b do
    Result := Format('%d.%d.%d.%d:%d', [ord(s_b1), ord(s_b2), ord(s_b3), ord(s_b4), ntohs(addr.sin_port)]);
end;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение команды поступившей от терминала и отправка результата в терминал. Выполняет необходимые действия и
// отправляет команду-результат в терминал. Исполняемая команда во входящем буфере. Отправляемый результат в
// исходящем.
//            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
procedure TSBPinpadDevice.execute_MasterCall(const mc: TMCMeta);
var errid, size: int;
    addr: TSockAddr;
    answ: TMCMeta;
begin
  errid := $00;
  rebootTimeout := 0; // Сбрасываем.
  try
    // По умолчанию ответ нулевой!
    outcmdbuffer.area(TMCMeta.getMCDataOffset(), 0);
    // Парсим команду поступившую из терминала.
    mc.setAreaToMCData(incmdbuffer);

    if (isMCLogging) then
      logMsg('MASTERCALL(): %s %s [%d]{ %s }', [mc.cidDEV(), mc.cidOP(), mc.getMCDataLength(),
        BufferToHex(incmdbuffer.offsetPtr(), 0, mc.getMCDataLength())], true);

    case (mc.mcDevType) of
      MCDEV_LAN:
        begin
          case (mc.mcOpType) of
            MCOPER_OPEN:
              begin
                // Если старый сокет по какой-то причине не закрыт - закрываем.
                closeSocket(lanSocket);

                FillChar(addr, sizeof(addr), 0);
                addr.sin_family      := PF_INET;
                // IP адрес, обратный порядок байт (!!!)
                addr.sin_addr.S_addr := incmdbuffer.getIntAt(2);
                // Порт. Обычный порядок байт (!!!)
                addr.sin_port        := htons(incmdbuffer.getInt2At(6));
                if (isMCLogging) then logMsg('MASTERCALL(): CONNECTING TO ( %s )', [SockAddrToStr(addr)], true);
                // Установка соединения.
                openLanSocket(lanSocket, addr);
                // Формирование результата операции (успех\неудача) в терминал.
              end;

            MCOPER_READ:
              begin
                // Чтение информации из ПЦ.
                size := readLanSocket(lanSocket, outcmdbuffer, incmdbuffer.getInt2At(0));
                // Формирование результата операции (данные из ПЦ) в терминал.
                outcmdbuffer.length(size);
              end;

            MCOPER_WRITE:
              begin
                // Оправка информации в ПЦ.
                size := writeLanSocket(lanSocket, incmdbuffer, mc.getMCDataLength());
                // Формирование результата операции (кол-во отправленных байт) в терминал.
                outcmdbuffer.length(2).putInt2(size);
              end;

            MCOPER_CLOSE:
              begin
                if (isMCLogging) then logMsg('MASTERCALL(): DISCONNECTING', [], true);
                // Закрытие соединения.
                closeLanSocket(lanSocket);
                // Формирование результата операции (успех) в терминал.
              end;
          end;
        end;
        
      MCDEV_PRINTER:
        begin
          case (mc.mcOpType) of
            MCOPER_OPEN:
              begin
                printerMode := incmdbuffer.getAt(0);
                // Если новая печать - очищаем старый чек, если повтор - нет.
                if (printerMode = 0) then printerTextSize := 0;
                if (isMCLogging) then logMsg('MASTERCALL(): START PRINT (mode = %d)', [printerMode], true);
                fireOnMCPrintOpen(printerMode);
              end;

            MCOPER_WRITE:
              begin
                printerText[printerTextSize].mode := incmdbuffer.getAt(0);
                printerText[printerTextSize].text := incmdbuffer.getZStringAt(1, mc.getMCDataLength() - 1);
                inc(printerTextSize); // след.строка.
                if (isMCLogging) then
                  logMsg('MASTERCALL(): PRINT TEXT = [%d]"%s"', [printerText[printerTextSize-1].mode, printerText[printerTextSize-1].text], true);
                fireOnMCPrintWrite(printerText[printerTextSize-1]);
              end;

            MCOPER_CLOSE:
              begin
                logMsg('MASTERCALL(): END PRINT (mode = %d), lines = %d', [printerMode, printerTextSize], true);
                fireOnMCPrintClose(printerMode, printerText, printerTextSize);
              end;
          end;
        end;

      MCDEV_REBOOT:
        begin
          case (mc.mcOpType) of
            MCOPER_OPEN:
              begin
                rebootTimeout := incmdbuffer.getIntAt(0);
                if (rebootTimeout < 0) then rebootTimeout := 60000; // 60 сек.
                if (isMCLogging) then logMsg('MASTERCALL(): REBOOT [timeout = %d ms]', [rebootTimeout], true);
              end;
          end;
        end;

    else
      begin
        // Для всех прочих устройств - заглушка (рапорт об успехе операции).
        // Передача результата операции (успех) в терминал.
      end;
    end;
  except
    errid := $15;
    outcmdbuffer.length(0);
  end;

  try
    answ := nil;
    try
      // Создаём и отправляем ответ на команду.
      answ := TMCMeta.answer(mc, errid, outcmdbuffer.length());
      sendCmd(answ);
    except
      on ex: TExDisconnect do raise;
      on ex: TExError do raise; // TODO: везде реализовать подробное логирование
    end;
  finally
    FreeAndNilSafe(answ);
  end;
end;

// Методы для расширения в потомках - для онлайн печати например или контроля её гарантированного сохранения.
procedure TSBPinpadDevice.fireOnMCPrintOpen(mode: int);
begin
end;

// Методы для расширения в потомках - для онлайн печати например или контроля её гарантированного сохранения.
procedure TSBPinpadDevice.fireOnMCPrintWrite(var line: TSBPrinterTextLine);
begin
end;

// Методы для расширения в потомках - для онлайн печати например или контроля её гарантированного сохранения.
procedure TSBPinpadDevice.fireOnMCPrintClose(mode: int; var text: TSBPrinterText; linecount: int);
begin
end;



procedure logTrans(const cmd: TTRCommand);
begin
  logMsg('EXEC_TRANS_CMD(): amount=%d cardT=%d curT=%d opT=%d track=%s reqid=0x%.8X rrn=%s flags=%d',
    [cmd.amount, cmd.cardType, cmd.currencyType, cmd.opType, cmd.track2, cmd.requestID, cmd.RRN, cmd.flags], true);
end;

procedure logTransResult(const res: TTRResult);
begin
  logMsg('EXEC_TRANS_RES(): code=%d auth=%s rrn=%s opN=%s cardN=%s expire=%s'
         +' msg="%s" date=%d time=%d isSB=%d termN=%s cardname=%s'
         +' merchid=%s spasibo=%d sha=%s encdata=%s cardid=%s reqid=%d res2=%s',
    [res.resultCode, res.authCode, res.RRN, res.opNumber, res.cardNumber, res.cardExpire,
    res.messageText, res.date, res.time, res.isSberbankCard, res.terminalNumber, res.cardName,
    res.merchantID, res.spasiboAmt, res.SHA1, res.encryptedData, res.cardID, res.requestID, res.res2], true);
end;


// Методы для расширения в потомках - для логирования или сохранения транзакций в БД.
procedure TSBPinpadDevice.fireOnTRStart(const meta: TTRCommand);
begin
end;

// Методы для расширения в потомках - для логирования или сохранения транзакций в БД.
procedure TSBPinpadDevice.fireOnTRFinish(const meta: TTRCommand; const res: TTRResult; const errmsg: string);
begin
end;


// * 0x6D (CMD_TRANSACTION): Транзакция.
// * Посылка команды CMD_TRANSACTION на выполнение терминалу.
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
function TSBPinpadDevice.cmd_Transaction(const meta: TTRCommand): TTRResult;
var cmd, res: TMeta;
  mc: TMCMeta;
begin
  if (isTRLogging) then logTrans(meta);

  printerMode := 0;
  printerTextSize := 0;
  cmd := nil; res := nil; mc  := nil; Result := nil;

  try
    try
      fireOnTRStart(meta);

      // Первый этап - передача команды терминалу.
      cmd := TMeta.command(CMDID_TRANSACTION, $44);
      cmd.setAreaToData(outcmdbuffer);
      outcmdbuffer.putInt(meta.amount).put(meta.cardType).put(meta.currencyType).put(meta.opType);
      if ((meta.track2 <> '') and (pos('hex:', meta.track2) > 0)) then
      begin
        outcmdbuffer.put(byte('E'));
        outcmdbuffer.putHex(copy(meta.track2, 5, length(meta.track2)-4), 39);
      end else
      begin
        outcmdbuffer.putZString(meta.track2, 40);
      end;
      outcmdbuffer.putInt(meta.requestID).putZString(meta.RRN, 13).putInt(meta.flags);

      sendCmd(cmd);

      res := TMeta.answer();
      mc := TMCMeta.Create();

      // Второй этап - выполнение промежуточных команд терминала (если поступят).
      while (true) do
      begin
        // Выполняется приём команды без логирования! Т.к. могут быть команды разных классов!
        // Логирование производится позднее исходя из типа команды.
        receiveCmd(res, 65000, true); // 60 сек таймаут + 5 сек на всякий случай.

        // Если получили ответ, то это должен быть ответ на начальную команду!
        if (res.isAnswer) then
        begin
          if (isCmdLogging) then logCmd('RECEIVECMD', res, incmdbuffer);
          break;
        end;

        // Если это команда от терминала, выполняем её и снова ждём ответа на начальную команду.
        if (res.cmdID = CMDID_MASTERCALL) then
        begin
          TMCMeta.metaFrom(mc, incmdbuffer, res.getRawLength());
          if (isCmdLogging) then logCmd('RECEIVECMD', mc, incmdbuffer);

          execute_MasterCall(mc);

          // Если была команда перезагрузки терминала - надо выдержать паузу и переподключиться.
          if (rebootTimeout > 0) then
          begin
            // Закрываем драйвер.
            getDriver().closeSafe();
            // Ждем заданное время для возобновления связи.
            sleep(rebootTimeout);
            // Переподключаемся.
            getDriver().open();
            rebootTimeout := 0;
          end;

          continue;
        end;

        // Прочие команды - по идее таких быть не должно!
        //if (isCmdLogging) then logCmd('RECEIVECMD', res, incmdbuffer);
      end;

      // Третий этап - получение ответа.
      testAnswer(cmd, res);

      res.setAreaToData(incmdbuffer); // Рабочее окно на данные. На всякий случай.
      Result := TTRResult.Create(incmdbuffer);

      if (isTRLogging) then logTransResult(Result);

      if (Result.requestID <> meta.requestID) then
        raise TExWrongAnswer.Create('Неверный requestID в ответе!');

      fireOnTRFinish(meta, Result);
      
    except
      on ex: Exception do
      begin
        fireOnTRFinish(meta, Result, iif(ex.Message = '', 'Error: ' + ex.ClassName, ex.Message));
        FreeAndNilSafe(Result);
        raise;
      end;
    end;

  finally
    FreeAndNilSafe(cmd);
    FreeAndNilSafe(res);
    FreeAndNilSafe(mc);
  end;
end;



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Регламентные операции.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadDevice.cmd_TR_Custom(amount, cmdid: int; rrn: string = ''; hexencdata: string = ''): TTRResult;
var cmd: TTRCommand;
begin
  cmd := nil; Result := nil;
  try
    try
      cmd := TTRCommand.Create(amount, cmdid);
      if (rrn <> '') then cmd.RRN := rrn;
      if (hexencdata <> '') then cmd.track2 := 'hex:' + hexencdata;
      Result := cmd_Transaction(cmd);
    except
      FreeAndNilSafe(Result);
      raise;
    end;
  finally
    FreeAndNilSafe(cmd);
  end;
end;

// Выполнение команды "ЗАКРЫТИЕ СМЕНЫ" на терминале.
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_TR_CloseSession(): TTRResult;
begin
  Result := cmd_TR_Custom(0, TR_CLOSESESSION);
end;

// Выполнение команды "ОТЧЕТ ИТОГО ЗА СМЕНУ" на терминале.
//      ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_TR_Totals(mode: int): TTRResult;
var cmd: TTRCommand;
begin
  cmd := nil; Result := nil;
  try
    try
      cmd := TTRCommand.Create(0, TR_TOTALS);
      cmd.cardType := mode; // 0-контрольная лента, 1-итоги.
      Result := cmd_Transaction(cmd);
    except
      FreeAndNilSafe(Result);
      raise;
    end;
  finally
    FreeAndNilSafe(cmd);
  end;
end;

// Выполнение команды "ОЧЕТ СПРАВКА" на терминале.
//      ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_TR_Help(): TTRResult;
begin
  Result := cmd_TR_Custom(0, TR_PRINTHELP);
end;

// Выполнение команды "ВХОД В СЕРВИСНОЕ МЕНЮ"  на терминале.
//      ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
// TODO: Нужно разобраться, как происходит процесс обновки.
// TODO: (макс.время ожидания получения обновлений? происходит перезапуск терминала?
// TODO: требуется продолжать цикл исполнения после перезагрузки? какой результат операции?)
function TSBPinpadDevice.cmd_TR_ServiceMenu(): TTRResult;
begin
  Result := cmd_TR_Custom(0, TR_SERVICEMENU);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Торговые операции.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение команды "ПРОДАЖА" на терминале.
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_TR_Purchase(amount: int): TTRResult;
begin
  Result := cmd_TR_Custom(amount, TR_PURCHASE);
end;

// Выполнение команды "ВОЗВРАТ ПРОДАЖИ" на терминале.
// Возврат клиенту суммы на карту. После возврата уже нельзя отменить операцию никаким образом! RRN+ENC - успешно
// возвращает без предъявления карты!
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect
function TSBPinpadDevice.cmd_TR_Refund(amount: int; const rrn, hexencdata: string): TTRResult;
begin
  Result := cmd_TR_Custom(amount, TR_REFUND, rrn, hexencdata);
end;

// Выполнение команды "ОТМЕНА ТРАНЗАКЦИИ" на терминале.
// Отмена транзакции (не только продаж!). Не требует карты при предоставлении hexencdata! RRN - не воспринимается!!!
// На терминале выдаст список возможных транзакций - надо будет там подтверждать! Если не задана сумма - выдаст все
// транзакции, которые можно отменить! Это видимо недоработка в прошивке!
//        ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
function TSBPinpadDevice.cmd_TR_Cancel(amount: int; const rrn, hexencdata: string): TTRResult;
begin
  Result := cmd_TR_Custom(amount, TR_CANCEL, rrn, hexencdata);
end;



initialization

  InitWSA();

finalization

  //logDbg('fin-start: dant_SBPinpadDeice.pas');
  DoneWSA();
  //logDbg('fin-end: dant_SBPinpadDeice.pas');

end.








