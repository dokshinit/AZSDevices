////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////
unit dant_RCClient;

interface

uses
  WinSock, dant_log, dant_NetUDPClient, dant_DataBuffer;


const
  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Код ошибки в исключениях.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  ERR_REQ_BUILD = 1;
  ERR_REQ_SEND = 2;
  ERR_ANSW_RECEIVE = 3;
  ERR_ANSW_PARSE = 4;

  // Успешно.
  RESULT_OK = 0;
  // Другая ошибка.
  RCRESULT_ERROR = 100;

  // Неверное состояние.
  RESULT_RESULTNOTREADY = 1;
  // Повтор команды которая уже есть в слотах.
  RESULT_DUPLICATECOMMAND = 2;
  // Нет свободных слотов для запуска команды.
  RESULT_CANNOTEXECUTE = 3;
  // Слот не найден (для команды).
  RESULT_COMMANDNOTFOUND = 4;
  // Неверный формат сообщения.
  RESULT_WRONGFORMAT = 5;
  // Неверное значение.
  RESULT_WRONGVALUE = 6;
  // Неверный ResultID.
  RESULT_WRONGFINALIZATIONID = 7;


type
  TExRequestError = class (TExError);
  TExTimeout = class (TExError);

  TExAnswerError = class (TExError);
  TExSBError = class (TExError);

  TExResultError = class (TExError);
  
  //////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  МЕТАДАННЫЕ
  //
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TRCMeta = class
    public
      senderID: Integer;
      messageID: Int64;
      requestType: Integer;
      commandID: Int64;
      executeTimeout: Integer;
      finalizationID: Int64;

      answerErrorID: Integer;
      answerErrorMessage: string;

      constructor Create(); overload;
      constructor Create(src: TRCMeta); overload;

      function parse(isanswer: Boolean; buf: TDataBuffer): TDataBuffer;
      function parseRequest(buf: TDataBuffer): TDataBuffer;
      function parseAnswer(buf: TDataBuffer): TDataBuffer;

      function build(isanswer: Boolean; buf: TDataBuffer): TDataBuffer;
      function buildRequest(buf: TDataBuffer): TDataBuffer;
      function buildAnswer(buf: TDataBuffer): TDataBuffer;

      function toString(): string;
  end;


  //////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  РЕЗУЛЬТАТЫ ЗАПРОСОВ
  //
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TRCResultGetState = class(TRCMeta)
  public
    // Время последнего запуска сервиса.
    lastStartTime: Int64;
    // Время последнего перезапуска сервиса (после ошибок).
    lastAutoRestartTime: Int64;
    // Время последней остановки сервиса.
    lastStopTime: Int64;

    constructor Create(src: TRCMeta; buffer: TDataBuffer); overload;
    constructor Create(src: TRCResultGetState); overload;
  end;

  TRCResultRestart = class (TRCMeta);
  TRCResultStop = class (TRCMeta);
  TRCResultHalt = class (TRCMeta);
  TRCResultExecute = class (TRCMeta);

  
  //////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  АБСТРАКТНЫЙ КЛИЕНТ
  //
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TRCClient = class
  private
    channel: TNetUDPClient;
    clientID: Integer;
    address: TSockAddr;
    serverHost: String;
    serverPort: Integer;
    clientPort: Integer;
    messageID, commandID: Int64;

  protected
    ioBuffer, tmpBuffer: TDataBuffer;

    function generateMessageID(): Int64;
    function generateCommandID(): Int64;

    procedure Request(answertimeout: Integer; meta: TRCMeta; body: TDataBuffer);

  public
    constructor Create(id: Integer; const srvhost: string; srvport, cliport: Integer; maxsize: Integer);
    destructor Destroy(); override;

    function getClientID(): Integer;
    function getServerHost(): String;
    function getServerPort(): Integer;
    function getClientPort(): Integer;
    function getServerAddress(): TSockAddr;

    function remoteGetState(answertimeout: Integer): TRCResultGetState;
    function remoteRestart(answertimeout: Integer; restarttimeout: Integer): TRCResultRestart;
    function remoteStop(answertimeout: Integer): TRCResultStop;
    function remoteHalt(answertimeout: Integer): TRCResultHalt;
    function remoteExecute(answertimeout, executetimeout: Integer; buf: TDataBuffer): TRCResultExecute;
  end;



