unit dant_SerialPort;

interface

uses
  dant_utils, dant_log, dant_sync;

// Константы...
const
  BAUDRATE_110    = 110;
  BAUDRATE_300    = 300;
  BAUDRATE_600    = 600;
  BAUDRATE_1200   = 1200;
  BAUDRATE_4800   = 4800;
  BAUDRATE_9600   = 9600;
  BAUDRATE_14400  = 14400;
  BAUDRATE_19200  = 19200;
  BAUDRATE_38400  = 38400;
  BAUDRATE_57600  = 57600;
  BAUDRATE_115200 = 115200;
  BAUDRATE_128000 = 128000;
  BAUDRATE_256000 = 256000;

  DATABITS_5 = 5;
  DATABITS_6 = 6;
  DATABITS_7 = 7;
  DATABITS_8 = 8;

  // DANT: Привел с общему знаменателю (как они передаются в нативную библиотеку!).
  STOPBITS_1   = 0;
  STOPBITS_1_5 = 1;
  STOPBITS_2   = 2;

  PARITY_NONE  = 0;
  PARITY_ODD   = 1;
  PARITY_EVEN  = 2;
  PARITY_MARK  = 3;
  PARITY_SPACE = 4;

  PURGE_RXABORT = $0002;
  PURGE_RXCLEAR = $0008;
  PURGE_TXABORT = $0001;
  PURGE_TXCLEAR = $0004;

  FLOWCONTROL_NONE        = 0;
  FLOWCONTROL_RTSCTS_IN   = 1;
  FLOWCONTROL_RTSCTS_OUT  = 2;
  FLOWCONTROL_XONXOFF_IN  = 4;
  FLOWCONTROL_XONXOFF_OUT = 8;

  // Добавлены для унификации состояния линий
  LINESSTATUS_CTS  = 1;
  LINESSTATUS_DSR  = 2;
  LINESSTATUS_RING = 4;
  LINESSTATUS_RSLD = 8;

  ERROR_FRAME   = $0008;
  ERROR_OVERRUN = $0002;
  ERROR_PARITY  = $0004;

  PARAMS_FLAG_IGNPAR = 1;
  PARAMS_FLAG_PARMRK = 2;

  ERR_PORT_ALREADY_OPENED   = 1;
  ERR_NULL_PORT_NAME        = 2;
  ERR_PORT_BUSY             = 3;
  ERR_PORT_NOT_FOUND        = 4;
  ERR_PERMISSION_DENIED     = 5;
  ERR_INCORRECT_SERIAL_PORT = 6;
  ERR_PORT_NOT_OPENED       = 7;

type

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //  ИСКЛЮЧЕНИЯ
  //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Общее исключение для TSerialPort.
  TExSerialPort = class(TExError);
  // Исключение при попытке совершении операции при закрытом порте.
  TExPortNotOpened = class(TExSerialPort);
  // Исключение при ошибке выполнения операции.
  TExFault = class(TExSerialPort);

  // Реализация последовательного порта.
  TSerialPort = class
    private
      portHandle: THandle;
      portName: string;
      portOpened: Boolean;

      procedure exIfPortNotOpened(const infomsg: string);
      procedure exIfFalse(value: boolean; infomsg: string);
      function exIfNegOne(value: int; infomsg: string): int;

    public
      constructor Create(const portName: string);
      destructor Destroy(); override;

      function getPortName(): string;
      function isOpened(): boolean;

      procedure openPort();
      procedure setParams(baudRate, dataBits, stopBits, parity: int; rts: boolean = true; dtr: boolean = true);
      procedure purgePort(flags: int = (PURGE_RXABORT or PURGE_RXCLEAR or PURGE_TXABORT or PURGE_TXCLEAR));
      procedure closePort();
      function checkPort(): int;
      procedure flushPort();

      procedure setRTS(value: boolean);
      procedure setDTR(value: boolean);
      procedure setFlowControlMode(mask: int);
      function getFlowControlMode(): int;
      procedure sendBreak(duration: int);
      function getLinesStatus(): int;
      function isCTS(): boolean;
      function isDSR(): boolean;
      function isRING(): boolean;
      function isRLSD(): boolean;

      function readBytes(const buffer: PByte; idx, len: int): int;
      function readByte(): int;
      function writeBytes(const buffer: PByte; idx, len: int): int;
      function writeByte(value: int): int;
      function getInputBufferBytesCount(): int;
      function getOutputBufferBytesCount(): int;

      class function errToString(errid: int): string;
  end;

implementation

uses
  Windows, jsscex;

// Конструктор.
constructor TSerialPort.Create(const portName: string);
begin
  inherited Create();
  self.portName   := portName;
  self.portHandle := INVALID_HANDLE_VALUE;
  self.portOpened := false;
end;

destructor TSerialPort.Destroy();
begin
  inherited;
