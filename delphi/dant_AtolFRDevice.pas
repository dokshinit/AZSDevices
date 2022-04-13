////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2017, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_AtolFRDevice;

interface

uses
  Windows, SysUtils, dant_utils, dant_log, dant_crc, dant_DataBuffer, dant_RS232Driver;

// Драйвер для управления ККМ Атол по протоколу Атол 3.1 (нижний уровент v2).

type
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Исключения.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Общее исключение для TAtolFRDevice
  TExAtolFRDevice = class(TExError);

  // Неверная команда в буфере отправки (или длина).
  TExBuild = class(TExAtolFRDevice);
  // При исчерпании попыток приёма\отправки.
  TExAttempt = class(TExAtolFRDevice);

  // Неверный код команды в ответе.
  TExResultIncorrect = class(TExAtolFRDevice);
  // Ненулевой код ошибки в ответе.
  TExResultError = class(TExAtolFRDevice);


  TResult_GetDevType = record
    protocol: int;
    kind: int;
    model: int;
    mode: int;
    version: int64;
    name: string;
  end;

  TResult_GetState = record
    operator: int;
    kktnumber: int;
    dt: TDateTime;
    flags: int;
    RNM: int64;
    model: int;
    fwversion: int;
    mode: int;
    checknumber: int;
    sessionnumber: int;
    checkstate: int;
    checksum: int64;
    dotpos: int;
    port: int; // интерфейс управления
  end;

  TResult_GetModeState = record
    mode: int;
    flags: int;
  end;


  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Устройство-пинпад СБ.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TAtolFRDevice = class
    private
      // Коммуникационный драйвер.
      driver: TRS232Driver;
      // Имя устройства (для логов).
      devname: String;

      // Таймаут получения каждого байта (500 мсек.).
      transportTimeout: int; // T6
      // Таймаут получения подтверждения об отправке на транспортном уровне (500 мсек.).
      transportConfirmationTimeout: int; // T1, T3, T4.
      // Таймаут получения первого байта (STX) данных.
      transportSTXTimeout: int; // T2.
      // Таймаут получения первого байта ответа на команду (10 сек.). Индивидуально у каждой команды.
      answerTimeout: int; // T5

      // Буфер для передаваемых команд. (кроме STX и LRC)
      outbuffer: TDataBuffer;
      // Буфер для принимаемых команд. (кроме STX и LRC)
      inbuffer: TDataBuffer;

      psw: int; // Пароль кассира.

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

    private
      procedure receiveAndDrop();
      function sendCommand(): boolean;
      procedure receiveResult(isskipenq: boolean; devanswertimeout: int = -1);
      procedure executeCmd(devanswertimeout: int = -1; restype: int = 1);
      function toAtolString(const s: string): string; // Меняет местами $ и №!
      function setCmdToOutBuffer(cmdid: int): TDataBuffer;

    public
      procedure cmd_EnterToMode(mode: int; modepsw: int = 30);
      procedure cmd_ReturnFromCurrentMode();

      procedure cmd_PrintString(const s: string);
      procedure cmd_PrintImage(idx: int; offset: int = 0);
      procedure cmd_PrintCliche();
      procedure cmd_PrintBarCode(bartype, align, width, version, options, corrlevel, rowcount,
                                 colcount, barproportion, pixproportion: int; const data: string);
      procedure cmd_PrintCheckCopy();

      procedure cmd_Feed(lines: int = 7);
      procedure cmd_Cut(isfull: boolean = false);
      procedure cmd_Beep();
      procedure cmd_Sound(freq, time: int);

      function cmd_GetRegister(reg: int; param1: int = 0; param2: int = 0): TDataBuffer;
      function cmd_GetRegisterAsBCD(bcdlen: int; reg: int; param1: int = 0; param2: int = 0): int64;

      function cmd_GetDevType(): TResult_GetDevType;
      function cmd_GetState(): TResult_GetState;
      function cmd_GetModeState(): TResult_GetModeState;

      procedure cmd_PrintDemo(kind: int);
  end;


implementation

uses
  dant_SerialPort;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  ПЕРВЫЙ УРОВЕНЬ: СООБЩЕНИЯ + ТРАНСПОРТНЫЙ (фреймы) + ФИЗИЧЕСКИЙ