implementation

uses
  SysUtils, dant_utils, dant_crc;


const
  // Получение состояния сервиса.
  REQ_TYPE_GETSTATE = 1;
  // Выполнение команды.
  REQ_TYPE_EXECUTE = 2;
  // Получение результата выполнения команды.
  REQ_TYPE_GETRESULT = 3;
  // Финализация результата (освобождение результата).
  REQ_TYPE_FINALIZE = 4;
  // Остановка сервиса (установка флага прерывания).
  REQ_TYPE_STOP = 100;



////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  МЕТАДАННЫЕ
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TRCMeta.Create();
begin
  senderID       := 0;
  messageID      := 0;
  requestType    := 0;
  commandID      := 0;
  executeTimeout := 0;
  finalizationID := 0;

  answerErrorID  := 0;
  answerErrorMessage := '';
end;


constructor TRCMeta.Create(src: TRCMeta);
begin
  senderID       := src.senderID;
  messageID      := src.messageID;
  requestType    := src.requestType;
  commandID      := src.commandID;
  executeTimeout := src.executeTimeout;
  finalizationID := src.finalizationID;

  answerErrorID  := src.answerErrorID;
  answerErrorMessage := src.answerErrorMessage;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.parse(isanswer: Boolean; buf: TDataBuffer): TDataBuffer;
begin
  try
    senderID := buf.getInt();
    messageID := buf.getLong();
    requestType := buf.get();
    if (not requestType in [1,2,3,4,100]) then
      raise TExResultError.Create(RESULT_WRONGVALUE, 'Неверный код команды сервиса! {id=%d}', [requestType]);

    commandID          := 0;
    executeTimeout     := 0;
    finalizationID     := 0;
    answerErrorID      := RESULT_OK;
    answerErrorMessage := '';

    case requestType of
      REQ_TYPE_EXECUTE:
          begin
            // Для команды EXECUTE должны следовать дополнительные параметры для исполнения.
            commandID := buf.getLong();
            executeTimeout := buf.getInt();
          end;
      REQ_TYPE_GETRESULT:
          begin
            // Для команды RESULT должны следовать дополнительные параметры.
            commandID := buf.getLong();
            if (isanswer) then
              finalizationID := buf.getLong(); // Ответ содержит также cmdID для финализации.
          end;
      REQ_TYPE_FINALIZE:
          begin
            // Для команды FINALIZE должны следовать дополнительные параметры.
            commandID := buf.getLong();
            finalizationID := buf.getLong();
          end;
    end;       

    if (isanswer) then // Для ответа добавляем результат.
    begin
      answerErrorID := buf.getInt2();
      answerErrorMessage := '';
      if ((answerErrorID <> RESULT_OK) and (buf.remaining() > 0)) then
        answerErrorMessage := buf.getString(buf.remaining());
    end;
  except
    on ex: TExResultError do raise;
    on ex: Exception do
      raise TExResultError.Create(RESULT_WRONGFORMAT, 'Ошибка при разборе заголовка сообщения - %s!', [ex.Message]);
  end;
  Result := buf;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.parseRequest(buf: TDataBuffer): TDataBuffer;
begin
  Result := parse(False, buf);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.parseAnswer(buf: TDataBuffer): TDataBuffer;
begin
  Result := parse(True, buf);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.build(isanswer: Boolean; buf: TDataBuffer): TDataBuffer;
begin
  try
    if (requestType = 0) then raise TExResultError.Create(RESULT_WRONGVALUE, 'Не задана команда!');
    buf.putInt(senderID).putLong(messageID);
    buf.put(requestType);
    case (requestType) of
      REQ_TYPE_EXECUTE:
          begin
            // Для команды EXECUTE должны следовать дополнительные параметры для исполнения.
            buf.putLong(commandID).putInt(executeTimeout);
          end;
      REQ_TYPE_GETRESULT:
          begin
            // Для команды RESULT должны следовать дополнительные параметры.
            buf.putLong(commandID);
            if (isanswer) then buf.putLong(finalizationID); // Ответ содержит также cmdID для финализации.
          end;
      REQ_TYPE_FINALIZE:
          begin
            // Для команды FINALIZE должны следовать дополнительные параметры.
            buf.putLong(commandID).putLong(finalizationID);
          end;
    end;      
    if (isanswer) then // Для ответа добавляем результат.
    begin
      buf.putInt2(answerErrorID);
      if ((answerErrorID <> RESULT_OK) and (answerErrorMessage <> '')) then buf.putString(answerErrorMessage);
    end;
  except
    on ex: TExResultError do raise;
    on ex: Exception do raise TExResultError.Create(RESULT_WRONGFORMAT, 'Ошибка при построении сообщения - %s!', [ex.Message]);
  end;
  Result := buf;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.buildRequest(buf: TDataBuffer): TDataBuffer;
