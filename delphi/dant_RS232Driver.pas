unit dant_RS232Driver;

interface

uses
  Windows, dant_utils, dant_log, dant_sync, dant_SerialPort;

const
  ERR_PORT_ALREADY_OPENED   = dant_SerialPort.ERR_PORT_ALREADY_OPENED;
  ERR_NULL_PORT_NAME        = dant_SerialPort.ERR_NULL_PORT_NAME;
  ERR_PORT_BUSY             = dant_SerialPort.ERR_PORT_BUSY;
  ERR_PORT_NOT_FOUND        = dant_SerialPort.ERR_PORT_NOT_FOUND;
  ERR_PERMISSION_DENIED     = dant_SerialPort.ERR_PERMISSION_DENIED;
  ERR_INCORRECT_SERIAL_PORT = dant_SerialPort.ERR_INCORRECT_SERIAL_PORT;
  ERR_PORT_NOT_OPENED       = dant_SerialPort.ERR_PORT_NOT_OPENED;
  ERR_OPERATION_FAULT       = 100;

  REG_OK           = 0;
  REG_OPENED       = 1;
  REG_DISCONNECTED = -1;
  REG_NOTOPENED    = -2;

type
  // Общее исключение для TRS232Driver.
  TExRS232Driver = class(TExError);
  // Исключение при ошибках операций с устройством. Анонимизирует реализацию устройства (коды ошибок драйвера устройства).
  TExDevice = class(TExRS232Driver);
  // Исключение при истечении таймаута ожидании данных при чтении из устройства.
  TExTimeout = class(TExRS232Driver);
  // Исключение при операциях с отключенным устройством.
  TExDisconnect = class(TExRS232Driver);

  //////////////////////////////////////////////////////////////////////////////////////////////////
  //  Класс для работы с портом RS232 (методы синхронизированны!).
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TRS232Driver = class
    private
      sDeviceName: string;
      sPortName: string;
      //
      iBitRate, iDataBits, iStopBits, iParity: int;
      //
      iTimeout: int;
      //
      port: TSerialPort;
      sync: TCriticalSectionExt;

    public  
      isLogging, isIOLogging: boolean;

    public
      constructor Create(const devname, portname: string);
      destructor Destroy(); override;
      procedure CreateNewPort();

      function getDeviceName(): string;
      function getPortName(): string;

      function bitrate(value: int): TRS232Driver; overload;
      function bitrate(): int; overload;
      function databits(value: int): TRS232Driver; overload;
      function databits(): int; overload;
      function stopbits(value: int): TRS232Driver; overload;
      function stopbits(): int; overload;
      function parity(value: int): TRS232Driver; overload;
      function parity(): int; overload;
      function timeout(value: int): TRS232Driver; overload;
      function timeout(): int; overload;

      function open(): TRS232Driver;
      procedure closeSafe();
      function isOpened(): boolean;
      function isClosed(): boolean;
      function checkDisconnect(): boolean;
      function regenerate(): int;
      procedure flush();
      function getInputCount(): int;
      function getOutputCount(): int;

      // Чтение одного байта.
      function read(timeout: int = -1; istimeoutexception: boolean = true): int;
      function readTimeoutSafe(timeout: int = -1): int; // Удобная форма для чтения без исключения по таймауту.
      // Запись одного байта.
      procedure write(value: int);
      procedure writeAndFlush(value: int);

      function readAllAndDrop(): int; // Очистка буфера чтения (считывает и отбрасывает все данные).
      function purgeRead(withabort: boolean = false): int; // Сброс буфера чтения.
      function purgeWrite(withabort: Boolean = false): int; // Сброс буфера записи.

      class function errToString(errid: int): string;
  end;


implementation

uses
  SysUtils, dant_TimeoutUtils;

      
