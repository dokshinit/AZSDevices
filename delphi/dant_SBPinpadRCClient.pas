////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////
unit dant_SBPinpadRCClient;

interface

uses
  WinSock, dant_log, dant_DataBuffer, dant_RCClient;

const
  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Коды ошибок-результатов выполнения команд терминала СБ.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  SBR_OK = 0;
  SBR_DISCONNECTED = 1;
  SBR_UNSUPPORTED = 2;
  SBR_ERROR = 100;

type

  //////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  РЕЗУЛЬТАТЫ ЗАПРОСОВ
  //
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TSBResultGetState = class(TRCResultGetState)
  public
    processingMode: integer;
    isSingleSerialMode: boolean;
    processorState: integer;
    slotsFree, slotsExecute, slotsResult: integer;
    queueFree, queueSize: integer;
    isDevConnected: boolean;

    constructor Create(src: TRCResultGetState; buffer: TDataBuffer);
  end;


  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Данные результата выполнения команды CMD_TRANSACTION.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TTRResult = class
  public
    resultCode: Integer; // [2]
    authCode: String; // [6+1]
    RRN: String; // [12+1]
    opNumber: String; // [4+1]
    cardNumber: String; // [19+1]
    cardExpire: String; // [5+1]
    messageText: String; // [32]
    date: Integer; // [4]
    time: Integer; // [4]
    isSberbankCard: Integer; // [1]
    terminalNumber: String; // [8+1]
    cardName: String; // [16]
    merchantID: String; // [12]
    spasiboAmt: Integer; // [4]
    SHA1: String; // [20] HEX
    encryptedData: String; // [32] HEX Зашифрованные данные карты (в 19.0 размер = 0xBF).
    cardID: Byte; // [1] HEX (в 24.0 размер = 0xD3) Идентификатор типа карты.
    requestID: Integer; // [4]
    // Остальные поля только если в ответе есть RequestID и он меньше ноля.
    res2: String; // [19] HEX (в 24.0 размер = 0xD3) Нам пока не нужны - не разбираем.

    // Конструктор. Считывание данных из буфера с текущей позиции.
    constructor Create(buffer: TDataBuffer);
    // Чтение данных из буфера с текущей позиции и заполнение полей считанными значениями.
    function parse(buffer: TDataBuffer): TDataBuffer;
  end;


  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Блок вывода на принтер.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TPrinterTextBlock = class
  public
    size: Integer;
    modes: array of Integer;
    texts: array of String;

    constructor Create(buffer: TDataBuffer);
    function parse(buffer: TDataBuffer): TDataBuffer;
  end;


  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Клиент удаленного управления пинпадом СБ.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TSBPinpadRCClient = class (TRCClient)
  private
    cmdbuffer: TDataBuffer;

    function execCmd(answertimeout, executetimeout: Integer): TDataBuffer; overload;
    function execCmd(): TDataBuffer; overload;
    function execTRCmd(): TDataBuffer;

  public
    constructor Create(id: Integer; const srvhost: string; srvport, cliport: Integer; maxsize: Integer);

    function getBuffer(): TDataBuffer;

    function remoteGetState(answertimeout: Integer): TSBResultGetState;

    function cmd_GetReady(timeout: integer = 1000): String;
    function cmd_CardTest(): Integer;

    procedure cmd_MC_Display(row: Integer; const text: String);
    procedure cmd_MC_DisplayFlex(const vals: array of const);
    procedure cmd_MC_Beep(typ: Integer);
    function cmd_MC_Keyboard(): String;

    function cmd_TR_PreAuthorize(amount: Integer): TTRResult;
    function cmd_TR_PreComplete(amount: Integer; const rrn, hexencdata: String): TTRResult;
    function cmd_TR_Purchase(amount: Integer): TTRResult;
    function cmd_TR_Refund(amount: Integer; const rrn, hexencdata: String): TTRResult;

    function getLastPrintedTextAsBlocks(buffer: TDataBuffer): TPrinterTextBlock;
    function cmd_TR_CloseSession(): TPrinterTextBlock;
    function cmd_TR_Totals(typ: Integer): TPrinterTextBlock;
    function cmd_TR_Help(): TPrinterTextBlock;
    function cmd_GetPrinter(): TPrinterTextBlock;
  end;

  function sbrErrName(sbrerrid: Integer): String;



implementation

const
  //////////////////////////////////////////////////////////////////////////////////////////////////
  // КОМАНДЫ ПИНПАДА СБ.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  CMD_GETREADY_ID = 1;
  CMD_CARDTEST_ID = 2;

  CMD_MC_DISPLAY_ID = 10;
  CMD_MC_BEEP_ID = 11;
  CMD_MC_KEYBOARD_ID = 12;

  CMD_TR_PURCHASE_ID = 20;
  CMD_TR_REFUND_ID = 21;
  CMD_TR_CANCEL_ID = 22;
  CMD_TR_ROLLBACK_ID = 23;
  CMD_TR_BALANCE_ID = 24;
  CMD_TR_PREAUTHORIZE_ID = 25;
  CMD_TR_PRECOMPLETE_ID = 26;

  CMD_TR_CLOSESESSION_ID = 30;
  CMD_TR_TOTALS_ID = 31;
  CMD_TR_HELP_ID = 32;
  CMD_TR_READCARD_ID = 33;

  CMD_GETPRINTER_ID = 40; // Получение информации о последнем режиме печати принтера и массиве отпечатанных строк.




