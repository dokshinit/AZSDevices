////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2017, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_TopazFDDevice;

interface

uses
  Windows, SysUtils, dant_utils, dant_log, dant_crc, dant_DataBuffer, dant_RS232Driver;

// Драйвер для управления ТРК Топаз по протоколу АЗС АЗТ 2.0.

type
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Исключения.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Общее исключение для TShtrihFRDevice
  TExTopazFDDevice = class(TExError);

  // Неверная команда в буфере отправки (или длина).
  TExBuild = class(TExTopazFDDevice);
  // Ошибки при неверных физических данных.
  TExProtocol = class(TExTopazFDDevice);
  // При исчерпании попыток приёма\отправки.
  TExAttempt = class(TExTopazFDDevice);

  //
  TExUnsupportedCommand = class(TExTopazFDDevice);
  //
  TExCannotExecute = class(TExTopazFDDevice);


  TValue = record
    value: int64;
    power: int;
  end;

  TResult_GetState = record
    state: int;
    reason: int;
    flags: int;
  end;

  TResult_GetFilling = record
    volume: int64;
    sum: int64;
    price: int64;
  end;

  TResult_GetCounter = record
    volume: int64;
    sum: int64;
  end;

  TResult_GetExtState = record
    intstate, extstate: int;
    nover, nstep, ownstate: int;
  end;

  TResult_GetError = record
    iderror, idadd1, idadd2: int;
  end;

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  Устройство-ТРК Топаз.
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  TTopazFDDevice = class
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

      // Кол-во разрядов для внутреннего оперирования! Не имеет отношение к табло!!!
      volumeDigits: int; // Кол-во разрядов для дозы.
      priceDigits: int;  // Кол-во разрядов для цены.
      sumDigits: int;    // Кол-во разрядов для стоимости.

    public
      isCmdLogging: boolean;

    public
      constructor Create(const devname: String; const portname: string);
      destructor Destroy(); override;
      function getDriver(): TRS232Driver;
      function getDeviceName(): String;
      procedure open();
      function  openSafe(): boolean;
      procedure closeSafe();

    protected
      procedure executeCmd(channel: int);
      procedure cmd_GetParam(channel: int; idparam: int);

    public
      function  cmd_GetState(channel: int): TResult_GetState;
      procedure cmd_Accept(channel: int);
      procedure cmd_Reset(channel: int);
      function  cmd_GetFillingVolume(channel: int): int64;
      function  cmd_GetFilling(channel: int): TResult_GetFilling;
      function  cmd_GetCounter(channel: int): TResult_GetCounter;
      procedure cmd_Confirm(channel: int);
      function  cmd_GetExtState(channel: int): TResult_GetExtState; // Не поддерживается Топаз106к2-2мр!
      function  cmd_GetProtocolVersion(channel: int): int;
      procedure cmd_SetPrice(channel: int; price: int64);
      procedure cmd_SetVolume(channel: int; volume: int64; isfull: boolean);
      procedure cmd_Refill(channel: int); // долив.
      procedure cmd_ForceStart(channel: int);
      procedure cmd_SetCommonParameter(idparam: int; const value: string);
      function  cmd_GetParamCodes(channel: int): string;
      function  cmd_GetExtParamCodes(channel: int): string;
      function  cmd_GetParamAsString(channel: int; idparam: int): string;
      function  cmd_GetParamAsLong(channel: int; idparam: int): int64;
      function  cmd_GetParamAsInt(channel: int; idparam: int): int;
      function  cmd_GetDoseVolume(channel: int): int64;
      procedure cmd_ShowError(channel: int; iderror: int; time: int);
      function  cmd_GetError(channel: int): TResult_GetError;
      // Ext protocol...
      function  cmdext_GetParamAsValue(channel: int; idparam: int): TValue;
  end;