begin
  Result := build(False, buf);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.buildAnswer(buf: TDataBuffer): TDataBuffer;
begin
  Result := build(True, buf);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCMeta.toString(): string;
begin
  Result := Format('senderID=0x%X messageID=0x%X requestType=%d [timeout=%d finID=0x%X errID=%d errMsg=%s]',
                   [senderID, messageID, requestType, executeTimeout, finalizationID, answerErrorID, answerErrorMessage]);
end;




////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  РЕЗУЛЬТАТ ЗАПРОСА: GETSTATE
//
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TRCResultGetState.Create(src: TRCMeta; buffer: TDataBuffer);
begin
  inherited Create(src);
  lastStartTime := buffer.getLong();
  lastAutoRestartTime := buffer.getLong();
  lastStopTime := buffer.getLong();
end;


constructor TRCResultGetState.Create(src: TRCResultGetState);
begin
  inherited Create(src);
  lastStartTime := src.lastStartTime;
  lastAutoRestartTime := src.lastAutoRestartTime;
  lastStopTime := src.lastStopTime;
end;




////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  АБСТРАКТНЫЙ КЛИЕНТ
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TRCClient.Create(id: Integer; const srvhost: String; srvport, cliport: Integer; maxsize: Integer);
begin
  serverHost := srvhost;
  serverPort := srvport;
  clientPort := cliport;

  channel := TNetUDPClient.Create(cliport);
  clientID := id;

  FillChar(address, sizeof(address), 0);
  address.sin_family      := AF_INET;
  address.sin_addr.S_addr := inet_addr(PAnsiChar(serverHost));
  address.sin_port        := htons(serverPort);

  ioBuffer := TDataBuffer.Create(maxsize);
  tmpBuffer := TDataBuffer.Create(maxsize);

  messageID := GetNowInMilliseconds();
  commandID := GetNowInMilliseconds();
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
destructor TRCClient.Destroy();
begin
  channel.Destroy();
  ioBuffer.Destroy();
  tmpBuffer.Destroy();
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.getClientID(): Integer;
begin
  Result := clientID;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.getServerHost(): String;
begin
  Result := serverHost;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.getServerPort(): Integer;
begin
  Result := serverPort;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.getClientPort(): Integer;
begin
  Result := clientPort;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.getServerAddress(): TSockAddr;
begin
  Result := address;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.generateMessageID(): Int64;
begin
  messageID := messageID + 1;
  Result := messageID;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.generateCommandID(): Int64;
begin
  commandID := commandID + 1;
  Result := commandID;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса сервису и получение ответа на запрос.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TRCClient.Request(answertimeout: Integer; meta: TRCMeta; body: TDataBuffer);
var dt: Int64;
  len, crc, res: Integer;
  msglen, msgcrc: Integer;
  addr: TSockAddrIn;
  mm: TRCMeta;
  serr: String;
