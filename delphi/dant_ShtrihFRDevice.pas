////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2017, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_ShtrihFRDevice;

interface

uses
  Windows, SysUtils,
  dant_utils, dant_log, dant_crc, dant_sync, dant_DataBuffer, dant_RS232Driver;

// Драйвер для управления ККМ Штрих-Мини-ФРК по протоколу Штрих.

type
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Исключения.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Общее исключение для TShtrihFRDevice
  TExShtrihFRDevice = class(TExError);

  // Неверная команда в буфере отправки (или длина).
  TExBuild = class(TExShtrihFRDevice);
  // Ошибки при неверных физических данных.
  TExProtocol = class(TExShtrihFRDevice);
  // При исчерпании попыток приёма\отправки.
  TExAttempt = class(TExShtrihFRDevice);

  // Неверный код команды в ответе.
  TExResultCommand = class(TExShtrihFRDevice);
  // Ненулевой код ошибки в ответе.
  TExResultError = class(TExShtrihFRDevice);

  // Ошибка ожидания завершения печати.
  TExWaitPrint = class(TExShtrihFRDevice);


  TResult_GetDevType = record
    device: int; // 0xNNMM NN-тип, MM-подтип
    protocol: int; // 0xNNMM NN-версия, MM-подверсия
    model: int;
    lang: int;
    name: string;
  end;

  TResult_GetStateShort = record
    operatorNum: int;
    flags: int;
    mode: int;
    modeState: int;
    subMode: int;
    billOperationCount: int;
    batteryVoltage: int;
    powerVoltage: int;
    lastPrintResult: int;
  end;

  TResult_CloseCheck = record
    operatorNum: int;
    restSum: int64;
    urlText: string;
  end;

  TResult_PrintXBarCode = record
    operatorNum: int;
    param1: int;
    param2: int;
    param3: int;
    param4: int;
    param5: int;
    width: int;
    height: int;
  end;

  TResult_GetFontParams = record
    fieldWidth: int;
    charWidth, charHeight: int;
    fontsCount: int;
    charsPerField: int;
  end;

  TResult_FN_GetOFDState = record
    status: int;
    isreading: boolean;
    msgcount: int;
    docnumber: int;
    docdt: TDateTime;
  end;

  FR_ModeEnum = (
      FR_MODE_DATA = 1,
      FR_MODE_SESSION = 2,
      FR_MODE_SESSIONOUTED = 3,
      FR_MODE_SESSIONCLOSED = 4,
      FR_MODE_BLOCKED = 5,
      FR_MODE_DATECONFIRMWAITING = 6,
      FR_MODE_DOTCHANGE = 7,

      FR_MODE_OPENDOCUMENT = 8,
      FR_MODE_OPENDOCUMENT_SALE = $00 + FR_MODE_OPENDOCUMENT,
      FR_MODE_OPENDOCUMENT_PURCHASE = $10 + FR_MODE_OPENDOCUMENT,
      FR_MODE_OPENDOCUMENT_SALERETURN = $20 + FR_MODE_OPENDOCUMENT,
      FR_MODE_OPENDOCUMENT_PURCHASERETURN = $30 + FR_MODE_OPENDOCUMENT,
      FR_MODE_OPENDOCUMENT_NOFISCAL = $40 + FR_MODE_OPENDOCUMENT,

      FR_MODE_SERVICENULL = 9,
      FR_MODE_TESTPRINTING = 10,
      FR_MODE_FISCALREPORTPRINTING = 11,
      FR_MODE_EKLZREPORTPRINTING = 12,
      FR_MODE_FPDWORKING = 13,
      FR_MODE_FPDWORKING_SALE = $00 + FR_MODE_FPDWORKING,
      FR_MODE_FPDWORKING_PURCHASE = $10 + FR_MODE_FPDWORKING,
      FR_MODE_FPDWORKING_SALERETURN = $20 + FR_MODE_FPDWORKING,
      FR_MODE_FPDWORKING_PURCHASERETURN = $30 + FR_MODE_FPDWORKING,

      FR_MODE_PDPRINTING = 14,
      FR_MODE_PDPRINTING_PAPERWAITING = $00 + FR_MODE_PDPRINTING,
      FR_MODE_PDPRINTING_LOADING = $01 + FR_MODE_PDPRINTING,
      FR_MODE_PDPRINTING_POSING = $02 + FR_MODE_PDPRINTING,
      FR_MODE_PDPRINTING_PRINTING = $03 + FR_MODE_PDPRINTING,
      FR_MODE_PDPRINTING_PRINTED = $04 + FR_MODE_PDPRINTING,
      FR_MODE_PDPRINTING_EJECTION = $05 + FR_MODE_PDPRINTING,
      FR_MODE_PDPRINTING_EXTRACTION = $06 + FR_MODE_PDPRINTING,

      FR_MODE_FISCALPAPERFORMED = 15
  );

  FR_SubModeEnum = (
      FR_SUBMODE_READY = 0,
      FR_SUBMODE_NOPAPERDETECT = 1,
      FR_SUBMODE_NOPAPERPRINTING = 2,
      FR_SUBMODE_WAITCONTINUEPRINTING = 3,
      FR_SUBMODE_FISCALPRINTING = 4,
      FR_SUBMODE_PRINTING = 5
  );

  FR_CheckTypeEnum = (FR_SALE = 0, FR_PURCHASE = 1, FR_SALE_RETURN = 2, FR_PURCHASE_RETURN = 3);

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Устройство-пинпад СБ.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TShtrihFRDevice = class
    private
      // Коммуникационный драйвер.
      driver: TRS232Driver;
      // Имя устройства (для логов).
      devname: String;

      // Таймаут получения каждого байта (50 мсек.).
      transportTimeout: int;
      // Таймаут получения подтверждения об отправке на транспортном уровне (300 мсек.).
      transportConfirmationTimeout: int; // = 2*50 = 100;
      // Таймаут получения первого байта ответа на команду (35 сек.).
      answerTimeout: int; // = 65000;

      // Буфер для передаваемых команд. (кроме STX и LRC)
      outbuffer: TDataBuffer;
      // Буфер для принимаемых команд. (кроме STX и LRC)
      inbuffer: TDataBuffer;

      psw: int; // Пароль кассира.

      syncLock: TCriticalSectionExt;

    public
      isCmdLogging: boolean;

    public
      constructor Create(const devname: String; const portname: string);
      destructor Destroy(); override;
      function getDriver(): TRS232Driver;
      function getDeviceName(): String;
      procedure open();
      function openSafe(): boolean;
      procedure closeSafe();
      procedure createNewPort();

      function TryLock(): boolean;
      procedure Lock();
      procedure Unlock();

    private
      procedure receiveAndDrop(sendval: int = -1);
      procedure sendCommand();
      procedure receiveResult(devanswertimeout: int = -1);
      procedure executeCmd(devanswertimeout: int = -1);
      function  setCmd(cmdid: int): TDataBuffer;
      function  setCmdPsw(cmdid: int): TDataBuffer;

    public
      function cmd_GetDevType(): TResult_GetDevType;
      function cmd_GetStateShort(): TResult_GetStateShort;
      function cmd_GetFontParams(fontid: int = 1): TResult_GetFontParams;

      procedure cmd_PrintString(const s: string);
      procedure cmd_PrintBoldString(const s: string);
      procedure cmd_PrintFontString(const s: string; fontnum: int);
      procedure cmd_Beep();
      function  cmd_PrintHeader(const title: string; num: int): int;
      procedure cmd_PrintCliche();
      procedure cmd_EndDocument(iswithreclam: boolean);
      procedure cmd_PrintReclame();

      function  cmd_GetMoneyRegister(num: int): int64;
      function  cmd_GetOperRegister(num: int): int;

      procedure cmd_WriteTable(tab, row, field: int; const buf; len: int);
      procedure cmd_WriteTableAsString(tab, row, field: int; const str: string; maxlen: int = 64);
      procedure cmd_WriteTableAsInt(tab, row, field: int; value: int; maxlen: int = 4);
      function  cmd_ReadTable(tab, row, field: int; var buf; maxlen: int): int;
      function  cmd_ReadTableAsString(tab, row, field: int): string;
      function  cmd_ReadTableAsInt(tab, row, field: int): int;

      procedure cmd_SetTime(hh, mm, ss: int);
      procedure cmd_SetDate(dd, mm, yy: int);
      procedure cmd_SetDateConfirm(dd, mm, yy: int);

      procedure cmd_Cut(isfull: boolean = false);
      procedure cmd_Feed(rowcount: int);

      procedure cmd_OpenSession();

      procedure cmd_OpenCheck(kind: FR_CheckTypeEnum);
      function  cmd_CloseCheck(sum1, sum2, sum3, sum4: int64; tax1, tax2, tax3, tax4: int; discount: int; const text: string = ''): TResult_CloseCheck;
      procedure cmd_AddSaleInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
      procedure cmd_AddPurchaseInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
      procedure cmd_AddSaleReturnInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
      procedure cmd_AddPurchaseReturnInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);

      function  cmd_IncomeMoneyCheck(sum: int64): int;
      function  cmd_OutcomeMoneyCheck(sum: int64): int;
      procedure cmd_CancelCheck();
      procedure cmd_PrintCheckCopy();
      procedure cmd_ContinueCheckPrint();

      procedure cmd_PrintImage(firstline: int = 1; lastline: int = 200);
      procedure cmd_PrintBarCode(value: int64);
      procedure cmd_LoadData(kind: int; blocknum: int; const buf; len: int);
      function  cmd_PrintXBarCode(kind, len, firstblocknum, par1, par2, par3, par4, par5, align: int): TResult_PrintXBarCode;
      function  cmd_PrintQRCode(len, firstblocknum, version, mask, dotsize, erclevel, align: int): TResult_PrintXBarCode;

      // Отчёты.
      procedure cmd_PrintXReport();
      procedure cmd_PrintZReport();
      procedure cmd_PrintSectionReport();
      procedure cmd_PrintTaxReport();

      procedure waitEndOfPrint(timeout: int = -1);

      procedure cmd_FN_StartOpenSession();
      procedure cmd_FN_StartCloseSession();
      procedure cmd_FN_PutTLV(const tlv; offs, len: int);
      procedure cmd_FN_PutTagAsRaw(tag: int; const raw; offs, len: int);
      procedure cmd_FN_PutTagAsOemStr(tag: int; const oemstr: string; maxlen: int = -1);
      procedure cmd_FN_PutClientEmail(const email: string);
      procedure cmd_FN_PutCashierINN(const inn: string);
      procedure cmd_FN_PutAgentType(const bits: int);
      procedure cmd_FN_PutSupplierPhone(const phone: string);

      function cmd_FN_GetOFDState(): TResult_FN_GetOFDState;

      
      class function getModeTitle(isshort: boolean; mode: int): string;
      class function getSubModeTitle(isshort: boolean; submode: int): string;
      class function getErrorTitle(errid: int): string;
  end;