const
  // Состояния раздаточного рукава ТРК.
  FD_STATE_OFF    = 0; // ТРК выключена, пистолет повешен.
  FD_STATE_ON     = 1; // ТРК выключена, пистолет снят.
  FD_STATE_ACCEPT = 2; // ТРК выключена, ожидание санкционирования налива.
  FD_STATE_FUEL   = 3; // ТРК включена, отпуск топлива.
  FD_STATE_FINISH = 4; // ТРК выключена, налив завершен, ожидание подтверждения отпуска.

  // Причины состояний (только для FD_STATE_FINISH), как дополнительный флаг состояния.
  FD_REASON_NORMAL = 0; // Отпущенная доза меньше или соответствует заданной.
  FD_REASON_OVER   = 1; // Перелив (или несанкционированный отпуск).
    // Примечание: Несанкционированный отпуск возникает при обнаружении отпуска топлива при отсутствии команды
    // САНКЦИОНИРОВАНИЕ или при наличии этой команды, но без пуска ТРК клиентом. Также несанкционированным отпуском
    // считается любой повторно зафиксированный отпуск НП после окончания отпуска заданной дозы, поэтому переход ТРК в
    // статус '4'(0x34) + '1'(0х31) возможен из любого состояния.

  // Флаги состояний (только для FD_STATE_FINISH).
  FD_STATEFLAG_ERROR = 1; // Флаг наличия внутренней ошибки (битовое поле).

  
implementation

uses
  dant_SerialPort;

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  ПЕРВЫЙ УРОВЕНЬ: СООБЩЕНИЯ + ТРАНСПОРТНЫЙ (фреймы) + ФИЗИЧЕСКИЙ
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Служебные байт-коды протокола.
  const STX = $02; // Начало команды. $2,$7-$14
  const ETX = $03; // Конец команды.
  const ACK = $06; // Подтверждение успешного выполнения.
  const NAK = $15; // Подтверждение неверной команды.
  const CAN = $18; // Подтверждение невозможности выполнить команду в данный момент.
  const DEL = $7F; // Префикс пакета команды\ответа.

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Пинпад.
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TTopazFDDevice.Create(const devname: string; const portname: string);
var i: int;
begin
  inherited Create();

  self.devname := devname;

  // Буферы для команд.
  outbuffer := TDataBuffer.Create(300, CHARSET_WIN1251);
  inbuffer  := TDataBuffer.Create(300, CHARSET_WIN1251);

  transportTimeout             := 50;
  transportConfirmationTimeout := 2 * transportTimeout;
  answerTimeout                := 400;

  // RS232
  self.driver := TRS232Driver.Create(devname, portname)
                    .bitrate(dant_SerialPort.BAUDRATE_4800)
                    .databits(dant_SerialPort.DATABITS_7)
                    .stopbits(dant_SerialPort.STOPBITS_2)
                    .parity(dant_SerialPort.PARITY_EVEN)
                    .timeout(transportTimeout);

  volumeDigits := 5;
  priceDigits := 4;
  sumDigits := 7;

  isCmdLogging := false;
end;


destructor TTopazFDDevice.Destroy();
begin
  closeSafe();

  FreeAndNilSafe(driver);
  FreeAndNilSafe(outbuffer);
  FreeAndNilSafe(inbuffer);

  inherited;
end;


// Получение драйвера устройства (RS232).
function TTopazFDDevice.getDriver(): TRS232Driver;
begin
  Result := driver;
end;


// Получение имени устройства.
function TTopazFDDevice.getDeviceName(): String;
begin
  Result := devname;
end;


procedure TTopazFDDevice.open();
begin
  driver.open();
end;

function TTopazFDDevice.openSafe(): boolean;
begin
  try
    driver.open();
    Result := true;
  except
    Result := false;
  end;
end;

// Метод автозавершения работы с устройством.
procedure TTopazFDDevice.closeSafe();
begin
  // Закрываем драйвер.
  if (driver <> nil) then driver.closeSafe();
end;