end;


// Получение имени порта.
function TSerialPort.getPortName(): string;
begin
  Result := portName;
end;


// Получение состояния открытости порта.
function TSerialPort.isOpened(): boolean;
begin
  Result := portOpened;
end;


// Проверка открытости порта. Если не открыт - выбрасывается исключение.
procedure TSerialPort.exIfPortNotOpened(const infomsg: string);
begin
  if (not portOpened) then
    raise TExPortNotOpened.Create('Порт "%s" не открыт! [%s]', [portName, infomsg]);
end;


// Проверка boolean значения. Если false - выбрасывается исключение.
procedure TSerialPort.exIfFalse(value: boolean; infomsg: string);
begin
  if (not value) then TExFault.Create('Ошибка операции с портом "%s"! [%s]', [portName, infomsg]);
end;


// Проверка int значения. Если = -1 - выбрасывается исключение.
function TSerialPort.exIfNegOne(value: int; infomsg: string): int;
begin
  if (value = -1) then raise TExFault.Create('Ошибка операции с портом "%s"! [%s]', [portName, infomsg]);
  Result := value;
end;


// Открытие порта. Вид ошибки открытия порта - в типе выбрасываемого исключения.
procedure TSerialPort.openPort();
begin
  if (portOpened) then raise TExPortNotOpened.Create(ERR_PORT_ALREADY_OPENED, 'Порт "%s" уже открыт!', [portName]);
  if (portName = '') then raise TExPortNotOpened.Create(ERR_NULL_PORT_NAME, 'Не задано имя порта!');
  portHandle := jsscex.openPort(portName);
  case (portHandle) of
    jsscex.ERR_PORT_BUSY: raise TExPortNotOpened.Create(ERR_PORT_BUSY, 'Порт "%s" занят!', [portName]);
    jsscex.ERR_PORT_NOT_FOUND: raise TExPortNotOpened.Create(ERR_PORT_NOT_FOUND, 'Порт "%s" не найден!', [portName]);
    jsscex.ERR_INCORRECT_SERIAL_PORT: raise TExPortNotOpened.Create(ERR_INCORRECT_SERIAL_PORT, 'Неверный последовательный порт "%s"!', [portName]);
    jsscex.ERR_PORT_NOT_OPENED: raise TExPortNotOpened.Create(ERR_PORT_NOT_OPENED, 'Порт не открыт (прочие ошибки) "%s"!', [portName]);
  end;
  portOpened := true;
end;


// Установка параметров порта.
//        throws PortNotOpenedException, FaultNativeException
procedure TSerialPort.setParams(baudRate, dataBits, stopBits, parity: int; rts: Boolean = true; dtr: boolean = true);
begin
  exIfPortNotOpened('setParams()');
  exIfFalse(jsscex.setParams(portHandle, baudRate, dataBits, stopBits, parity, rts, dtr), 'setParams()');
end;


// Выполнение операции освобождения порта. Некторые устройства могут не поддерживать эту функцию!
// throws PortNotOpenedException, FaultNativeException
procedure TSerialPort.purgePort(flags: int = (PURGE_RXABORT or PURGE_RXCLEAR or PURGE_TXABORT or PURGE_TXCLEAR));
begin
  exIfPortNotOpened('purgePort()');
  exIfFalse(jsscex.purgePort(portHandle, flags), 'purgePort()');
end;


// Закрытие порта. Сначала удаляет слушателей.
//  throws PortNotOpenedException, FaultNativeException {
procedure TSerialPort.closePort();
begin
  exIfPortNotOpened('closePort()');
  exIfFalse(jsscex.closePort(portHandle), 'closePort()');
  portOpened := false;
end;


// Проверка работоспособности порта.
function TSerialPort.checkPort(): int;
begin
  if (not isOpened()) then
  begin
    Result := -1;
  end else
  begin
    Result := jsscex.checkPort(portName);
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  СОСТОЯНИЕ ПОРТА
//
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка состояния RTS линии.
procedure TSerialPort.setRTS(value: boolean);
begin
  exIfPortNotOpened('setRTS()');
  exIfFalse(jsscex.setRTS(portHandle, value), 'setRTS()');
end;

// Установка состояния DTR линии.
procedure TSerialPort.setDTR(value: boolean);
begin
  exIfPortNotOpened('setDTR()');
  exIfFalse(jsscex.setDTR(portHandle, value), 'setDTR()');
end;

// Установка режима контроля потока.
procedure TSerialPort.setFlowControlMode(mask: int);
begin
  exIfPortNotOpened('setFlowControlMode()');
  exIfFalse(jsscex.setFlowControlMode(portHandle, mask), 'setFlowControlMode()');
end;

// Получение режима контроля потока.
function TSerialPort.getFlowControlMode(): int;
begin
  exIfPortNotOpened('getFlowControlMode()');
  Result := exIfNegOne(jsscex.getFlowControlMode(portHandle), 'getFlowControlMode()');