implementation

uses
  dant_SerialPort, dant_utf8;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Служебные байт-коды протокола.
const STX = $02; // Начало команды.
const ENQ = $05; // Запрос состояния ККМ.
const ACK = $06; // Подтверждение успешной передачи.
const NAK = $15; // Подтверждение ошибки передачи.

const TIMEOUT = -1; // Истёк таймаут.

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TShtrihFRDevice.Create(const devname: string; const portname: string);
begin
  inherited Create();

  self.devname := devname;

  // Синхронизатор доступа. Для внешних программ.
  syncLock := TCriticalSectionExt.Create();
  syncLock.Enter();
  try
    // Буферы для команд.
    outbuffer := TDataBuffer.Create(3000, CHARSET_WIN1251);
    inbuffer  := TDataBuffer.Create(3000, CHARSET_WIN1251);

    transportTimeout             := 50;
    transportConfirmationTimeout := 2 * transportTimeout;
    answerTimeout                := 30000;

    // RS232
    self.driver := TRS232Driver.Create(devname, portname)
                      .bitrate(dant_SerialPort.BAUDRATE_115200)
                      .databits(dant_SerialPort.DATABITS_8)
                      .stopbits(dant_SerialPort.STOPBITS_1)
                      .parity(dant_SerialPort.PARITY_NONE)
                      .timeout(transportTimeout);

    psw := 30;

    isCmdLogging := false;
    self.driver.isLogging := false;
    self.driver.isIOLogging := false;
    
  finally
    syncLock.Leave();
  end;
end;


destructor TShtrihFRDevice.Destroy();
begin
  syncLock.Enter();
  try
    closeSafe();

    FreeAndNilSafe(driver);
    FreeAndNilSafe(outbuffer);
    FreeAndNilSafe(inbuffer);
  finally
    syncLock.Leave();
  end;
  FreeAndNilSafe(syncLock);

  inherited;
end;


// Получение драйвера устройства (RS232).
function TShtrihFRDevice.getDriver(): TRS232Driver;
begin
  Result := driver;
end;


// Получение имени устройства.
function TShtrihFRDevice.getDeviceName(): String;
begin
  Result := devname;
end;


procedure TShtrihFRDevice.open();
begin
  driver.open();
end;


function TShtrihFRDevice.openSafe(): boolean;
begin
  try
    driver.open();
    Result := true;
  except
    Result := false;
  end;
end;


// Метод автозавершения работы с устройством.
procedure TShtrihFRDevice.closeSafe();
begin
  // Закрываем драйвер.
  if (driver <> nil) then driver.closeSafe();
end;

procedure TShtrihFRDevice.createNewPort();
begin
  driver.CreateNewPort();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Обеспечение межпотоковой синхронизации для внешних обращений.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function TShtrihFRDevice.TryLock(): boolean;
begin
  Result := syncLock.TryEnter();
end;

procedure TShtrihFRDevice.Lock();
begin
  syncLock.Enter();
end;

procedure TShtrihFRDevice.Unlock();
begin
  syncLock.Leave();