////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор.
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TRS232Driver.Create(const devname, portname: string);
begin
  inherited Create();

  sDeviceName := devname;
  sPortName   := portname;

  iBitRate    := dant_SerialPort.BAUDRATE_19200;
  iDataBits   := dant_SerialPort.DATABITS_8;
  iStopBits   := dant_SerialPort.STOPBITS_1;
  iParity     := dant_SerialPort.PARITY_NONE;

  iTimeout    := 100;

  sync := TCriticalSectionExt.Create();
  port := TSerialPort.Create(sPortName);

  isLogging   := false;
  isIOLogging := false;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Деструктор.
////////////////////////////////////////////////////////////////////////////////////////////////////
destructor TRS232Driver.Destroy();
begin
  closeSafe();
  sync.Enter();
  try
    FreeAndNilSafe(port);
  finally
    sync.Leave();
  end;
  FreeAndNilSafe(sync);

  inherited;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрывает и уничтожает текущий порт, создаёт новый.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TRS232Driver.CreateNewPort();
begin
  sync.Enter();
  try
    closeSafe();
    FreeAndNilSafe(port);
    port := TSerialPort.Create(sPortName);
  finally
    sync.Leave();
  end;
end;


function TRS232Driver.getDeviceName(): string;
begin
  Result := sDeviceName;
end;

function TRS232Driver.getPortName(): string;
begin
  Result := sPortName;
end;

function TRS232Driver.bitrate(value: int): TRS232Driver;
begin
  iBitRate := value;
  Result := self;
end;

function TRS232Driver.bitrate(): int;
begin
  Result := iBitRate;
end;

function TRS232Driver.databits(value: int): TRS232Driver;
begin
  iDataBits := value;
  Result := self;
end;

function TRS232Driver.databits(): int;
begin
  Result := iDataBits;
end;

function TRS232Driver.stopbits(value: int): TRS232Driver;
begin
  iStopBits := value;
  Result := self;
end;

function TRS232Driver.stopbits(): int;
begin
  Result := iStopBits;
end;

function TRS232Driver.parity(value: int): TRS232Driver;
begin
  iParity := value;
  Result := self;
end;

function TRS232Driver.parity(): int;
begin
  Result := iParity;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Сеттер для таймаута (из-за проверок).
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRS232Driver.timeout(value: int): TRS232Driver;
begin
  if (value < 10) then value := 10;
  if (value > 10000) then value := 10000;
  iTimeout := value;
  Result := self;
end;

function TRS232Driver.timeout(): int;
begin
  Result := iTimeout;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Открытие порта.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRS232Driver.open(): TRS232Driver;
begin
  sync.Enter();
  try
    if (not isClosed()) then closeSafe();
    if (isLogging) then logMsg('Открытие порта [%s]...', [sPortName]);
    try
      port.openPort();
    except
      on ex: TExPortNotOpened do
      begin
        if (isLogging) then logMsg('Ошибка открытия порта [%s]: #%d "%s"!', [sPortName, ex.errorID, ex.Message]);
        closeSafe();
        raise TExDevice.Create(ex.errorID, 'Ошибка открытия порта!'); // Анонимизация и проброс исключения дальше.
      end;
    end;

    try
      port.setParams(iBitRate, iDataBits, iStopBits, iParity);
    except
      on ex: TExSerialPort do // ExFault, ExPortNotOpened
      begin
        if (isLogging) then logMsg('Ошибка установки параметров порта [%s]: #%d "%s"!', [sPortName, ex.errorID, ex.Message]);
        closeSafe();
        raise TExDevice.Create(iif(ex.ClassType = TExFault, ERR_OPERATION_FAULT, ex.errorID), 'Ошибка установки параметров порта!'); // Анонимизация и проброс исключения дальше.
      end;
    end;
    if (isLogging) then logMsg('Порт успешно открыт [%s]: bitrate=%d databit=%d stopbit=%d paritybit=%d', [sPortName, iBitRate, iDataBits, iStopBits, iParity]);

  finally
    sync.Leave();
  end;

  Result := self;