end;

// Посылка сигнала прерывания в течение заданного времени.
procedure TSerialPort.sendBreak(duration: int);
begin
  exIfPortNotOpened('sendBreak()');
  exIfFalse(jsscex.sendBreak(portHandle, duration), 'sendBreak()');
end;

// Получение состояний линий.
function TSerialPort.getLinesStatus(): int;
begin
  exIfPortNotOpened('getLinesStatus()');
  Result := exIfNegOne(jsscex.getLinesStatus(portHandle), 'getLinesStatus()');
end;

// Получение состояния линии CTS.
function TSerialPort.isCTS(): boolean;
begin
  Result := isBitOn(getLinesStatus(), LINESSTATUS_CTS);
end;

// Получение состояния линии DSR.
function TSerialPort.isDSR(): boolean;
begin
  Result := isBitOn(getLinesStatus(), LINESSTATUS_DSR);
end;

// Получение состояния линии RING.
function TSerialPort.isRING(): boolean;
begin
  Result := isBitOn(getLinesStatus(), LINESSTATUS_RING);
end;

// Получение состояния линии RLSD.
function TSerialPort.isRLSD(): boolean;
begin
  Result := isBitOn(getLinesStatus(), LINESSTATUS_RSLD);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  ОПЕРАЦИИ С ДАННЫМИ
//
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Неблокирующее чтение данных из порта в заданный участок массива. Чтение происходит за одно обращение, ожидания
// чтения всех данных не происходит! Если в приёмном буфере данных нет - возвращается ноль.
function TSerialPort.readBytes(const buffer: PByte; idx, len: int): int;
begin
  exIfPortNotOpened('readBytes()');
  Result := exIfNegOne(jsscex.readBytes(portHandle, buffer, idx, len), 'readBytes()');
end;

// Неблокирующее чтение одного байта из порта. Чтение происходит за одно обращение, ожидания чтения всех данных не
// происходит! Если в приёмном буфере данных нет - возвращается -1.
function TSerialPort.readByte(): int;
begin
  exIfPortNotOpened('readByte()');
  Result := exIfNegOne(jsscex.readByte(portHandle), 'readByte()');
  if (Result = -2) then Result := -1; // Если байт не считан - возвращаем -1.
end;

// Неблокирующая запись в порт заданного участка массива. Запись происходит за одно обращение, ожидания записи всех
// данных не происходит! Если произошла ошибка записи - возвращается -1.
function TSerialPort.writeBytes(const buffer: PByte; idx, len: int): int;
begin
  exIfPortNotOpened('writeBytes()');
  Result := exIfNegOne(jsscex.writeBytes(portHandle, buffer, idx, len), 'writeBytes()');
end;

// Неблокирующая запись в порт одного байта. Запись происходит за одно обращение.
function TSerialPort.writeByte(value: int): int;
begin
  exIfPortNotOpened('writeByte()');
  Result := exIfNegOne(jsscex.writeByte(portHandle, value), 'writeByte()');
end;

// Получение кол-ва байт доступных для чтения в буфере чтения порта.
function TSerialPort.getInputBufferBytesCount(): int;
begin
  exIfPortNotOpened('getInputBufferBytesCount()');
  Result := exIfNegOne(jsscex.getInputBufferBytesCount(portHandle), 'getInputBufferBytesCount()');
end;

// Получение кол-ва байт ожидающих отправки в буфере записи порта.
function TSerialPort.getOutputBufferBytesCount(): int;
begin
  exIfPortNotOpened('getOutputBufferBytesCount()');
  Result := exIfNegOne(jsscex.getOutputBufferBytesCount(portHandle), 'getOutputBufferBytesCount()');
end;


procedure TSerialPort.flushPort();
begin
  exIfPortNotOpened('flushPort()');
  exIfFalse(FlushFileBuffers(portHandle), 'flushPort()');
  //while (getOutputBufferBytesCount() > 0) do sleep(1);
end;


class function TSerialPort.errToString(errid: int): string;
begin
  case errid of
    ERR_PORT_ALREADY_OPENED:    Result := 'PORT_ALREADY_OPENED';
    ERR_NULL_PORT_NAME:         Result := 'NULL_PORT_NAME';
    ERR_PORT_BUSY:              Result := 'PORT_BUSY';
    ERR_PORT_NOT_FOUND:         Result := 'PORT_NOT_FOUND';
    ERR_PERMISSION_DENIED:      Result := 'PERMISSION_DENIED';
    ERR_INCORRECT_SERIAL_PORT:  Result := 'INCORRECT_SERIAL_PORT';
    ERR_PORT_NOT_OPENED:        Result := 'PORT_NOT_OPENED';
    else                        Result := 'UNKNOWN';
  end;
end;


end.