//
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Служебные байт-коды протокола.
const ENQ = $05; // Запрос.
const ACK = $06; // Подтверждение.
const NAK = $15; // Отрицание.
const STX = $02; // Начало текста.
const ETX = $03; // Конец текста.
const EOT = $04; // Конец передачи.
const DLE = $10; // Экранирование упр.символов.

// Тут будут константы v3 протокола, если буду реализовывать.


const TIMEOUT = -1; // Истёк таймаут.

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Пинпад.
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TAtolFRDevice.Create(const devname: string; const portname: string);
var i: int;
begin
  inherited Create();

  self.devname := devname;

  // Буферы для команд.
  outbuffer := TDataBuffer.Create(3000, CHARSET_OEM866);
  inbuffer  := TDataBuffer.Create(3000, CHARSET_OEM866);

  transportTimeout             := 500;
  transportConfirmationTimeout := 500;
  transportSTXTimeout          := 2000;
  answerTimeout                := 10000;

  // RS232
  self.driver := TRS232Driver.Create(devname, portname)
                    .bitrate(dant_SerialPort.BAUDRATE_115200)
                    .databits(dant_SerialPort.DATABITS_8)
                    .stopbits(dant_SerialPort.STOPBITS_1) // Что за стартовый бит?
                    .parity(dant_SerialPort.PARITY_NONE)
                    .timeout(transportTimeout);

  psw := 0;

  isCmdLogging := true;
  self.driver.isLogging := true;
  self.driver.isIOLogging := true;
end;


destructor TAtolFRDevice.Destroy();
begin
  closeSafe();

  FreeAndNilSafe(driver);
  FreeAndNilSafe(outbuffer);
  FreeAndNilSafe(inbuffer);

  inherited;
end;


// Получение драйвера устройства (RS232).
function TAtolFRDevice.getDriver(): TRS232Driver;
begin
  Result := driver;
end;


// Получение имени устройства.
function TAtolFRDevice.getDeviceName(): String;
begin
  Result := devname;
end;


procedure TAtolFRDevice.open();
begin
  driver.open();
end;


function TAtolFRDevice.openSafe(): boolean;
begin
  try
    driver.open();
    Result := true;
  except
    Result := false;
  end;
end;


// Метод автозавершения работы с устройством.
procedure TAtolFRDevice.closeSafe();
begin
  // Закрываем драйвер.
  if (driver <> nil) then driver.closeSafe();
end;


// Здесь не используется drop, т.к. надо удалить все поступающие левые данные!!!
procedure TAtolFRDevice.receiveAndDrop();
var n: int;
begin
  if (isCmdLogging) then logMsg('dropping...');
  n := 0;
  while (driver.readTimeoutSafe() <> -1) do inc(n);
  if (isCmdLogging) then logMsg('dropped: %d', [n]);
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка команды (из исходящего буфера, длина окна = длина данных, позиция = отправлено данных)
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function TAtolFRDevice.sendCommand(): boolean;
label label_retry_enq;
const N = 10; N1 = 100;
var len, v, frc, rc, crccalc, i: int;

  procedure incRetryAndCheck(var att: int; maxatt: int; const msg: string);
  begin
    inc(att);
    if (att > maxatt) then
    begin
      if (isCmdLogging) then logMsg('SND[%d:%d] Передача EOT...', [frc, rc]);
      driver.writeAndFlush(EOT); // Завершаем сеанс.
      raise TExAttempt.Create(msg);
    end;
  end;