end;

procedure TRS232Driver.flush();
begin
  sync.Enter();
  try
    if (port.isOpened()) then port.flushPort();
  finally
    sync.Leave();
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрытие порта.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TRS232Driver.closeSafe();
begin
  sync.Enter();
  try
    try
      if (port.isOpened()) then port.closePort();
    except
    end;
    if (isLogging) then logMsg('Порт закрыт [%s]!', [sPortName]);
  finally
    sync.Leave();
  end;
end;


function TRS232Driver.isOpened(): boolean;
begin
  sync.Enter();
  try
    Result := port.isOpened();
  finally
    sync.Leave();
  end;
end;


function TRS232Driver.isClosed(): boolean;
begin
  Result := not isOpened();
end;


function TRS232Driver.checkDisconnect(): boolean;
begin
  sync.Enter();
  try
    if (port.isOpened()) then
    begin
      Result := (port.checkPort() <> 0);
    end else
    begin
      Result := false;
    end;
  finally
    sync.Leave();
  end;
end;


function TRS232Driver.regenerate(): int;
begin
  sync.Enter();
  try
    if (not port.isOpened()) then // isOpened
    begin
      try
        open();
        Result := REG_OPENED;
      except
        Result := REG_NOTOPENED;
      end;
    end else
    begin
      if (port.checkPort() <> 0) then // checkDisconnect
      begin
        closeSafe();
        Result := REG_DISCONNECTED;
      end else
      begin
        Result := REG_OK;
      end;
    end;
  finally
    sync.Leave();
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Чтение одного байта из порта. [TExDisconnect, TExDevice, TExTimeout]
// istimeoutexception = false - тогде в случае таймаута исключение не выкидывается и возвращается -1.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRS232Driver.read(timeout: int = -1; istimeoutexception: boolean = true): int;
var time: int64;
begin
  Result := -1;
  sync.Enter();
  try
    if (timeout < iTimeout) then timeout := iTimeout;
    if (not port.isOpened()) then raise TExDisconnect.Create();
    try
      time := GetNowInMilliseconds();
      while (GetNowInMilliseconds() - time <= timeout) do
      begin
        if (port.getInputBufferBytesCount() > 0) then
        begin
          Result := port.readByte();
          if (Result >= 0) then
          begin
            if (isIOLogging) then
            begin
              time := GetNowInMilliseconds() - time;
              logMsg('<- %.2X (%d:%d)', [Result, timeout, time]);
            end;
            Exit;
          end;
        end;
        Sleep(1);
      end;
      
    except
      on ex: TExPortNotOpened do raise TExDisconnect.Create();
      on ex: TExFault do
      begin
        if (checkDisconnect()) then raise TExDisconnect.Create();
        raise TExDevice.Create(ERR_OPERATION_FAULT, ex.Message);
      end;
    end;

    if (istimeoutexception) then
    begin
      raise TExTimeout.Create(timeout, 'Таймаут=%d Истекло=%d', [timeout, GetNowInMilliseconds() - time]);
    end else
    begin
      Result := -1
    end;  

  finally
    sync.Leave();
  end;
end;

function TRS232Driver.readTimeoutSafe(timeout: int = -1): int;
begin
  Result := read(timeout, false);
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Запись одного байта в порт. [TExDisconnect, TExDevice]
// timeout = 0 - не ждать опустошения буфера, -1 - ждать, дефолтный таймаут, > 0 - ждать заданный таймаут.
// Result = 1 - байт выбыл из буфера записи, 0 - не выбыл или не проверялось.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure TRS232Driver.write(value: int);
var tmstart: int64;
begin
  sync.Enter();
  try
    if (not port.isOpened()) then raise TExDisconnect.Create();
    try
      value := value and $FF;
      tmstart := GetNowInMilliseconds();
      if (port.writeByte(value) <> 1) then raise TExFault.Create('Байт не записан!');
      if (isIOLogging) then logMsg('-> %.2X (0:%d)', [value, GetNowInMilliseconds() - tmstart]);

    except
      on ex: TExPortNotOpened do raise TExDisconnect.Create();
      on ex: TExFault do
      begin
        if (checkDisconnect()) then raise TExDisconnect.Create();
        raise TExDevice.Create(ERR_OPERATION_FAULT, ex.Message);
      end;
    end;

  finally
    sync.Leave();
  end;