begin
  dt := GetNowInMilliseconds();

  try
    ioBuffer.reset().shift(4); // оставляем для длины и CRC16.
    meta.buildRequest(ioBuffer).putArea(body).flip();
    len := ioBuffer.length() - 4;
    crc := crc16sb(ioBuffer.buffer(), 4, len);
    ioBuffer.putInt2At(0, len).putInt2At(2, crc);
  except
    on ex: Exception do raise TExRequestError.Create(ERR_REQ_BUILD, 'Ошибка построения запроса - %s!', [ex.Message]);
  end;

  try
    // Очистка входного буфера от уже полученных датаграмм (устарели).
    channel.clearReceive();
    // Отправляем (должно уйти с первого раза - иначе ошибка!).
    res := channel.send(ioBuffer, address);
    // Если не всё отправили - ошибка!
    if (res <> ioBuffer.length()) then
      raise TExRequestError.Create(ERR_REQ_SEND, 'Ошибка отправки запроса для %s! {отправлено %d из %d}',
                                   [SockAddrToStr(address), res, ioBuffer.length()]);
    logMsg('[%d] Отправлено в %s {meta={%s} datahex=%s', [clientID, SockAddrToStr(address), meta.toString(), body.getHexAt(0, body.length())]);
  except
    on ex: TExRequestError do raise;
    on ex: Exception do raise TExRequestError.Create(ERR_REQ_SEND, 'Ошибка отправки запроса - %s!', [ex.Message]);
  end;

  // Ошибка по умолчанию при истечении времени ожидания ответа.
  serr := '';

  // Цикл ожидания ответа.
  while (true) do
  begin
    try
      res := channel.receive(ioBuffer.reset(), addr);
      logMsg('[%d] Получено от %s {size=%d}', [clientID, SockAddrToStr(addr), res]);
    except
      on ex: Exception do raise TExRequestError.Create(ERR_ANSW_RECEIVE, 'Ошибка получения ответа - %s!', [ex.Message]);
    end;

    if (res = 0) then
    begin
      if (GetNowInMilliseconds() - dt > answertimeout) then
      begin
        if (serr <> '') then
        begin
          raise TExRequestError.Create(ERR_ANSW_PARSE, serr);
        end else
        begin
          raise TExTimeout.Create('Истекло время получения ответа на запрос!');
        end;
      end;
      Sleep(10); // Если нет пакетов - ожидаем.
    end
    else
    begin
      try
        len := ioBuffer.flip().length(); // После этого окно равно полученному пакету.
        if (len < 4) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Длина датаграммы меньше 4 байт! {len=%d}', [len]);

        msglen := ioBuffer.getInt2();
        msgcrc := ioBuffer.getInt2();

        // Проверяем длину сообщения.
        if (msglen <> len - 4) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Длина сообщения не совпадает с длиной в сообщении! {len=%d-4 msglen=%d}', [len, msglen]);

        // Проверяем контрольную сумму.
        crc := crc16sb(ioBuffer.buffer(), 4, len - 4);
        if (msgcrc <> crc) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Не совпадает контрольная сумма! [crc=0x%04X msgcrc=0x%04X}', [crc, msgcrc]);

        // Если сообщение не битое - парсим метаданные!
        mm := TRCMeta.Create();
        mm.parseAnswer(ioBuffer.tail()); // Окно от тек.позиции и до конца данных.

        logMsg('[%d] Получено от %s {meta={%s} datahex=%s}', [clientID, SockAddrToStr(addr), mm.toString(), ioBuffer.getHexAt(ioBuffer.pos(), ioBuffer.remaining())]);

        // Сравниваем поля запроса и ответа - должны совпадать!
        if (mm.senderID <> meta.senderID) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Не совпадает запрос и ответ - senderID!');

        if (mm.messageID <> meta.messageID) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Не совпадает запрос и ответ - messageID!');

        if (mm.requestType <> meta.requestType) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Не совпадает запрос и ответ - requestType!');

        if (mm.commandID <> meta.commandID) then
          raise TExRequestError.Create(ERR_ANSW_PARSE, 'Не совпадает запрос и ответ - commandID!');

        meta.finalizationID := mm.finalizationID;
        meta.answerErrorID := mm.answerErrorID;
        meta.answerErrorMessage := mm.answerErrorMessage;

        // Обрабатываем команду.
        res := ioBuffer.tail().length();
        body.reset();
        if (res > 0) then body.putArea(ioBuffer);
        body.flip();
        
        Break; // Завершаем запрос.

      except // При ошибках просто отбрасываем эту команду и ждём другую (ошибку сохраняем для возврата при истечении таймаута).
        on ex: TExRequestError do
        begin
          logEx('[%d] Неверный формат сообщения - %s!', [clientID, ex.Message]);
          serr := Format('Неверный формат сообщения - %s!', [ex.Message]); // raise
        end;
        on ex: Exception do
        begin
          logEx('[%d] Ошибка при разборе сообщения - %s!', [clientID, ex.Message]);
          //raise TExRequestError.Create(ERR_ANSW_PARSE, 'Неверный формат сообщения - %s!', [ex.Message]);
          serr := Format('Ошибка при разборе сообщения - %s!', [ex.Message]);
        end;
      end;
    end;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса GETSTATE.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.remoteGetState(answertimeout: Integer): TRCResultGetState;