end;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Управление на уровне низового протокола (базовый уровень).
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Здесь не используется drop, т.к. надо удалить все поступающие левые данные!!!
procedure TShtrihFRDevice.receiveAndDrop(sendval: int = -1);
var n: int;
begin
  if (isCmdLogging) then logMsg('dropping...');
  n := 0;
  while (driver.readTimeoutSafe() <> -1) do inc(n);
  if (isCmdLogging) then logMsg('dropped: %d', [n]);
  if (sendval <> -1) then
  begin
    if (isCmdLogging) then logMsg('drop-write: 0x%X', [sendval]);
    driver.writeAndFlush(sendval);
  end;
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка команды (из исходящего буфера, длина окна = длина данных, позиция = отправлено данных)
procedure TShtrihFRDevice.sendCommand();
var len, v, attempt, crccalc, i: int;
    isenq, issend: boolean;

begin
  isenq := true;
  issend := false;
  len := outbuffer.length();
  attempt := 0;
  driver.purgeRead(true); // Отбрасываем мусор в буфере.
  while (true) do
  begin
    if (preInc(attempt) > 5) then
    begin
      receiveAndDrop(ACK); // Используем дроп с приёмом всего мусора. Убиваем ответ.
      raise TExAttempt.Create('Исчерпаны попытки подачи команды!');
    end;

    if (isenq) then
    begin
      if (isCmdLogging) then logMsg('send[%d] Передача ENQ...', [attempt]);
      driver.purgeRead(true);
      driver.writeAndFlush(ENQ);
      if (isCmdLogging) then logMsg('send[%d] Получение NAK...', [attempt]);
      v := driver.readTimeoutSafe(transportConfirmationTimeout);
      case v of
        NAK: // ККТ в режиме приёма команды - переходим к посылке команды.
            begin
              //if (timeoutcount > 0) then receiveAndDrop(ACK) else
              driver.purgeRead(true); // отбрасываем буферизированные ответы.
              //timeoutcount := 0;
            end;
        TIMEOUT: // При таймауте - повтор попытки.
            begin
              if (isCmdLogging) then logMsg('send[%d] ERR: Timeout!', [attempt]);
              //driver.writeAndFlush(NAK); // Давим потенциальный ответ?
              continue;
            end;
        ACK: // ККТ в состоянии передачи ответа...
            begin
              // Если команда уже была подана - переходим к ответу.
              if (issend) then
              begin
                if (isCmdLogging) then logMsg('send[%d] Получено подтверждение приёма команды', [attempt]);
                break; // Переход к получению результата!
              end else
              // Иначе дропим результат и повтор запроса.
              begin
                if (isCmdLogging) then logMsg('send[%d] Получено подтверждение предыдущей команды, дроп...', [attempt]);
                receiveAndDrop(ACK); // Отбрасываем результат с подтверждением приёма (чтобы не слал больше).
                continue;
              end;
            end;
        else
            begin
              if (isCmdLogging) then logMsg('send[%d] ERR: Левый ответ! (v=0x%.2X)', [attempt, v]);
              if (isCmdLogging) then logMsg('send[%d] ERR: Ожидание конца передачи...', [attempt]);
              receiveAndDrop(ACK); // Отбрасываем результат с подтверждением приёма (чтобы не слал больше).
              continue;
            end;
      end;      
    end;

    // Передаём команду.
    if (isCmdLogging) then logMsg('send[%d] %s команды...', [attempt, iif(isenq, 'Передача', 'Повтор передачи')]);
    outbuffer.rewind();

    driver.write(STX);
    driver.write(len);
    crccalc := len; // Расчётная CRC.
    for i:=0 to len-1 do
    begin
      v := outbuffer.get();
      driver.write(v);
      crccalc := crccalc xor v; // Обновляем расчётную CRC.
    end;
    driver.purgeRead(true); // Чтобы если что-то пришло во врема отсылки - убилось.
    driver.writeAndFlush(crccalc);
    issend := true;
    
    // Ожидаем подтверждения приёма.
    if (isCmdLogging) then logMsg('send[%d] Получение подтверждения приёма...', [attempt]);
    v := driver.readTimeoutSafe(transportConfirmationTimeout);
    isenq := (v = TIMEOUT); // Запрос ENQ только при таймауте.
    case v of
      ACK:     break; // Успех только если получен ACK иначе повтор попытки.
      NAK:     if (isCmdLogging) then logMsg('send[%d] ERR: NAK!', [attempt]);
      TIMEOUT: if (isCmdLogging) then logMsg('send[%d] ERR: Timeout!', [attempt]);
      else     if (isCmdLogging) then logMsg('send[%d] ERR: Левый ответ! (v=0x%.2X)', [attempt, v]);
    end;
  end;
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение результата команды (во входящий буфер, длина буфера = длина данных, позиция = принято данных).
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TShtrihFRDevice.receiveResult(devanswertimeout: int = -1);
var len, v, attempt, crc, crccalc, i: int;

  procedure logAnswer(v: int);
  begin
  end;

begin
  if (devanswertimeout = -1) then devanswertimeout := answerTimeout;

  attempt := 0;
  while (true) do
  begin
    if (preInc(attempt) > 5) then
    begin
      receiveAndDrop(ACK); // Используем дроп с приёмом всего мусора. Убиваем ответ.
      raise TExAttempt.Create('Исчерпаны попытки получения результата!');
    end;

    if (attempt > 1) then // При повторных попытках необходим предварительный запрос состояния.
    begin
      if (isCmdLogging) then logMsg('recv[%d] Передача ENQ...', [attempt]);
      //receiveAndDrop(); // Используем дроп с приёмом всего мусора.
      driver.purgeRead(true);
      //driver.purgeWrite(true);
      driver.writeAndFlush(ENQ);
      if (isCmdLogging) then logMsg('recv[%d] Получение ACK...', [attempt]);
      v := driver.readTimeoutSafe(transportConfirmationTimeout);
      // Успех только если получен ACK иначе повтор попытки.
      case v of
        ACK:
            ;
        NAK:
            begin
              if (isCmdLogging) then logMsg('recv[%d] ERR: NAK!', [attempt]);
              continue;
            end;
        TIMEOUT:
            begin
              if (isCmdLogging) then logMsg('recv[%d] ERR: Timeout!', [attempt]);
              continue;
            end;
        else
            begin
              if (isCmdLogging) then logMsg('recv[%d] ERR: Левый ответ! (v=0x%.2X)', [attempt, v]);
              receiveAndDrop(NAK); // Используем дроп с приёмом всего мусора.
              continue;
            end;
      end;
    end;

    inbuffer.reset();
    if (isCmdLogging) then logMsg('recv[%d] Получение STX...', [attempt]);
    v := driver.readTimeoutSafe(devanswertimeout);
    devanswertimeout := transportConfirmationTimeout; // После первой попытки сбрасываем таймаут.
    case v of
      STX:
          ;
      ACK:
          begin
            if (isCmdLogging) then logMsg('recv[%d] ERR: ACK!', [attempt]);
            continue;
          end;
      NAK:
          begin
            if (isCmdLogging) then logMsg('recv[%d] ERR: NAK!', [attempt]);
            continue;
          end;
      TIMEOUT:
          begin
            if (isCmdLogging) then logMsg('recv[%d] ERR: Timeout!', [attempt]);
            continue;
          end;
      else
          begin
            if (isCmdLogging) then logMsg('recv[%d] ERR: Левый ответ! (v=0x%.2X)', [attempt, v]);
            receiveAndDrop(NAK); // Используем дроп с приёмом всего мусора.
            continue;
          end;
    end;

    // Если STX приняли, то таймаут вызывает повтор попытки.
    if (isCmdLogging) then logMsg('recv[%d] Получение данных...', [attempt]);
    len := 0;
    try
      len := driver.read();
      crccalc := len; // Расчётная CRC.
      inbuffer.length(len);
      for i:=0 to len-1 do
      begin
        v := driver.read();
        crccalc := crccalc xor v; // Обновляем расчётную CRC.
        inbuffer.put(v);
      end;
      crc := driver.read();
      // Контрольная сумма включ рассчитывается по всем данным (кроме STX и LRC).
      if (crc = crccalc) then
      begin
        if (isCmdLogging) then logMsg('recv[%d] Передача ACK...', [attempt]);
        driver.writeAndFlush(ACK); // Ответ принят - разрываем цикл попыток.
        break;
      end else
      begin
        if (isCmdLogging) then logMsg('recv[%d] ERR: Неверная CRC! (calc=0x%.2X <> read=0x%.2X)', [attempt, crccalc, crc]);
        // Если контрольная сумма не совпала или таймаут - передаём NAK и новая попытка.
        if (isCmdLogging) then logMsg('recv[%d] Передача NAK...', [attempt]);
        driver.writeAndFlush(NAK);
      end;
    except
      on ex: TExTimeout do // Маскируем ошибку - переход к новой попытке!
      begin
        if (isCmdLogging) then logMsg('recv[%d] ERR: Таймаут!', [attempt]);
        if (len > 0) then receiveAndDrop(NAK); // Используем дроп с приёмом всего мусора.
      end;
    end;
  end;