begin
  Result := false;
  len := outbuffer.length();

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // ШАГ-1: Получение готовности ККТ.
  frc := 0;
  while (true) do
  begin
    inc(frc);
    rc := 0;

  label_retry_enq: ///////////////////////
    incRetryAndCheck(rc, 5, 'Исчерпаны попытки запроса готовности!');

    if (isCmdLogging) then logMsg('SND[%d:%d] Передача ENQ...', [frc, rc]);
    driver.purgeRead();
    driver.writeAndFlush(ENQ);
    if (isCmdLogging) then logMsg('SND[%d:%d] Получение ACK...', [frc, rc]);
    v := driver.readTimeoutSafe(transportConfirmationTimeout);
    case v of
      ACK:
          begin
            break;
          end;
      TIMEOUT:
          begin
            if (isCmdLogging) then logMsg('SND[%d:%d] ERR: TIMEOUT! (v=0x%.2X)', [frc, rc, v]);
            goto label_retry_enq;
          end;
      NAK:
          begin
            if (isCmdLogging) then logMsg('SND[%d:%d] ERR: NAK, sleep(%d)! (v=0x%.2X)', [frc, rc, transportTimeout, v]);
            sleep(transportTimeout);
            goto label_retry_enq;
          end;
      ENQ:
          begin
            if (isCmdLogging) then logMsg('SND[%d:%d] ERR: ENQ, sleep(%d)! (v=0x%.2X)', [frc, rc, transportTimeout, v]);
            sleep(transportTimeout);
            incRetryAndCheck(frc, N1, 'Исчерпаны попытки запроса готовности!');
            continue;
          end;
      else
          begin
            if (isCmdLogging) then logMsg('SND[%d:%d] ERR: Не ACK! (v=0x%.2X)', [frc, rc, v]);
            incRetryAndCheck(frc, N1, 'Исчерпаны попытки запроса готовности!');
            continue;
          end;
    end;
  end;
  // Получен ACK.

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // ШАГ-2: Передача команды.
  rc := 0;
  while (true) do
  begin
    incRetryAndCheck(rc, N, 'Исчерпаны попытки передачи команды!');

    // Передаём команду.
    if (isCmdLogging) then logMsg('SND[%d] Передача команды...', [rc]);
    outbuffer.rewind();
    driver.write(STX);
    crccalc := 0; // Расчётная CRC.
    for i:=0 to len-1 do
    begin
      v := outbuffer.get();
      if (v in [ETX, DLE]) then // Маскируем DLE и ETX.
      begin
        driver.write(DLE);
        crccalc := crccalc xor DLE;
      end;
      driver.write(v);
      crccalc := crccalc xor v; // Обновляем расчётную CRC.
    end;
    driver.write(ETX);
    crccalc := crccalc xor ETX; // Обновляем расчётную CRC.
    driver.writeAndFlush(crccalc);

    // Ожидаем подтверждения приёма.
    if (isCmdLogging) then logMsg('SND[%d] Получение подтверждения приёма...', [rc]);
    v := driver.readTimeoutSafe(transportConfirmationTimeout);
    if (v = ACK) then
    begin
      if (isCmdLogging) then logMsg('SND[%d] Передача EOT...', [rc]);
      driver.writeAndFlush(EOT); // Завершаем сеанс.
      break;
    end;
    if ((v = ENQ) and (rc > 1)) then
    begin
      if (isCmdLogging) then logMsg('SND[%d] NOTE: ENQ && rc>1! (v=0x%.2X)', [rc, v]);
      Result := true;
      break;
    end;
    if (v = TIMEOUT) then
    begin
      if (isCmdLogging) then logMsg('SND[%d] ERR: TIMEOUT! (v=0x%.2X)', [rc, v]);
      continue;
    end;
    // Не ACK и не (ENQ && rc>1) и не TIMEOUT - повтор.
  end;
end;


procedure TAtolFRDevice.receiveResult(isskipenq: boolean; devanswertimeout: int = -1);
label label_retry_err, label_retry_stx, label_buf_reset;
const N = 10; N1 = 100;
var len, v, frc, rc, crccalc, i: int;
    ismask: boolean;
    tm, tmstart: int64;