//procedure TTopazFDDevice.dropReadSafe();
//var count: int;
//begin
//  try
//    while (true) do
//    begin
//      count := driver.purgeRead();
//      if (isPortLogging) then logMsg('dropReadSafe(): %d bytes', [count]);
//
//      driver.write(NAK);
//      // Когда нет входящих данных - цикл завершится исключением по таймауту.
//      driver.read(transportConfirmationTimeout);
//    end;
//  except
//  end;
//end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка команды (из исходящего буфера, длина окна = длина данных, позиция = отправлено данных)
// channel = 0 - широковещательная команда, channel = 1..225 - для указанного канала.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TTopazFDDevice.executeCmd(channel: int);
var bSTX, bCHANNEL, len, v, attempt, crccalc, crc, i, answ, cov: int;
begin
  if (isCmdLogging) then logMsg('Command(%d)[%d]: %s', [channel, outbuffer.length(), outbuffer.getHexAt(0, outbuffer.length())]);

  // Проверяем буфер команды.
  len := outbuffer.length();
  if (len > 255) then raise TExBuild.Create('Длина команды больше 255! (%d)', [len]);

  // Вычисляем заголовочные байты.
  if ((channel < 0) or (channel > 225)) then raise TExBuild.Create('');
  bSTX := iif(channel <= 15, STX, 6 + (channel div 15)); // STX=$2,$7-$14
  bCHANNEL := $20 + (channel mod 15); // канал 0x21-0x2F

  attempt := 3;
  while (true) do
  begin
    try
      //////////////////////////////////////////////////////////////////////////////////////////////
      // Отбрасываем все данные из буфера чтения (мусор - непринятые результаты предыдущих команд). Могут быть?
      answ := 0;
      i := driver.readAllAndDrop();

      //////////////////////////////////////////////////////////////////////////////////////////////
      // Отправляем команду.
      outbuffer.rewind();
      driver.write(DEL);
      driver.write(bSTX);
      crccalc := 0; // Расчётная CRC.
      if (channel <> 0) then
      begin
        driver.write(bCHANNEL);
        driver.write(bCHANNEL xor $7F);
        crccalc := crccalc xor bCHANNEL;
      end;
      for i:=0 to len-1 do
      begin
        v := outbuffer.get();
        driver.write(v);
        driver.write(v xor $7F); // Комплементарный байт.
        crccalc := crccalc xor v; // Обновляем расчётную CRC.
      end;
      driver.write(ETX);
      crccalc := (crccalc xor ETX) or $40; // Сумма захватывает один ETX.
      driver.write(ETX);
      driver.write(crccalc);

      //////////////////////////////////////////////////////////////////////////////////////////////
      // Ожидаем потверждения приёма.
      inbuffer.reset();
      v := driver.read(answerTimeout);
      if (v <> DEL) then raise TExProtocol.Create('Ожидается DEL в ответе!');

      answ := driver.read();
      case answ of
        ACK: // Получено подтверждение - разрываем цикл.
            begin
              inbuffer.flip();
              if (isCmdLogging) then logMsg('Result[%d]: ACK');
              exit;
            end;
        STX:
            begin
              crccalc := 0;
              while (true) do // Читаем в цикле данные пока не дойдем до конца ответа.
              begin
                v := driver.read();
                if (v >= $20) then // Это данные.
                begin
                  cov := driver.read(); // Считываем комплементарный байт к данным.
                  if (cov < $21) then raise TExProtocol.Create('Ко-значение вне диапазона! (value=0x%.2X co=0x%.2X)', [v, cov]);
                  if ((v xor $7F) <> cov) then raise TExProtocol.Create('Неверное ко-значение! (value=0x%.2X co=0x%.2X)', [v, cov]);
                  crccalc := crccalc xor v;
                  inbuffer.put(v);
                end else
                begin // Не данные - ожидаем завершающий блок.
                  if (v <> ETX) then raise TExProtocol.Create('Ожидается ETX1! (0x%.2X)', [v]);
                  crccalc := (crccalc xor ETX) or $40;
                  v := driver.read();
                  if (v <> ETX) then raise TExProtocol.Create('Ожидается ETX2! (0x%.2X)', [v]);
                  crc := driver.read();
                  if (crc <> crccalc) then TExProtocol.Create('Контрольная сумма! (calc=0x%.2X crc=0x%.2X)', [crccalc, crc]);
                  break; // Прерываем цикл чтения.
                end;
              end;
              inbuffer.flip();
              if (isCmdLogging) then logMsg('Result[%d]: %s', [inbuffer.length(), inbuffer.getHexAt(0, inbuffer.length())]);
              exit;
            end;
        NAK: raise TExUnsupportedCommand.Create(); // Если не поддерживается - нет смысла повторять попытки!
        CAN: raise TExCannotExecute.Create();
        else raise TExProtocol.Create('Неверный символ начала ответа! (0x%.2X)', [answ]);
      end;

    except
      // При любых ошибках - прерывание, кроме ошибок протокола - тогда новая попытка.
      on ex: TExProtocol do if (attempt = 1) then raise TExAttempt.Create(ex.Message); // Если попытки исчерпаны - пробрасываем.
      // Прочие пробрасываются.
    end;
  end;
  // До этого места никогда не должно доходить!