end;


procedure TRS232Driver.writeAndFlush(value: int);
begin
  write(value);
  flush();
end;


function TRS232Driver.getInputCount(): int;
begin
  Result := 0;
  sync.Enter();
  try
    if (port.isOpened()) then
      Result := port.getInputBufferBytesCount();
  finally
    sync.Leave();
  end;
end;

function TRS232Driver.getOutputCount(): int;
begin
  Result := 0;
  try
    if (port.isOpened()) then
      Result := port.getOutputBufferBytesCount();
  finally
    sync.Leave();
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Очистка всех входящих данных из порта (возвращает кол-во считанных байт).
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRS232Driver.readAllAndDrop(): int;
var i: int;
begin
  sync.Enter();
  try
    Result := 0;
    if (port.isOpened()) then
    begin
      //port.purgePort(PURGE_RXCLEAR or iif(withabort, PURGE_RXABORT, 0));
      //if (isIOLogging) then logMsg('<- %.2d bytes purged (read)!', [Result]);
      while (port.getInputBufferBytesCount() > 0) do
      begin
        i := port.readByte();
        if (isIOLogging) then logMsg('<- 0x%.2X drop!', [i]);
        inc(Result);
      end;
    end;

  finally
    sync.Leave();
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Очистка всех входящих данных из порта (возвращает кол-во считанных байт).
////////////////////////////////////////////////////////////////////////////////////////////////////
function TRS232Driver.purgeRead(withabort: boolean = false): int;
begin
  sync.Enter();
  try
    if (port.isOpened()) then
    begin
      Result := port.getInputBufferBytesCount();
      if (Result > 0) then
      begin
        port.purgePort(PURGE_RXCLEAR or iif(withabort, PURGE_RXABORT, 0));
        if (isIOLogging) then logMsg('<- %.2d bytes purged (read)!', [Result]);
      end;
    end else
    begin
      Result := 0;
    end;

  finally
    sync.Leave();
  end;
end;


function TRS232Driver.purgeWrite(withabort: boolean = false): int;
begin
  sync.Enter();
  try
    if (port.isOpened()) then
    begin
      Result := port.getOutputBufferBytesCount();
      if (Result > 0) then
      begin
        port.purgePort(PURGE_TXCLEAR or iif(withabort, PURGE_TXABORT, 0));
        if (isIOLogging) then logMsg('-> %.2d bytes purged (write)!', [Result]);
      end;
    end else
    begin
      Result := 0;
    end;

  finally
    sync.Leave();
  end;
end;


class function TRS232Driver.errToString(errid: int): string;
begin
  case errid of
    ERR_PORT_ALREADY_OPENED:    Result := 'PORT_ALREADY_OPENED';
    ERR_NULL_PORT_NAME:         Result := 'NULL_PORT_NAME';
    ERR_PORT_BUSY:              Result := 'PORT_BUSY';
    ERR_PORT_NOT_FOUND:         Result := 'PORT_NOT_FOUND';
    ERR_PERMISSION_DENIED:      Result := 'PERMISSION_DENIED';
    ERR_INCORRECT_SERIAL_PORT:  Result := 'INCORRECT_SERIAL_PORT';
    ERR_PORT_NOT_OPENED:        Result := 'PORT_NOT_OPENED';
    ERR_OPERATION_FAULT:        Result := 'OPERATION_FAULT';         
    else                        Result := 'UNKNOWN';
  end;
end;


end.