begin
  if (devanswertimeout = -1) then devanswertimeout := answerTimeout;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // ШАГ-1: Получение запроса от ККТ (может быть пропущен, если приняли при посылке команды).
  if (not isskipenq) then // Если ENQ был получен - переходим к приёму данных.
  begin
    rc := 0;
    tmstart := GetNowInMilliseconds();
    tm := devanswertimeout;
    while (true) do
    begin
      if (preInc(rc) > N1) then raise TExAttempt.Create('Исчерпаны попытки получения ENQ!');
      if (isCmdLogging) then logMsg('RCV[%d:%d] Получение ENQ...', [frc, rc]);
      v := driver.read(tm); // ExTimeout
      if (v = ENQ) then break;
      tm := tmstart + devanswertimeout - GetNowInMilliseconds();
      if (tm <= 0) then TExTimeout.Create('Таймаут ожидания ENQ!');
    end;
  end; // ИСПОЛЬУЕТСЯ ОБЩЕЕ ВРЕМЯ ОЖИДАНИЯ ENQ!!! (а в схеме КАЖДЫЙ повтор оно!)

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // ШАГ-2: Прием результата.
  frc := 1; // ??? Этого в схеме нет, но по логике должно быть, т.к. нет начального инкремента!?
  while (true) do
  begin
    if (isCmdLogging) then logMsg('RCV[%d:%d] Отправка ACK...', [frc, rc]);
    driver.writeAndFlush(ACK);

  label_retry_err: //////////////////////
    tmstart := GetNowInMilliseconds();
    tm := transportSTXTimeout;
    rc := 0;

  label_retry_stx: //////////////////////
    if (preInc(rc) > N1) then raise TExAttempt.Create('Исчерпаны попытки получения STX!');

    if (isCmdLogging) then logMsg('RCV[%d:%d] Получение STX...', [frc, rc]);
    v := driver.read(tm);
    if (v = ENQ) then
    begin
      if (isCmdLogging) then logMsg('RCV[%d:%d] ERR: Получен ENQ!', [frc, rc]);
      if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
      continue;
    end;
    if (v <> STX) then
    begin
      if (isCmdLogging) then logMsg('RCV[%d:%d] ERR: Получен не STX!(v=0x%.2X)', [frc, rc, v]);
      tm := tmstart + transportSTXTimeout - GetNowInMilliseconds();
      if (tm <= 0) then TExTimeout.Create('Таймаут ожидания STX!');
      goto label_retry_stx;
    end;

    // STX
  label_buf_reset:
    inbuffer.reset();
    ismask := false;
    crccalc := 0;

    while (true) do
    begin
      if (not inbuffer.hasRemaining()) then
      begin
        if (isCmdLogging) then logMsg('RCV[%d:%d] ERR: Переполнен буфер!', [frc, rc]);
        if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
        goto label_retry_err;
      end;
      v := driver.readTimeoutSafe(transportTimeout);
      if (v = TIMEOUT) then
      begin
        if (isCmdLogging) then logMsg('RCV[%d:%d] ERR: TIMEOUT!', [frc, rc]);
        if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
        goto label_retry_err;
      end;
      // Данные.
      crccalc := crccalc xor v; // Все данные, т.ч. ETX!
      if (ismask) then
      begin
        ismask := false;
        inbuffer.put(v);
      end else
      begin
        if (v = DLE) then
        begin
          ismask := true; // Не считываем в буфер!
        end else
        begin
          if (v = ETX) then break;
          inbuffer.put(v);
        end;
      end;
      // Продолжаем приём.
    end;
    inbuffer.flip();
    // Приём контрольной суммы.
    if (isCmdLogging) then logMsg('RCV[%d:%d] Приём контрольной суммы...', [frc, rc]);
    v := driver.readTimeoutSafe(transportTimeout);
    if (v = TIMEOUT) then
    begin
      if (isCmdLogging) then logMsg('RCV[%d:%d] ERR: TIMEOUT!', [frc, rc]);
      if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
      goto label_retry_err;
    end;
    if (v <> crccalc) then
    begin
      if (isCmdLogging) then logMsg('RCV[%d:%d] ERR: CRC (cacl=0x%X crc=0x%X), Отправка NAK...', [frc, rc, crccalc, v]);
      driver.writeAndFlush(NAK);
      if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
      goto label_retry_err;
    end;
    // CRC Ok.
    if (isCmdLogging) then logMsg('RCV[%d:%d] Отправка ACK...', [frc, rc]);
    driver.writeAndFlush(ACK);
    if (isCmdLogging) then logMsg('RCV[%d:%d] Получение EOT...', [frc, rc]);
    v := driver.readTimeoutSafe(transportConfirmationTimeout);
    if ((v = TIMEOUT) or (v = EOT)) then break; // Завершаем приём.
    if (v = STX) then
    begin
      if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
      goto label_retry_err;
    end;
    // Не EOT и не STX и не TIMEOUT.
    v := driver.readTimeoutSafe(transportTimeout);
    if (v = TIMEOUT) then
    begin
      break; // Завершаем приём.
    end else
    begin
      if (preInc(frc) > N) then raise TExAttempt.Create('Исчерпаны попытки получения ответа!');
      goto label_retry_err;
    end;
  end;