end;




//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение посылка команды и считывание ответа (если был непринятый ответ, он принимается и отбрасывается!).
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TShtrihFRDevice.executeCmd(devanswertimeout: int);
var outcmdid, incmdid, errid, len: int;
begin
  // Команда уже подготовлена в буфере.
  len := outbuffer.length();
  if (len > 255) then raise TExBuild.Create('Длина команды больше 255! (%d)', [len]);

  if (isCmdLogging) then logMsg('CMD(%d): %s', [outbuffer.length(), outbuffer.getHexAt(0, outbuffer.length())]);

  sendCommand();
  receiveResult(devanswertimeout);

  if (isCmdLogging) then logMsg('RESULT(%d): %s', [inbuffer.length(), inbuffer.getHexAt(0, inbuffer.length())]);

  outcmdid := outbuffer.getAt(0);
  incmdid := inbuffer.getAt(0);
  if (outcmdid = $FF) then
  begin
    outcmdid := (outcmdid shl 8) or outbuffer.getAt(1);
    incmdid := (incmdid shl 8) or inbuffer.getAt(1);
    inbuffer.shiftOffset(1); // Доп.сдвиг на второй байт.
  end;
  inbuffer.shiftOffset(1);

  if (outcmdid <> incmdid) then raise TExResultCommand.Create('Неверный код команды в ответе! (cmd=0x%.2X res=%0x%.2X)', [outcmdid, incmdid]);

  errid := inbuffer.getAt(0);
  if (errid <> 0) then raise TExResultError.Create(errid, 'Получен код ошибки! (0x%.2X: "%s")', [errid, getErrorTitle(errid)]);

  inbuffer.shiftOffset(1); // Сдвигаем окно чтобы начиналось с данных.
end;


function TShtrihFRDevice.setCmd(cmdid: int): TDataBuffer;
begin
  if (cmdid > $FF) then
    Result := outbuffer.reset().put((cmdid shr 8) and $FF).put(cmdid and $FF)
  else
    Result := outbuffer.reset().put(cmdid);
end;

function TShtrihFRDevice.setCmdPsw(cmdid: int): TDataBuffer;
begin
  Result := setCmd(cmdid).putInt(psw);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  КОМАНДЫ ПРОТОКОЛА ШТРИХ
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получить тип устройства (ВНИМАНИЕ, ПОЧЕМУ НЕТ В НОВОЙ ВЕРСИИ ПРОТОКОЛА???!!!)
function TShtrihFRDevice.cmd_GetDevType(): TResult_GetDevType;
begin
  setCmd($FC).flip();
  executeCmd();
  inbuffer.rewind();
  Result.device := (inbuffer.get() shl 8) or (inbuffer.get());
  Result.protocol := (inbuffer.get() shl 8) or (inbuffer.get());
  Result.model := inbuffer.get();
  Result.lang := inbuffer.get();
  Result.name := trim(inbuffer.getString(inbuffer.remaining()));
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Короткий запрос состояния ККТ
function TShtrihFRDevice.cmd_GetStateShort(): TResult_GetStateShort;
begin
  setCmdPsw($10).flip();
  executeCmd();
  FillChar(Result, sizeof(Result), 0);
  inbuffer.rewind();
  Result.operatorNum := inbuffer.get();
  Result.flags := inbuffer.getInt2();
  Result.mode := inbuffer.get();
  Result.subMode := inbuffer.get();
  Result.billOperationCount := inbuffer.get();
  Result.batteryVoltage := inbuffer.get();
  Result.powerVoltage := inbuffer.get();
  inbuffer.shift(2);
  Result.billOperationCount := Result.billOperationCount or (inbuffer.get() shl 8);
  inbuffer.shift(3);
  if (inbuffer.hasRemaining()) then Result.lastPrintResult := inbuffer.get();
end;


function TShtrihFRDevice.cmd_GetFontParams(fontid: int = 1): TResult_GetFontParams;
begin
  setCmdPsw($26).put(fontid).flip();
  executeCmd();
  FillChar(Result, sizeof(Result), 0);
  inbuffer.rewind();
  Result.fieldWidth := inbuffer.getInt2();
  Result.charWidth  := inbuffer.get();
  Result.charHeight := inbuffer.get();
  Result.fontsCount := inbuffer.get();
  Result.charsPerField := 0;
  if (Result.charWidth > 0) then Result.charsPerField := Result.fieldWidth div Result.charWidth
end;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать стандартной строки (шрифт 1)
procedure TShtrihFRDevice.cmd_PrintString(const s: string);
begin
  setCmdPsw($17).put(2).putString(s, 60).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать жирной строки (шрифт 2)
procedure TShtrihFRDevice.cmd_PrintBoldString(const s: string);
begin
  setCmdPsw($12).put(2).putString(s, 60).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать строки данным шрифтом
procedure TShtrihFRDevice.cmd_PrintFontString(const s: string; fontnum: int);
begin
  setCmdPsw($2F).put(2).put(fontnum).putString(s, 60).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Гудок