end;









//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  КОМАНДЫ ПРОТОКОЛА АЗС АЗТ 2.0
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x31 Запрос статуса ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function TTopazFDDevice.cmd_GetState(channel: int): TResult_GetState;
begin
  outbuffer.reset().put($31).flip();
  executeCmd(channel);
  inbuffer.rewind();
  Result.state  := inbuffer.get() and $F;
  Result.reason := 0;
  Result.flags  := 0;
  if (inbuffer.hasRemaining()) then
  begin
    Result.reason := inbuffer.get() and $F;
    if (inbuffer.hasRemaining()) then Result.flags := inbuffer.get() and $F;
  end;
end;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x32 Санкционирование ТРК. Возможные статусы ТРК до запроса – '0', '1' или '8'. Возможные статусы ТРК после запроса – '2'.
procedure TTopazFDDevice.cmd_Accept(channel: int);
begin
  outbuffer.reset().put($32).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x33 Сброс ТРК. Возможные статусы ТРК до запроса – '2' ,'3' или '8'. Возможные статусы ТРК после запроса – '4' + '0' или '4'+'1'; '1' или '0'.
procedure TTopazFDDevice.cmd_Reset(channel: int);
begin
  outbuffer.reset().put($33).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x34 Запрос текущих данных отпуска топлива. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetFillingVolume(channel: int): int64;
begin
  outbuffer.reset().put($34).flip();
  executeCmd(channel);
  Result := inbuffer.rewind().getLongFromString(6);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x35 Запрос полных данных отпуска топлива. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняютсяa.
function  TTopazFDDevice.cmd_GetFilling(channel: int): TResult_GetFilling;
begin
  outbuffer.reset().put($35).flip();
  executeCmd(channel);
  inbuffer.rewind();
  Result.volume := inbuffer.getLongFromString(volumeDigits);
  Result.sum    := inbuffer.getLongFromString(sumDigits);
  Result.price  := inbuffer.getLongFromString(priceDigits);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x36 Запрос показаний суммарников. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetCounter(channel: int): TResult_GetCounter;
var n: int;
begin
  outbuffer.reset().put($36).flip();
  executeCmd(channel);
  n := inbuffer.rewind().remaining() div 2;
  Result.volume := inbuffer.getLongFromString(n);
  Result.sum    := inbuffer.getLongFromString(n);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x38 Подтверждение записи итогов отпуска. Возможные статусы ТРК до запроса – '4' + '0' или '4' + '1'. Возможные статусы ТРК после запроса – '0' или '1'.
procedure TTopazFDDevice.cmd_Confirm(channel: int);
begin
  outbuffer.reset().put($38).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x39 Запрос дополнительного статуса ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
// Не поддерживается Топаз106к2-2мр!
function  TTopazFDDevice.cmd_GetExtState(channel: int): TResult_GetExtState;
begin
  outbuffer.reset().put($39).flip();
  executeCmd(channel);
  inbuffer.rewind();
  Result.intstate := inbuffer.getIntFromString(1);
  Result.extstate := inbuffer.getIntFromString(1);
  Result.nover    := inbuffer.getIntFromString(2);
  Result.nstep    := inbuffer.getIntFromString(2);
  Result.ownstate := inbuffer.getIntFromString(3);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x50 Запрос номера версии протокола. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetProtocolVersion(channel: int): int;
begin
  outbuffer.reset().put($50).flip();
  executeCmd(channel);
  Result := inbuffer.rewind().getIntFromString(8);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x51 Установка цены за литр. Возможные статусы ТРК до запроса – '0', '1' или '8'. Возможные статусы ТРК после запроса – не меняются.
procedure TTopazFDDevice.cmd_SetPrice(channel: int; price: int64);
begin
  outbuffer.reset().put($51).putLongAsString(price, 4).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x54 Установка дозы отпуска топлива в литрах. Возможные статусы ТРК до запроса – '0', '1'. Возможные статусы ТРК после запроса – не меняются.