end;

const RES_55 = 1; RES_ERR = 2; RES_DEF = RES_55 + RES_ERR;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение посылка команды и считывание ответа (если был непринятый ответ, он принимается и отбрасывается!).
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TAtolFRDevice.executeCmd(devanswertimeout: int = -1; restype: int = 1);
var v, errid, len: int;
    isskipenq: boolean;
begin
  // Команда уже подготовлена в буфере.
  len := outbuffer.length();
  if (len > 255) then raise TExBuild.Create('Длина команды больше 255! (%d)', [len]);

  if (isCmdLogging) then logMsg('CMD(%d): %s', [outbuffer.length(), outbuffer.getHexAt(0, outbuffer.length())]);

  isskipenq := sendCommand();
  receiveResult(isskipenq, devanswertimeout);

  if (isCmdLogging) then logMsg('RESULT(%d): %s', [inbuffer.length(), inbuffer.getHexAt(0, inbuffer.length())]);

  inbuffer.rewind();
  // Если надо - проверяем первый байт на 0x55.
  if (isBitOn(restype, 1)) then
  begin
    v := inbuffer.get();
    if (v <> $55) then raise TExResultIncorrect.Create('Неверный код ответа в ответе! (0x55 <> res=0x%.2X)', [v]);
  end;
  // Если надо - проверяем на код ошибки (1 байт!).
  if (isBitOn(restype, 2)) then
  begin
    errid := inbuffer.getAt(1);
    if (errid <> 0) then raise TExResultError.Create(errid, 'Получен код ошибки! (err=0x%.2X)', [errid]);
  end;
  inbuffer.tail(); // Если были проверки - сдвигаем начало буфера, чтобы начать с данных.
end;






//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  КОМАНДЫ ПРОТОКОЛА ШТРИХ
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function TAtolFRDevice.toAtolString(const s: string): string;
var i, len: int;
begin
  len := Length(s);
  SetLength(Result, len);
  for i := 1 to len do
  begin
    case s[i] of
      '№': Result[i] := '$';
      '$': Result[i] := '№';
      else Result[i] := s[i];
    end;
  end;
end;

function TAtolFRDevice.setCmdToOutBuffer(cmdid: int): TDataBuffer;
begin
  Result := outbuffer.reset().putLongAsBCD(psw, 2).put(cmdid);
end;






procedure TAtolFRDevice.cmd_EnterToMode(mode: int; modepsw: int = 30);
begin
  setCmdToOutBuffer($56).put(mode).putLongAsBCD(modepsw, 4).flip();
  executeCmd();
end;


procedure TAtolFRDevice.cmd_ReturnFromCurrentMode();
begin
  setCmdToOutBuffer($48).flip();
  executeCmd();
end;






//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать стандартной строки (шрифт по умолчанию)
procedure TAtolFRDevice.cmd_PrintString(const s: string);
begin
  setCmdToOutBuffer($4C).putString(toAtolString(s)).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать графики.
procedure TAtolFRDevice.cmd_PrintImage(idx: int; offset: int = 0);
begin
  setCmdToOutBuffer($8D).put(1).put(idx).putInt2(offset).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать клише
procedure TAtolFRDevice.cmd_PrintCliche();
begin
  setCmdToOutBuffer($6C).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать штрих-кода.
procedure TAtolFRDevice.cmd_PrintBarCode(bartype, align, width, version, options, corrlevel,
  rowcount, colcount, barproportion, pixproportion: int; const data: string);
begin
  setCmdToOutBuffer($C1).put(bartype).put(align).putInt2(version).putInt2(options).put(corrlevel)
    .put(rowcount).put(colcount).putInt2(barproportion).putInt2(pixproportion).putRawString(data).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать копии чека (Повтор документа).