procedure TShtrihFRDevice.cmd_Beep();
begin
  setCmdPsw($13).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать заголовка документа (возвращает номер документа).
function TShtrihFRDevice.cmd_PrintHeader(const title: string; num: int): int;
begin
  setCmdPsw($18).putZString(title, 30).putInt2(num).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос денежного регистра: Ф регистры = 1 байт (К регистры = 2 байта - для других аппаратов?)
function TShtrihFRDevice.cmd_GetMoneyRegister(num: int): int64;
begin
  setCmdPsw($1A).put(num).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getLong6();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос операционного регистра
function TShtrihFRDevice.cmd_GetOperRegister(num: int): int;
begin
  setCmdPsw($1B).put(num).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запись таблицы: len<=40 для штрих-мини
procedure TShtrihFRDevice.cmd_WriteTable(tab, row, field: int; const buf; len: int);
begin
  setCmdPsw($1E).put(tab).putInt2(row).put(field).putVar(buf, 0, len).flip();
  executeCmd();
end;

procedure TShtrihFRDevice.cmd_WriteTableAsString(tab, row, field: int; const str: string; maxlen: int = 64);
begin
  // Передаём обязательный нулевой символ в конце строки - для принудительной её обрезки!
  // Это актуально только для текстовых полей! Если не делать - будет остаток поля заполнен мусором.
  setCmdPsw($1E).put(tab).putInt2(row).put(field).putString(str + #00, maxlen).flip();
  executeCmd();
end;

procedure TShtrihFRDevice.cmd_WriteTableAsInt(tab, row, field: int; value: int; maxlen: int = 4);
begin
  setCmdPsw($1E).put(tab).putInt2(row).put(field).putVar(value, 0, maxlen).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Чтение таблицы (возвращает длину считанного значения!)
function TShtrihFRDevice.cmd_ReadTable(tab, row, field: int; var buf; maxlen: int): int;
begin
  setCmdPsw($1F).put(tab).putInt2(row).put(field).flip();
  executeCmd();
  Result := min(maxlen, inbuffer.remaining());
  inbuffer.rewind().getVar(buf, 0, Result);
end;

function TShtrihFRDevice.cmd_ReadTableAsString(tab, row, field: int): string;
begin
  setCmdPsw($1F).put(tab).putInt2(row).put(field).flip();
  executeCmd();
  Result := inbuffer.getString(inbuffer.remaining());
end;

function TShtrihFRDevice.cmd_ReadTableAsInt(tab, row, field: int): int;
begin
  setCmdPsw($1F).put(tab).putInt2(row).put(field).flip();
  executeCmd();
  Result := 0;
  inbuffer.getVar(Result, 0, min(4, inbuffer.remaining()));
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Программирование времени
procedure TShtrihFRDevice.cmd_SetTime(hh, mm, ss: int);
begin
  setCmdPsw($21).put(hh).put(mm).put(ss).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Программирование даты
procedure TShtrihFRDevice.cmd_SetDate(dd, mm, yy: int);
begin
  setCmdPsw($22).put(dd).put(mm).put(yy).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Подтверждение программирования даты
procedure TShtrihFRDevice.cmd_SetDateConfirm(dd, mm, yy: int);
begin
  setCmdPsw($23).put(dd).put(mm).put(yy).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отрезка чека
procedure TShtrihFRDevice.cmd_Cut(isfull: boolean = false);
begin
  setCmdPsw($25).put(iif(isfull, 0, 1)).flip();
  executeCmd();
  sleep(400);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Протяжка
procedure TShtrihFRDevice.cmd_Feed(rowcount: int);
begin
  setCmdPsw($29).put(2).put(rowcount).flip();
  executeCmd();
end;





//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открыть смену
procedure TShtrihFRDevice.cmd_OpenSession();
begin
  setCmdPsw($E0).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Суточный отчет без гашения
procedure TShtrihFRDevice.cmd_PrintXReport();
begin
  setCmdPsw($40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отчет о закрытии смены
procedure TShtrihFRDevice.cmd_PrintZReport();
begin
  setCmdPsw($41).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отчёт по секциям
procedure TShtrihFRDevice.cmd_PrintSectionReport();
begin
  setCmdPsw($42).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отчёт по налогам
procedure TShtrihFRDevice.cmd_PrintTaxReport();
begin
  setCmdPsw($43).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Печать клише
procedure TShtrihFRDevice.cmd_PrintCliche();
begin
  setCmdPsw($52).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Конец Документа (можно с рекламой).
procedure TShtrihFRDevice.cmd_EndDocument(iswithreclam: boolean);
begin
  setCmdPsw($53).put(iif(iswithreclam, 1, 0)).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать рекламного текста
procedure TShtrihFRDevice.cmd_PrintReclame();
begin
  setCmdPsw($54).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Внесение.
function TShtrihFRDevice.cmd_IncomeMoneyCheck(sum: int64): int;
begin
  setCmdPsw($50).putLong5(sum).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Выплата.
function TShtrihFRDevice.cmd_OutcomeMoneyCheck(sum: int64): int;
begin
  setCmdPsw($51).putLong5(sum).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открыть чек: «0» – приход, «1» – расход, «2» – возврат прихода, «3» – возврат расхода.
procedure TShtrihFRDevice.cmd_OpenCheck(kind: FR_CheckTypeEnum);
begin
  setCmdPsw($8D).put(ord(kind)).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрытие чека.
function TShtrihFRDevice.cmd_CloseCheck(sum1, sum2, sum3, sum4: int64; tax1, tax2, tax3, tax4: int;
                                            discount: int; const text: string = ''): TResult_CloseCheck;
begin
  setCmdPsw($85)
    .putLong5(sum1).putLong5(sum2).putLong5(sum3).putLong5(sum4)
    .putInt2(discount)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putZString(text, 40)
    .flip();
  executeCmd();
  inbuffer.rewind();
  Result.operatorNum := inbuffer.get();
  Result.restSum := inbuffer.getLong5();
  Result.urlText := '';
  if (inbuffer.hasRemaining()) then Result.urlText := inbuffer.getString(inbuffer.remaining());
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Добавление строки продажи в чек.
procedure TShtrihFRDevice.cmd_AddSaleInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  setCmdPsw($80)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putZString(text, 40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Добавление строки покупки в чек.
procedure TShtrihFRDevice.cmd_AddPurchaseInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  setCmdPsw($81)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putZString(text, 40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Возврат продажи
procedure TShtrihFRDevice.cmd_AddSaleReturnInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  setCmdPsw($82)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putZString(text, 40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Возврат покупки
procedure TShtrihFRDevice.cmd_AddPurchaseReturnInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  setCmdPsw($83)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putZString(text, 40).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Аннулирование чека.
procedure TShtrihFRDevice.cmd_CancelCheck();
begin
  setCmdPsw($88).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать копии чека (Повтор документа).
procedure TShtrihFRDevice.cmd_PrintCheckCopy();
begin
  setCmdPsw($8C).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Продолжение печати.
procedure TShtrihFRDevice.cmd_ContinueCheckPrint();
begin
  setCmdPsw($B0).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать графики.
procedure TShtrihFRDevice.cmd_PrintImage(firstline: int = 1; lastline: int = 200);
begin
  setCmdPsw($C1).put(firstline).put(lastline).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать штрих-кода EAN-13.
procedure TShtrihFRDevice.cmd_PrintBarCode(value: int64);
begin
  setCmdPsw($C2).putLong5(value).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Загрузка данных: kind=0 - QRData, len<=64!
procedure TShtrihFRDevice.cmd_LoadData(kind: int; blocknum: int; const buf; len: int);
begin
  setCmdPsw($DD).put(kind).put(blocknum).putVar(buf, 0, len).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать многомерного штрих-кода.
function TShtrihFRDevice.cmd_PrintXBarCode(kind, len, firstblocknum, par1, par2, par3, par4, par5, align: int): TResult_PrintXBarCode;
begin
  setCmdPsw($DE)
    .put(kind).putInt2(len).put(firstblocknum)
    .put(par1).put(par2).put(par3).put(par4).put(par5)
    .put(align).flip();
  executeCmd();
  inbuffer.rewind();
  FillMemory(@Result, sizeof(Result), 0);
  Result.operatorNum := inbuffer.get();
  if (kind = 131) then
  begin
    Result.param1 := inbuffer.get();
    Result.param2 := inbuffer.get();

    Result.param3 := inbuffer.get();

    Result.param4 := inbuffer.get();

    Result.param5 := inbuffer.get();

    Result.width := inbuffer.getInt2();

    Result.height := inbuffer.getInt2();

  end;

end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать QR штрих-кода.
function TShtrihFRDevice.cmd_PrintQRCode(len, firstblocknum, version, mask, dotsize, erclevel, align: int): TResult_PrintXBarCode;
begin
  // kind=3 len=загруженные данные, firstblocknum=0, version=0, mask=0, dotsize=4, erclevel=2, align=1
  Result := cmd_PrintXBarCode(3 {131}, len, firstblocknum, version, mask, dotsize, 0, erclevel, align);
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ФН: Начать открытие смены.
procedure TShtrihFRDevice.cmd_FN_StartOpenSession();
begin
  setCmdPsw($FF41).flip;
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ФН: Начать закрытие смены.
procedure TShtrihFRDevice.cmd_FN_StartCloseSession();
begin
  setCmdPsw($FF42).flip;
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Передача в ФН: Произвольных TLV данных.
procedure TShtrihFRDevice.cmd_FN_PutTLV(const tlv; offs, len: int);
begin
  setCmdPsw($FF0C).putVar(tlv, offs, len).flip;
  executeCmd();
end;

// Передача в ФН: Тэга как строки (с перекодированием в CP866).
procedure TShtrihFRDevice.cmd_FN_PutTagAsOemStr(tag: int; const oemstr: string; maxlen: int = -1);
var raw: string;
begin
  raw := dant_AnsiToOem(oemstr);
  setCmdPsw($FF0C).putInt2(tag).putInt2(Length(raw)).putRawString(raw, maxlen).flip;
  executeCmd();
end;

// Передача в ФН: Тэга как проистроки (с перекодированием в CP866).
procedure TShtrihFRDevice.cmd_FN_PutTagAsRaw(tag: int; const raw; offs, len: int);
begin
  setCmdPsw($FF0C).putInt2(tag).putInt2(len).putVar(raw, offs, len).flip;
  executeCmd();
end;

// Передача в ФН: Телефона клиента или электронного адреса почты клиента.
procedure TShtrihFRDevice.cmd_FN_PutClientEmail(const email: string);
begin
  cmd_FN_PutTagAsOemStr(1008, email, 64);
end;

// Передача в ФН: ИНН кассира.
procedure TShtrihFRDevice.cmd_FN_PutCashierINN(const inn: string);
begin
  cmd_FN_PutTagAsOemStr(1203, inn, 12);
end;

// Передача в ФН: Признака агента.
procedure TShtrihFRDevice.cmd_FN_PutAgentType(const bits: int);
begin
  cmd_FN_PutTagAsRaw(1057, bits, 0, 1);
end;

// Передача в ФН: Телефона поставщика.
procedure TShtrihFRDevice.cmd_FN_PutSupplierPhone(const phone: string);
begin
  cmd_FN_PutTagAsOemStr(1171, phone, 19);
end;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос из ФН состояния обмена информацией с ОФД.
function TShtrihFRDevice.cmd_FN_GetOFDState(): TResult_FN_GetOFDState;
var dd,mm,yy,h,m: int;
  zerotime: double;
begin
  setCmdPsw($FF39).flip();
  executeCmd();
  inbuffer.rewind();
  FillMemory(@Result, sizeof(Result), 0);
  Result.status    := inbuffer.get();
  Result.isreading := (inbuffer.get() <> 0);
  Result.msgcount  := inbuffer.getInt2();
  Result.docnumber := inbuffer.getInt();
  yy := inbuffer.get() + 2000;
  mm := inbuffer.get();
  dd := inbuffer.get();
  h := inbuffer.get();
  m := inbuffer.get();
  if (dd = 0) then
  begin
    zerotime := 0;
    Result.docdt := TDateTime(zerotime);
  end else
  begin
    Result.docdt := dtwParse(Format('%d.%d.%d %d:%d:00', [dd,mm,yy,h,m]), '');
  end;  
end;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Ожидание любого состояния ККТ при котором отсутствует печать.
procedure TShtrihFRDevice.waitEndOfPrint(timeout: int = -1);
var
  timestart: int64;
  st: TResult_GetStateShort;
begin
  timestart := GetNowInMilliseconds();
  while (true) do
  begin
    st := cmd_GetStateShort();
    case (FR_SubModeEnum(st.subMode)) of
      FR_SUBMODE_READY,
      FR_SUBMODE_NOPAPERDETECT:
          break;
      FR_SUBMODE_NOPAPERPRINTING,
      FR_SUBMODE_WAITCONTINUEPRINTING:
          raise TExWaitPrint.Create(st.subMode);
    end;
    if (timeout > -1) then
    begin
      if (GetNowInMilliseconds() - timestart >= timeout) then
        raise TExWaitPrint.Create(0, 'Истекло время ожидания завершения печати!');
    end;
    sleep(50);
  end;
end;








//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Расшифровки состояний и ошибок.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class function TShtrihFRDevice.getModeTitle(isshort: boolean; mode: int): string;
const
  m1: array [0..15] of string = ('', 'Выдача данных', 'Открытая смена, 24 часа не закончились', 'Открытая смена, 24 часа закончились',
    'Закрытая смена', 'Блокировка по неправильному паролю налогового инспектора', 'Ожидание подтверждения ввода даты',
    'Разрешение изменения положения десятичной точки', 'Открытый документ', 'Режим разрешения технологического обнуления',
    'Тестовый прогон', 'Печать полного фискального отчета', 'Печать отчёта ЭКЛЗ',
    'Работа с фискальным подкладным документом', 'Печать подкладного документа', 'Фискальный подкладной документ сформирован');
  m2: array [0..15] of string = ('', 'Передача данных', 'Открытая смена', '24 часа закончились',
    'Закрытая смена', 'Блокировка', 'Подтверждение даты',
    'Десятичная точка', 'Док:', 'Тех.обнуление',
    'Тестовый прогон', 'Фиск.отчет', 'Отчёт ЭКЛЗ',
    'ФПД:', 'ППД:', 'ФПД сформирован');
  md1: array [0..4] of string = ('Продажа', 'Покупка', 'Возврат продажи', 'Возврат покупки', 'Нефискальный');
  md2: array [0..4] of string = ('Продажа', 'Покупка', 'Возв.прод.', 'Возв.пок.', 'Нефиск.');
  mfd1: array [0..3] of string = ('Продажа', 'Покупка', 'Возврат продажи', 'Возврат покупки');
  mfd2: array [0..3] of string = ('Продажа', 'Покупка', 'Возв.прод.', 'Возв.пок.');
  mppd1: array [0..6] of string = ('Ожидание загрузки','Загрузка и позиционирование','Позиционирование',
    'Печать','Печать закончена','Выброс документа','Ожидание извлечения');
  mppd2: array [0..6] of string = ('Ожид.загр.','Загрузка','Позиц.','Печать','Печ.зак.','Выброс','Ожид.извл.');
var submode: int;

begin
  submode := (mode shr 4) and $F;
  mode := mode and $F;
  if (isshort) then
  begin
    // Краткое название режима для отображения в ККТ.
    case FR_ModeEnum(mode and $F) of
      FR_MODE_OPENDOCUMENT: Result := m2[mode] + md2[submode];
      FR_MODE_FPDWORKING:   Result := m2[mode] + mfd2[submode];
      FR_MODE_PDPRINTING:   Result := m2[mode] + mppd2[submode];
      else                  Result := m2[mode];
    end;
  end else
  begin
    // Полное название режима для хинта.
    case FR_ModeEnum(mode) of
      FR_MODE_OPENDOCUMENT: Result := m1[mode] + md1[submode];
      FR_MODE_FPDWORKING:   Result := m1[mode] + mfd1[submode];
      FR_MODE_PDPRINTING:   Result := m1[mode] + mppd1[submode];
      else                  Result := m1[mode];
    end;
  end;
end;


class function TShtrihFRDevice.getSubModeTitle(isshort: boolean; submode: int): string;
const
  sm1: array [0..5] of string = ('Бумага есть, готовность к выполнению команд', 'Нет бумаги (сработал датчик)', 'При печати закончилась бумага',
    'Ожидание команды продолжения печати', 'Идёт печать фискального отчёта', 'Идёт операция печати');
  sm2: array [0..5] of string = ('Готовность', 'Нет бумаги', 'Закончилась бумага',
    'Ожидание продолжения', 'Печать фиск.отчёта', 'Операция печати');

begin
  if (isshort) then
  begin
    // Краткое название режима для отображения в ККТ.
    Result := sm2[submode];
  end else
  begin
    // Полное название режима для хинта.
    Result := sm1[submode];
  end;
end;


const UNK = '';
var
  errMsg: array [0..255] of string = (
  {0x00}
  'Ошибок нет',
  'Неисправен накопитель ФП 1, ФП 2 или часы',
  'Отсутствует ФП 1',
  'Отсутствует ФП 2',
  'Некорректные параметры в команде обращения к ФП',
  'Нет запрошенных данных',
  'ФП в режиме вывода данных',
  'Некорректные параметры в команде для данной реализации ФП',
  'Команда не поддерживается в данной реализации ФП',
  'Некорректная длина команды',
  'Формат данных не BCD',
  'Неисправна ячейка памяти ФП при записи итога',
  'Переполнение необнуляемой суммы',
  'Переполнение суммы итогов смен',
  UNK,
  UNK,
  {0x10}
  UNK,
  'Не введена лицензия',
  'Заводской номер уже введен',
  'Текущая дата меньше даты последней записи в ФП',
  'Область сменных итогов ФП переполнена',
  'Смена уже открыта',
  'Смена не открыта',
  'Номер первой смены больше номера последней смены',
  'Дата первой смены больше даты последней смены',
  'Нет данных в ФП',
  'Область перерегистраций в ФП переполнена',
  'Заводской номер не введен',
  'В заданном диапазоне есть поврежденная запись',
  'Повреждена последняя запись сменных итогов',
  'Запись фискализации (перерегистрации ККМ) в накопителе не найдена',
  'Отсутствует память регистров',
  {0x20}
  'Переполнение денежного регистра при добавлении',
  'Вычитаемая сумма больше содержимого денежного регистра',
  'Неверная дата',
  'Нет записи активизации',
  'Область активизаций переполнена',
  'Нет активизации с запрашиваемым номером',
  'Вносимая клиентом сумма меньше суммы чека / В ФП присутствует 3 или более битые записи сменных итогов',
  'Признак несовпадения КС, з/н, перерегистраций или активизаций',
  'Технологическая метка в накопителе присутствует',
  'Технологическая метка в накопителе отсутствует, возможно накопитель пуст',
  'Фактическая емкость микросхемы накопителя не соответствует текущей версии ПО',
  'Невозможно отменить предыдущую команду',
  'Обнулённая касса (повторное гашение невозможно)',
  'Сумма чека по секции меньше суммы сторно',
  'В ККТ нет денег для выплаты',
  'Не совпадает заводской номер ККМ в оперативной памяти ФП с номером в накопителе',
  {0x30}
  'ККТ заблокирован, ждет ввода пароля налогового инспектора',
  'Сигнатура емкости накопителя не соответствует текущей версии ПО',
  'Требуется выполнение общего гашения',
  'Некорректные параметры в команде',
  'Нет данных',
  'Некорректный параметр при данных настройках',
  'Некорректные параметры в команде для данной реализации ККТ',
  'Команда не поддерживается в данной реализации ККТ',
  'Ошибка в ПЗУ',
  'Внутренняя ошибка ПО ККТ',
  'Переполнение накопления по надбавкам в смене',
  'Переполнение накопления в смене',
  'Смена открыта – операция невозможна / ЭКЛЗ: неверный регистрационный номер',
  'Смена не открыта – операция невозможна',
  'Переполнение накопления по секциям в смене',
  'Переполнение накопления по скидкам в смене',
  {0x40}
  'Переполнение диапазона скидок',
  'Переполнение диапазона оплаты наличными',
  'Переполнение диапазона оплаты типом 2',
  'Переполнение диапазона оплаты типом 3',
  'Переполнение диапазона оплаты типом 4',
  'Cумма всех типов оплаты меньше итога чека',
  'Не хватает наличности в кассе',
  'Переполнение накопления по налогам в смене',
  'Переполнение итога чека',
  'Операция невозможна в открытом чеке данного типа',
  'Открыт чек – операция невозможна',
  'Буфер чека переполнен',
  'Переполнение накопления по обороту налогов в смене',
  'Вносимая безналичной оплатой сумма больше суммы чека',
  'Смена превысила 24 часа',
  'Неверный пароль',
  {0x50}
  'Идет печать результатов выполнения предыдущей команды',
  'Переполнение накоплений наличными в смене',
  'Переполнение накоплений по типу оплаты 2 в смене',
  'Переполнение накоплений по типу оплаты 3 в смене',
  'Переполнение накоплений по типу оплаты 4 в смене',
  'Чек закрыт – операция невозможна',
  'Нет документа для повтора',
  'ЭКЛЗ: количество закрытых смен не совпадает с ФП',
  'Ожидание команды продолжения печати',
  'Документ открыт другим оператором',
  'Скидка превышает накопления в чеке',
  'Переполнение диапазона надбавок',
  'Понижено напряжение 24В',
  'Таблица не определена',
  'Неверная операция',
  'Отрицательный итог чека',
  {0x60}
  'Переполнение при умножении',
  'Переполнение диапазона цены',
  'Переполнение диапазона количества',
  'Переполнение диапазона отдела',
  'ФП отсутствует',
  'Не хватает денег в секции',
  'Переполнение денег в секции',
  'Ошибка связи с ФП',
  'Не хватает денег по обороту налогов',
  'Переполнение денег по обороту налогов',
  'Ошибка питания в момент ответа по I2C',
  'Нет чековой ленты',
  'Нет контрольной ленты',
  'Не хватает денег по налогу',
  'Переполнение денег по налогу',
  'Переполнение по выплате в смене',
  {0x70}
  'Переполнение ФП',
  'Ошибка отрезчика',
  'Команда не поддерживается в данном подрежиме',
  'Команда не поддерживается в данном режиме',
  'Ошибка ОЗУ',
  'Ошибка питания',
  'Ошибка принтера: нет импульсов с тахогенератора',
  'Ошибка принтера: нет сигнала с датчиков',
  'Замена ПО',
  'Замена ФП',
  'Поле не редактируется',
  'Ошибка оборудования',
  'Не совпадает дата',
  'Неверный формат даты',
  'Неверное значение в поле длины',
  'Переполнение диапазона итога чека',
  {0x80}
  'Ошибка связи с ФП (превышен таймаут I2C с контроллером)',
  'Ошибка связи с ФП (контроллер отсутствует!? (получен NAK по I2C) или принят неполный кадр от контроллера UART)',
  'Ошибка связи с ФП (неверный формат данных в кадре I2C)',
  'Ошибка связи с ФП (неверная контрольная сумма передаваемого кадра по I2C)',
  'Переполнение наличности',
  'Переполнение по продажам в смене',
  'Переполнение по покупкам в смене',
  'Переполнение по возвратам продаж в смене',
  'Переполнение по возвратам покупок в смене',
  'Переполнение по внесению в смене',
  'Переполнение по надбавкам в чеке',
  'Переполнение по скидкам в чеке',
  'Отрицательный итог надбавки в чеке',
  'Отрицательный итог скидки в чеке',
  'Нулевой итог чека',
  'Касса не фискализирована',
  {0x90}
  'Поле превышает размер, установленный в настройках',
  'Выход за границу поля печати при данных настройках шрифта',
  'Наложение полей',
  'Восстановление ОЗУ прошло успешно',
  'Исчерпан лимит операций в чеке',
  'Неизвестная ошибка ЭКЛЗ',
  'Выполните суточный отчет с гашением',
  UNK,
  UNK,
  UNK,
  UNK,
  'Некорректное действие',
  'Товар не найден по коду в базе товаров',
  'Неверные данные в записе о товаре в базе товаров',
  'Неверный размер файла базы или регистров товаров',
  UNK,
  {0xA0}
  'Ошибка связи с ЭКЛЗ',
  'ЭКЛЗ отсутствует',
  'ЭКЛЗ: Некорректный формат или параметр команды',
  'Некорректное состояние ЭКЛЗ',
  'Авария ЭКЛЗ',
  'Авария КС в составе ЭКЛЗ',
  'Исчерпан временной ресурс ЭКЛЗ',
  'ЭКЛЗ переполнена',
  'ЭКЛЗ: Неверные дата и время',
  'ЭКЛЗ: Нет запрошенных данных',
  'Переполнение ЭКЛЗ (отрицательный итог документа)',
  UNK,
  UNK,
  UNK,
  UNK,
  'Некорректные значения принятых данных от ЭКЛЗ',
  {0xB0}
  'ЭКЛЗ: Переполнение в параметре количество',
  'ЭКЛЗ: Переполнение в параметре сумма',
  'ЭКЛЗ: Уже активизирована',
  UNK,
  'Найденная запись фискализации (регистрации ККМ) повреждена',
  'Запись заводского номера ККМ повреждена',
  'Найденная запись активизации ЭКЛЗ повреждена',
  'Записи сменных итогов в накопителе не найдены',
  'Последняя запись сменных итогов не записана',
  'Сигнатура версии структуры данных в накопителе не совпадает с текущей версией ПО',
  'Структура накопителя повреждена',
  'Текущая дата+время меньше даты+времени последней записи активизации ЭКЛЗ',
  'Текущая дата+время меньше даты+времени последней записи фискализации (перерегистрации ККМ)',
  'Текущая дата меньше даты последней записи сменного итога',
  'Команда не поддерживается в текущем состоянии',
  'Инициализация накопителя невозможна',
  {0xC0}
  'Контроль даты и времени (подтвердите дату и время)',
  'ЭКЛЗ: суточный отчёт с гашением прервать нельзя',
  'Превышение напряжения в блоке питания',
  'Несовпадение итогов чека и ЭКЛЗ',
  'Несовпадение номеров смен',
  'Буфер подкладного документа пуст',
  'Подкладной документ отсутствует',
  'Поле не редактируется в данном режиме',
  'Нет связи с принтером или отсутствуют импульсы от таходатчика',
  'Перегрев печатающей головки',
  'Температура вне условий эксплуатации',
  'Неверный подытог чека',
  'Смена в ЭКЛЗ уже закрыта',
  'Обратитесь в ЦТО: тест целостности архива ЭКЛЗ не прошел, код ошибки ЭКЛЗ можно запросить командой 10H',
  'Лимит минимального свободного объема ОЗУ или ПЗУ на ККМ исчерпан',
  'Неверная дата (Часы сброшены? Установите дату!)',
  {0xD0}
  'Отчет по контрольной ленте не распечатан!',
  'Нет данных в буфере',
  UNK,
  UNK,
  UNK,
  'Критическая ошибка при загрузке ERRxx',
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  {0xE0}
  'Ошибка связи с купюроприемником',
  'Купюроприемник занят',
  'Итог чека не соответствует итогу купюроприемника',
  'Ошибка купюроприемника',
  'Итог купюроприемника не нулевой',
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  {0xF0}
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK,
  UNK
);

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Ожидание любого состояния ККТ при котором отсутствует печать.
class function TShtrihFRDevice.getErrorTitle(errid: int): string;
begin
  cutFor(errid, 0, 255);
  Result := errMsg[errid];
end;


end.