procedure TTopazFDDevice.cmd_SetVolume(channel: int; volume: int64; isfull: boolean);
begin
  outbuffer.reset().put($54).putLongAsString(volume, 5).put(iif(isfull, $31, $30)).flip(); // Поле юстировки не используем!
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x55 Долив дозы. Возможные статусы ТРК до запроса – '0' + '1'. Возможные статусы ТРК после запроса – не меняются.
procedure TTopazFDDevice.cmd_Refill(channel: int);
begin
  outbuffer.reset().put($55).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x56 Безусловный старт раздачи. Команда вызывает пуск колонки НЕЗАВИСИМО от положения раздаточного крана.
//      Востальном эффект от команды полностью аналогичен пуску ТРК при снятии крана (нажатии кнопки ПУСК/СТОП).
//      Возможные статусы ТРК до запроса – '2'. Возможные статусы ТРК после запроса – '3'.
procedure TTopazFDDevice.cmd_ForceStart(channel: int);
begin
  outbuffer.reset().put($56).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x57 Задание общих параметров. Широковещательная команда, принимается одновременно всеми ТРК на линии.
//      Возможные статусы ТРК до запроса – определяются номером параметра. Возможные статусы ТРК после запроса – не меняются.
procedure TTopazFDDevice.cmd_SetCommonParameter(idparam: int; const value: string);
var i: int;
begin
  outbuffer.reset().put($57).put($30 or (idparam and $F));
  for i:=1 to Length(value) do outbuffer.put($30 or (ord(value[i]) and $F));
  outbuffer.flip();
  executeCmd(0);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E чтение кодов параметров, поддерживаемых ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetParamCodes(channel: int): string;
var i, len: int;
begin
  outbuffer.reset().put($4E).flip();
  executeCmd(channel);
  len := inbuffer.rewind().remaining();
  SetLength(Result, len);
  for i:=1 to len do Result[i] := chr(inbuffer.get());
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E чтение кодов расширенных параметров, поддерживаемых ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetExtParamCodes(channel: int): string;
var i, len: int;
begin
  outbuffer.reset().put($4E).put($5E).flip();
  executeCmd(channel);
  i := inbuffer.rewind().get();
  if (i <> $5E) then raise TExProtocol.Create('Неверный маркер! (0x%.2X <> 0x5E)', [i]);
  len := inbuffer.remaining();
  SetLength(Result, len);
  for i:=1 to len do Result[i] := chr(inbuffer.get() + $2E);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до запроса – все допустимые.
// ИСПОЛЬЗУЕТСЯ ДРУГИМИ МЕТОДАМИ ДЛЯ ПОСЛЕДУЮЩЕЙ ИНТЕРПРЕТАЦИИ ИНФОРМАЦИИ.
procedure TTopazFDDevice.cmd_GetParam(channel: int; idparam: int);
begin
  if (idparam < $5E) then // Обычный параметр.
  begin
    outbuffer.reset().put($4E).put(idparam).flip();
    executeCmd(channel);
    if ((not inbuffer.rewind().hasRemaining(2)) or (inbuffer.get() <> idparam)) then raise TExProtocol.Create('Неверный ответ!');
  end else
  begin // Расширенный параметр.
    outbuffer.reset().put($4E).put($5E).put(idparam - $2E).flip();
    executeCmd(channel);
    if ((not inbuffer.rewind().hasRemaining(3)) or (inbuffer.get() <> $5E) or (inbuffer.get() <> (idparam - $2E))) then raise TExProtocol.Create('Неверный ответ!');
  end;
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до запроса – все допустимые.
function  TTopazFDDevice.cmd_GetParamAsString(channel: int; idparam: int): string;
var i: int;
begin
  cmd_GetParam(channel, idparam);
  Result := inbuffer.getRawStringAt(inbuffer.pos(), inbuffer.remaining());
  // Преобразование строки из вида: 0x?0..0x?F -> '0'..'F'.
  for i:=1 to Length(Result) do Result[i] := IntToHexChar(ord(Result[i]) and $F);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до запроса – все допустимые.