procedure TAtolFRDevice.cmd_PrintCheckCopy();
begin
  setCmdToOutBuffer($95).flip();
  executeCmd();
end;







//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Протяжка
procedure TAtolFRDevice.cmd_Feed(lines: int = 7);
var i: int;
begin
  cutFor(lines, 1, 20);
  for i:=1 to lines do cmd_PrintString('');
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отрезка чека
procedure TAtolFRDevice.cmd_Cut(isfull: boolean = false);
begin
  setCmdToOutBuffer($75).put(iif(isfull, 0, 1)).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Гудок
procedure TAtolFRDevice.cmd_Beep();
begin
  setCmdToOutBuffer($47).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Сигнал.
procedure TAtolFRDevice.cmd_Sound(freq, time: int);
begin
  setCmdToOutBuffer($88).putInt2(65536 - (921600 div freq)).put(time).flip();
  executeCmd();
end;





//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос денежного регистра: kind = 0 ( регистр), иначе
function TAtolFRDevice.cmd_GetRegister(reg: int; param1: int = 0; param2: int = 0): TDataBuffer;
begin
  setCmdToOutBuffer($91).put(reg).put(param1).put(param2).flip();
  executeCmd();
  Result := inbuffer.rewind();
end;

function TAtolFRDevice.cmd_GetRegisterAsBCD(bcdlen: int; reg: int; param1: int = 0; param2: int = 0): int64;
begin
  Result := cmd_GetRegister(reg, param1, param2).getLongFromBCD(bcdlen);
end;





//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получить тип устройства.
function TAtolFRDevice.cmd_GetDevType(): TResult_GetDevType;
begin
  setCmdToOutBuffer($A5).flip();
  executeCmd(answerTimeout, 0);
  inbuffer.rewind();
  Result.protocol := inbuffer.get();
  Result.kind     := inbuffer.get();
  Result.model    := inbuffer.get();

  Result.mode     := inbuffer.getInt2();

  Result.version  := inbuffer.getLong5();

  Result.name     := inbuffer.getString(inbuffer.remaining());

end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос состояния ККТ.
function TAtolFRDevice.cmd_GetState(): TResult_GetState;
var yy, mm, dd, h, m, s: int;
begin
  setCmdToOutBuffer($3F).flip();
  executeCmd();

  inbuffer.rewind();
  Result.operator  := inbuffer.getLongFromBCD(1);
  Result.kktnumber := inbuffer.get();
  yy := inbuffer.get() + 2000;
  mm := inbuffer.get();
  dd := inbuffer.get();
  h := inbuffer.get();
  m := inbuffer.get();
  s := inbuffer.get();
  Result.dt             := dtwParse(Format('%d.%d.%d %d:%d:%d', [dd,mm,yy,h,m,s]), '');
  Result.flags          := inbuffer.get();
  Result.RNM            := inbuffer.getInt() and $FFFFFFFF;
  Result.model          := inbuffer.get();
  Result.fwversion      := inbuffer.getIntFromString(2);
  Result.mode           := inbuffer.get();
  Result.checknumber    := inbuffer.getIntFromBCD(2);
  Result.sessionnumber  := inbuffer.getIntFromBCD(2);
  Result.checkstate     := inbuffer.get();
  Result.checksum       := inbuffer.getLong5();
  Result.dotpos         := inbuffer.get();
  Result.port           := inbuffer.get();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос текущего режима и флагов состояния.
function TAtolFRDevice.cmd_GetModeState(): TResult_GetModeState;
begin
  setCmdToOutBuffer($45).flip();
  executeCmd(answerTimeout, 2);
  inbuffer.rewind();
  Result.mode  := inbuffer.get();
  Result.flags := inbuffer.get(); 
end;




//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Демонстрационная печать.
// тип печатаемого документа:
//   0 – Демонстрационная печать,
//   1 – Информация о ККТ (после выполнения ККТ переходит до перезагруки на скорость 4800!),
//   3 – Технологический прогон,
//   6 – Печать диагностики соединения с ОФД (если есть ошибки соединения с ОФД - выдаст).
procedure TAtolFRDevice.cmd_PrintDemo(kind: int);
begin
  setCmdToOutBuffer($82).put(1).put(kind).put(0).flip();
  executeCmd();