var meta: TRCMeta;
begin
  meta := TRCMeta.Create();
  meta.senderID := clientID;
  meta.messageID := generateMessageID();
  meta.requestType := REQ_TYPE_GETSTATE;
  request(answertimeout, meta, tmpBuffer.reset().flip());
  Result := TRCResultGetState.Create(meta, tmpBuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса STOP (RESTART).
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.remoteRestart(answertimeout: Integer; restarttimeout: Integer): TRCResultRestart;
var meta: TRCMeta;
begin
  meta := TRCMeta.Create();
  meta.senderID := clientID;
  meta.messageID := generateMessageID();
  meta.requestType := REQ_TYPE_STOP;
  request(answertimeout, meta, tmpBuffer.reset().putInt(restarttimeout).flip());
  Result := TRCResultRestart.Create(meta);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса STOP.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.remoteStop(answertimeout: Integer): TRCResultStop;
var meta: TRCMeta;
begin
  meta := TRCMeta.Create();
  meta.senderID := clientID;
  meta.messageID := generateMessageID();
  meta.requestType := REQ_TYPE_STOP;
  request(answertimeout, meta, tmpBuffer.reset().flip());
  Result := TRCResultStop.Create(meta);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса STOP (HALT).
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.remoteHalt(answertimeout: Integer): TRCResultHalt;
var meta: TRCMeta;
begin
  meta := TRCMeta.Create();
  meta.senderID := clientID;
  meta.messageID := generateMessageID();
  meta.requestType := REQ_TYPE_STOP;
  request(answertimeout, meta, tmpBuffer.reset().putInt(-1).flip());
  Result := TRCResultHalt.Create(meta);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса EXECUTE.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRCClient.remoteExecute(answertimeout, executetimeout: Integer; buf: TDataBuffer): TRCResultExecute;
var meta, fmeta: TRCMeta;
    dt: Int64;
begin
  dt := GetNowInMilliseconds();

  // Выполнение запроса: EXECUTE.
  meta := TRCMeta.Create();
  meta.senderID := clientID;
  meta.messageID := generateMessageID();
  meta.requestType := REQ_TYPE_EXECUTE;
  meta.commandID := generateCommandID();
  meta.executeTimeout := executetimeout;
  request(answertimeout, meta, buf.rewind());
  buf.reset().flip();
  if (meta.answerErrorID <> RESULT_OK) then
  begin
    Result := TRCResultExecute.Create(meta);
    Exit;
  end;

  if (executetimeout = 0) then
  begin
    Result := TRCResultExecute.Create(meta); // Считываем ответ.
    Exit;
  end;

  executetimeout := abs(executetimeout); // Если он был < 0 - это для исполнителя, берем по модулю - реальный таймаут.

  // Выполнение запроса: GETRESULT.
  while (true) do
  begin
    meta.messageID := generateMessageID();
    meta.requestType := REQ_TYPE_GETRESULT;
    request(answertimeout, meta, buf.reset().flip());
    if (meta.answerErrorID = RESULT_OK) then Break; // Результат получен.
    if (meta.answerErrorID <> RESULT_RESULTNOTREADY) then
    begin
      Result := TRCResultExecute.Create(meta); // Какая-то ошибка помимо "результат не готов".
      Exit;
    end;
    if (GetNowInMilliseconds() - dt > executetimeout) then
    begin
      Result := TRCResultExecute.Create(meta); // Истекло время получения результата.
      Exit;
    end;
    Sleep(30); // Пауза перед повторным запросом результата.
  end;

  // Выполнение запроса: FINALIZATION.
  // Даже если он не удастся - не должен влиять на результат (т.к. команда выполнена и результат получен).
  try
    fmeta := TRCMeta.Create(meta);
    fmeta.messageID := generateMessageID();
    fmeta.requestType := REQ_TYPE_FINALIZE;
    request(answertimeout, fmeta, tmpBuffer.reset().flip());
    if (fmeta.answerErrorID = RESULT_COMMANDNOTFOUND) then fmeta.answerErrorID := RESULT_OK;
  except
  end;

  // Считываем результат.
  Result := TRCResultExecute.Create(meta);
end;




end.