////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор. Восстановление из буфера!
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TTRResult.Create(buffer: TDataBuffer);
begin
  parse(buffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Чтение данных из буфера с текущей позиции и заполнение полей считанными значениями.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TTRResult.parse(buffer: TDataBuffer): TDataBuffer;
begin
  resultCode := buffer.getInt2();
  authCode   := buffer.getZString(7);
  RRN        := buffer.getZString(13);
  opNumber   := buffer.getZString(5);
  cardNumber := buffer.getZString(20);
  cardExpire := buffer.getZString(6);
  messageText:= buffer.getZString(32);
  date       := buffer.getInt();
  time       := buffer.getInt();
  isSberbankCard := buffer.get();
  terminalNumber := buffer.getZString(9);
  cardName   := buffer.getZString(16);
  merchantID := buffer.getZString(12);
  spasiboAmt := buffer.getInt();
  SHA1       := buffer.getHex(20);

  encryptedData := '';
  if (buffer.remaining() >= 32 + 4) then encryptedData := buffer.getHex(32);

  cardID := 0;
  if (buffer.remaining() >= 1 + 4) then cardID := buffer.get();

  requestID := 0;
  if (buffer.remaining() >= 4) then requestID := buffer.getInt();

  // Остальные данные не парсим, даже если они и есть - не нужны.
  Result := buffer;
end;







////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор. Восстановление из буфера!
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TPrinterTextBlock.Create(buffer: TDataBuffer);
begin
  parse(buffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Восстановление из буфера.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TPrinterTextBlock.parse(buffer: TDataBuffer): TDataBuffer;
var i: Integer;
begin
  size := buffer.getInt2();
  SetLength(modes, size);
  SetLength(texts, size);
  for i := 0 to size-1 do
  begin
    modes[i] := buffer.get();
    texts[i] := buffer.getNString();
  end;
  Result := buffer;
end;




  
////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор.
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TSBPinpadRCClient.Create(id: Integer; const srvhost: string; srvport, cliport: Integer; maxsize: Integer);
begin
  inherited Create(id, srvhost, srvport, cliport, maxsize);
  cmdbuffer := TDataBuffer.Create(maxsize);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение наименования ошибки СБ по коду (для лога и отладки).
////////////////////////////////////////////////////////////////////////////////////////////////////
function sbrErrName(sbrerrid: Integer): String;
begin
  case (sbrerrid) of
      SBR_OK:
          Result := 'SBR_OK';
      SBR_DISCONNECTED:
          Result := 'SBR_DISCONNECTED';
      SBR_UNSUPPORTED:
          Result := 'SBR_UNSUPPORTED';
      SBR_ERROR:
          Result := 'SBR_ERROR';
  else
          Result := '';
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение буфера, использующегося для построения команды СБ и получения результата выполнения
// команды СБ.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.getBuffer(): TDataBuffer;
begin
  Result := cmdbuffer;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  РЕЗУЛЬТАТ ЗАПРОСА: GETSTATE
//
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TSBResultGetState.Create(src: TRCResultGetState; buffer: TDataBuffer);
begin
  inherited Create(src);
  // Queue
  processingMode := buffer.get();
  isSingleSerialMode := (buffer.get() <> 0);
  processorState := buffer.get();
  slotsFree := buffer.getInt2();
  slotsExecute := buffer.getInt2();
  slotsResult := buffer.getInt2();
  queueFree := buffer.getInt2();
  queueSize := buffer.getInt2();
  // RS232
  isDevConnected := (buffer.get() <> 0)
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Отправка запроса GETSTATE.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.remoteGetState(answertimeout: Integer): TSBResultGetState;
var src: TRCResultGetState;
begin
  src := inherited remoteGetState(answertimeout);
  Result := TSBResultGetState.Create(src, tmpBuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение команды.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.execCmd(answertimeout, executetimeout: Integer): TDataBuffer;
var rExec: TRCResultExecute;
    errid: Integer;
    errmsg: String;
begin
  rExec := remoteExecute(answertimeout, executetimeout, cmdbuffer);
  if (rExec.answerErrorID <> RESULT_OK) then
    raise TExAnswerError.Create(rExec.answerErrorID, rExec.answerErrorMessage);

  cmdbuffer.rewind();
  errid := cmdbuffer.getInt2();
  if (errid <> SBR_OK) then
  begin
    errmsg := cmdbuffer.getNString();
    logEx('Ошибка СБ = %d:%s "%s"', [errid, sbrErrName(errid), errmsg]);
    raise TExSBError.Create(errid, errmsg);
  end;
  Result := cmdbuffer;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение команды с таймаутами по умолчанию.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.execCmd(): TDataBuffer;
begin
  Result := execCmd(1000, 10000); // 1 сек - на ответ сервиса, 10 сек - на выполнение команд.
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Выполнение команды группы TRANSACTION с таймаутами по умолчанию.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.execTRCmd(): TDataBuffer;
begin
  Result := execCmd(1000, 65000); // 1 сек - на ответ сервиса, 65 сек - на выполнение финансовых команд.
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_GETREADY
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_GetReady(timeout: integer = 1000): String;
begin
  cmdbuffer.reset().put(CMD_GETREADY_ID).flip();
  execCmd(100, timeout);
  Result := cmdbuffer.getNString();
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TESTCARD
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_CardTest(): Integer;
begin
  cmdbuffer.reset().put(CMD_CARDTEST_ID).flip();
  execCmd();
  Result := cmdbuffer.get();
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_MC_DISPLAY
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TSBPinpadRCClient.cmd_MC_Display(row: Integer; const text: String);
begin
  cmdbuffer.reset().put(CMD_MC_DISPLAY_ID).putInt2(1).put(row).putNString(text).flip();
  execCmd();
end;

procedure TSBPinpadRCClient.cmd_MC_DisplayFlex(const vals: array of const);
var i, len, row, n: Integer;
begin
  cmdbuffer.reset().put(CMD_MC_DISPLAY_ID).mark().putInt2(0);
  len := Length(vals);
  n := 0;
  row := 1;
  for i:=0 to len-1 do
  begin
    case vals[i].VType of
      vtInteger:
          begin
            row := vals[i].VInteger;
            if (row = -100) then
            begin
              cmdbuffer.put(-100).putNString('');
              row := 1;
              n := n + 1;
            end;
          end;
      vtString,
      vtAnsiString:
          begin
            cmdbuffer.put(row).putNString(AnsiString(vals[i].VAnsiString));
            row := row + 1;
            n := n + 1;
          end;
    end;
  end;
  cmdbuffer.putInt2At(cmdbuffer.markedPos(), n).flip();
  execCmd();
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_MC_BEEP
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TSBPinpadRCClient.cmd_MC_Beep(typ: Integer);
begin
  cmdbuffer.reset().put(CMD_MC_BEEP_ID).put(typ).flip();
  execCmd()
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_MC_KEYBOARD
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_MC_Keyboard(): String;
begin
  cmdbuffer.reset().put(CMD_MC_KEYBOARD_ID).flip();
  execCmd();
  Result := cmdbuffer.getNString();
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_PREAUTHORIZE
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_TR_PreAuthorize(amount: Integer): TTRResult;
begin
  cmdbuffer.reset().put(CMD_TR_PREAUTHORIZE_ID).putInt(amount).flip();
  execTRCmd();
  Result := TTRResult.Create(cmdbuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_PRECOMPLETE
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_TR_PreComplete(amount: Integer; const rrn, hexencdata: String): TTRResult;
begin
  cmdbuffer.reset().put(CMD_TR_PRECOMPLETE_ID).putInt(amount).putNString(rrn).putNString(hexencdata).flip();
  execTRCmd();
  Result := TTRResult.Create(cmdbuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_PURCHASE
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_TR_Purchase(amount: Integer): TTRResult;
begin
  cmdbuffer.reset().put(CMD_TR_PURCHASE_ID).putInt(amount).flip();
  execTRCmd();
  Result := TTRResult.Create(cmdbuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_REFUND
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_TR_Refund(amount: Integer; const rrn, hexencdata: String): TTRResult;
begin
  cmdbuffer.reset().put(CMD_TR_REFUND_ID).putInt(amount).putNString(rrn).putNString(hexencdata).flip();
  execTRCmd();
  Result := TTRResult.Create(cmdbuffer);
end;


function TSBPinpadRCClient.getLastPrintedTextAsBlocks(buffer: TDataBuffer): TPrinterTextBlock;
begin
  Result := TPrinterTextBlock.Create(buffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_CLOSESESSION
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_TR_CloseSession(): TPrinterTextBlock;
begin
  cmdbuffer.reset().put(CMD_TR_CLOSESESSION_ID).flip();
  execTRCmd();
  Result := getLastPrintedTextAsBlocks(cmdbuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_TOTALS
////////////////////////////////////////////////////////////////////////////////////////////////////
// 0-контрольная лента, 1-итоги.
function TSBPinpadRCClient.cmd_TR_Totals(typ: Integer): TPrinterTextBlock;
begin
  cmdbuffer.reset().put(CMD_TR_TOTALS_ID).put(typ).flip();
  execTRCmd();
  Result := getLastPrintedTextAsBlocks(cmdbuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_HELP
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_TR_Help(): TPrinterTextBlock;
begin
  cmdbuffer.reset().put(CMD_TR_HELP_ID).flip();
  execTRCmd();
  Result := getLastPrintedTextAsBlocks(cmdbuffer);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// КОМАНДА: CMD_TR_GETPRINTER  (получение последнего чека принтера)
////////////////////////////////////////////////////////////////////////////////////////////////////
function TSBPinpadRCClient.cmd_GetPrinter(): TPrinterTextBlock;
begin
  cmdbuffer.reset().put(CMD_GETPRINTER_ID).flip();
  execCmd();
  Result := getLastPrintedTextAsBlocks(cmdbuffer);
end;

end.