end;




end.





// Поискать завтра стабилизатор питания для штриха - купить+поставить и поглядеть поможет это стабильности или нет.
// Узнать, есть ли где взять для тестов Штрих-М-01Ф... проверить работу на стабильность.
// Уточнить во ФРОСТе когда можно будет взять погонять 55 и 77 атолы - 22 как-то так себе (время отклика)...
// Надо тестить и решать что всётаки брать - АТОЛ или ШТРИХ.

// Почему нет команды "продвинуть документ"??? (приходится давать кучу команд печати пустой строки!)
// При проблемах с бумагой - нет команды продолжить печать чека (после устранения проблем с бумагой).
// При выключении ККТ результаты выполнения последней команды пропадают (!) ??? Т.е. чек потерян будет?
// Таймауты просто чудовищные в протоколе - в 5-10 раз больше чем у Штриха.
// Нет команды печати рекламного текста из настроек?
// Не буферизируется печать строк при печати в чеке??? Т.е. при повторе чека напечатанных вручную строк не будет?

// 



end.




function TAtolFRDevice.cmd_GetFontParams(fontid: int = 1): TResult_GetFontParams;
begin
  outbuffer.reset().put($26).putInt(psw).put(fontid).flip();
  executeCmd();
  FillChar(Result, sizeof(Result), 0);
  inbuffer.rewind();
  Result.fieldWidth := inbuffer.getInt2();
  Result.charWifth  := inbuffer.get();
  Result.charHeigth := inbuffer.get();
  Result.fontsCount := inbuffer.get();
end;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать жирной строки (шрифт 2)
procedure TAtolFRDevice.cmd_PrintBoldString(const s: string);
begin
  outbuffer.reset().put($12).putInt(psw).put(2).putString(s, 30).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать строки данным шрифтом
procedure TAtolFRDevice.cmd_PrintFontString(const s: string; fontnum: int);
begin
  outbuffer.reset().put($2F).putInt(psw).put(2).put(fontnum).putString(s, 60).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать заголовка документа
function TAtolFRDevice.cmd_PrintHeader(const title: string; num: int): int;
begin
  outbuffer.reset().put($18).putInt(psw).putZString(title, 30).putInt2(num).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запрос операционного регистра
function TAtolFRDevice.cmd_GetOperRegister(num: int): int;
begin
  outbuffer.reset().put($1B).putInt(psw).put(num).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Запись таблицы
procedure TAtolFRDevice.cmd_WriteTable(tab, row, field: int; const buf; len: int);
begin
  outbuffer.reset().put($1E).putInt(psw).put(tab).putInt2(row).put(field).putVar(buf, 0, len).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Чтение таблицы
procedure TAtolFRDevice.cmd_ReadTable(tab, row, field: int; var buf; maxlen: int);
begin
  outbuffer.reset().put($1F).putInt(psw).put(tab).putInt2(row).put(field).flip();
  executeCmd();
  inbuffer.rewind().getVar(buf, 0, min(maxlen, inbuffer.remaining()));
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Программирование времени
procedure TAtolFRDevice.cmd_SetTime(hh, mm, ss: int);
begin
  outbuffer.reset().put($21).putInt(psw).put(hh).put(mm).put(ss).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Программирование даты
procedure TAtolFRDevice.cmd_SetDate(dd, mm, yy: int);
begin
  outbuffer.reset().put($22).putInt(psw).put(dd).put(mm).put(yy).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Подтверждение программирования даты
procedure TAtolFRDevice.cmd_SetDateConfirm(dd, mm, yy: int);
begin
  outbuffer.reset().put($23).putInt(psw).put(dd).put(mm).put(yy).flip();
  executeCmd();
end;






//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открыть смену
procedure TAtolFRDevice.cmd_OpenSession();
begin
  outbuffer.reset().put($E0).putInt(psw).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Суточный отчет без гашения