function  TTopazFDDevice.cmd_GetParamAsLong(channel: int; idparam: int): int64;
begin
  cmd_GetParam(channel, idparam);
  Result := inbuffer.getLongFromString(inbuffer.remaining());
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до запроса – все допустимые.
function  TTopazFDDevice.cmd_GetParamAsInt(channel: int; idparam: int): int;
begin
  cmd_GetParam(channel, idparam);
  Result := inbuffer.getIntFromString(inbuffer.remaining());
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x58 Чтение заданной дозы. Возможные статусы ТРК до запроса – '0','1' или '8'. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetDoseVolume(channel: int): int64;
begin
  try
    outbuffer.reset().put($58).flip();
    executeCmd(channel);
    Result := inbuffer.rewind().getLongFromString(inbuffer.remaining());
  except
    on ex: TExCannotExecute do Result := -1; // Маскируем исключение - тут оно означает, что доза не была задана или состояние неверное.
  end;
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x5B Сигнализация о внешней ошибке. Возможные статусы ТРК до запроса – '0','1'. Возможные статусы ТРК после запроса – не меняются.
procedure TTopazFDDevice.cmd_ShowError(channel: int; iderror: int; time: int);
begin
  outbuffer.reset().put($5B).putLongAsString(iderror, 3).putLongAsString(time, 2).flip();
  executeCmd(channel);
end;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x5C Запрос кода внутренней ошибки. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса – не меняются.
function  TTopazFDDevice.cmd_GetError(channel: int): TResult_GetError;
begin
  outbuffer.reset().put($5C).flip();
  executeCmd(channel);
  inbuffer.rewind();
  Result.iderror := inbuffer.getIntFromString(3);
  Result.idadd1  := 0;
  Result.idadd2  := 0;
  if (inbuffer.hasRemaining(2)) then
  begin
    Result.idadd1 := inbuffer.getIntFromString(2);
    if (inbuffer.hasRemaining(2)) then Result.idadd2 := inbuffer.getIntFromString(2);
  end;
end;



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до запроса – все допустимые.
function  TTopazFDDevice.cmdext_GetParamAsValue(channel: int; idparam: int): TValue;
var bb, i, sign: int;
  v: int64;

  function getValue(): int64;
  var n: int;
  begin
    Result := 0;
    while (inbuffer.hasRemaining()) do
    begin
      n := inbuffer.get();
      if ((n and $F0) <> $30) then begin inbuffer.shift(-1); break; end;
      Result := (Result * 10) + (n and $F);
    end;
  end;

begin
  i := 1;
  if (idparam > 10) then i := 2;
  if (idparam > 100) then i := 3;

  outbuffer.reset().put($4C).put($51).putLongAsString(idparam, i).flip();
  executeCmd(channel);
  if (not inbuffer.rewind().hasRemaining(1)) then raise TExProtocol.Create('Слуишком короткий ответ!');
  bb := inbuffer.get();
  case bb of
    $51,$52,$53: ;
    $54: raise TExProtocol.Create('Ошибка команды ТРК! (%d)', [getValue()]);
    else raise TExProtocol.Create('Неверный ответ! (0x%.2X)', [bb]);
  end;
  v := getValue();
  if (v <> idparam) then raise TExProtocol.Create('Неверный код параметра в ответе! (%d <> answ:%d)', [idparam, v]);

  Result.value := 0;
  Result.power := 1; // По умолчанию!
  if (inbuffer.hasRemaining()) then
  begin
    i := inbuffer.get();
    case i of
      $41: sign := 1;
      $42: sign := -1;
      else raise TExProtocol.Create('Ожидается маркер мантиссы! (0x%.2X)', [i]); // Тут может быть стоит просто выходить (вдруг несколько чисел в ответе?)
    end;
    Result.value := getValue() * sign;
  end;
  if (bb = $53) then raise TExProtocol.Create('Ошибка параметра ТРК! (%d)', [Result.value]);

  if (inbuffer.hasRemaining()) then
  begin
    Result.power := 0; // Обнуляем чтобы заполнить.
    case inbuffer.get() of
      $43: sign := 1;
      $44: sign := -1;
      else raise TExProtocol.Create('Ожидается маркер степени! (0x%.2X)', [i]); // Тут может быть стоит просто выходить (вдруг несколько чисел в ответе?)
    end;
    Result.power := getValue() * sign;
  end;
end;


end.