procedure TAtolFRDevice.cmd_PrintXReport();
begin
  outbuffer.reset().put($40).putInt(psw).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отчет о закрытии смены
procedure TAtolFRDevice.cmd_PrintZReport();
begin
  outbuffer.reset().put($41).putInt(psw).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отчёт по секциям
procedure TAtolFRDevice.cmd_PrintSectionReport();
begin
  outbuffer.reset().put($42).putInt(psw).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отчёт по налогам
procedure TAtolFRDevice.cmd_PrintTaxReport();
begin
  outbuffer.reset().put($43).putInt(psw).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Конец Документа
procedure TAtolFRDevice.cmd_EndDocument(isad: boolean);
begin
  outbuffer.reset().put($53).putInt(psw).put(iif(isad, 1, 0)).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать рекламного текста
procedure TAtolFRDevice.cmd_PrintReclame();
begin
  outbuffer.reset().put($54).putInt(psw).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Внесение.
function TAtolFRDevice.cmd_IncomeMoneyCheck(sum: int64): int;
begin
  outbuffer.reset().put($50).putInt(psw).putLong5(sum).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Выплата.
function TAtolFRDevice.cmd_OutcomeMoneyCheck(sum: int64): int;
begin
  outbuffer.reset().put($51).putInt(psw).putLong5(sum).flip();
  executeCmd();
  Result := inbuffer.rewind(1).getInt2();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открыть чек: «0» – приход, «1» – расход, «2» – возврат прихода, «3» – возврат расхода.
procedure TAtolFRDevice.cmd_OpenCheck(kind: FR_CheckTypeEnum);
begin
  outbuffer.reset().put($8D).putInt(psw).put(ord(kind)).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрытие чека.
function TAtolFRDevice.cmd_CloseCheck(sum1, sum2, sum3, sum4: int64; tax1, tax2, tax3, tax4: int;
                                            discount: int; const text: string = ''): TResult_CloseCheck;
begin
  outbuffer.reset().put($85).putInt(psw)
    .putLong5(sum1).putLong5(sum2).putLong5(sum3).putLong5(sum4)
    .putInt2(discount)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putString(text, 40)
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
procedure TAtolFRDevice.cmd_AddSaleInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  outbuffer.reset().put($80).putInt(psw)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putString(text, 40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Добавление строки покупки в чек.
procedure TAtolFRDevice.cmd_AddPurchaseInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  outbuffer.reset().put($81).putInt(psw)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putString(text, 40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Возврат продажи
procedure TAtolFRDevice.cmd_AddSaleReturnInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  outbuffer.reset().put($82).putInt(psw)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putString(text, 40).flip();
  executeCmd();
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Возврат покупки
procedure TAtolFRDevice.cmd_AddPurchaseReturnInCheck(count, price: int64; section, tax1, tax2, tax3, tax4: int; const text: string);
begin
  outbuffer.reset().put($83).putInt(psw)
    .putLong5(count).putLong5(price).put(section)
    .put(tax1).put(tax2).put(tax3).put(tax4)
    .putString(text, 40).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Аннулирование чека.
procedure TAtolFRDevice.cmd_CancelCheck();
begin
  outbuffer.reset().put($88).putInt(psw).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Продолжение печати.
procedure TAtolFRDevice.cmd_ContinueCheckPrint();
begin
  outbuffer.reset().put($B0).putInt(psw).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать штрих-кода EAN-13.
procedure TAtolFRDevice.cmd_PrintBarCode(value: int64);
begin
  outbuffer.reset().put($C2).putInt(psw).putLong5(value).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Загрузка данных.
procedure TAtolFRDevice.cmd_LoadData(kind: int; blocknum: int; const buf; len: int);
begin
  outbuffer.reset().put($DD).putInt(psw)
    .put(kind).put(blocknum).putVar(buf, 0, len).flip();
  executeCmd();
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Печать QR штрих-кода.
function TAtolFRDevice.cmd_PrintQRCode(len, firstblocknum, version, mask, dotsize, erclevel, align: int): TResult_PrintXBarCode;
begin
  Result := cmd_PrintXBarCode(3 {131}, len, firstblocknum, version, mask, dotsize, 0, erclevel, align);
end;


end.








