// Реализация jSSC 2.8.0 на паскале.

unit jsscex;

interface

uses
  Windows, dant_utils, dant_log;

const
  ERR_PORT_BUSY             = dword(-1);
  ERR_PORT_NOT_FOUND        = dword(-2);
  ERR_PERMISSION_DENIED     = dword(-3);
  ERR_INCORRECT_SERIAL_PORT = dword(-4);
  ERR_PORT_NOT_OPENED       = dword(-5);
  ERR_PORT_OPENED           = dword(-6);

  FLOWCONTROL_NONE        = 0;
  FLOWCONTROL_RTSCTS_IN   = 1;
  FLOWCONTROL_RTSCTS_OUT  = 2;
  FLOWCONTROL_XONXOFF_IN  = 4;
  FLOWCONTROL_XONXOFF_OUT = 8;

  function openPort(const portName: string): THandle;
  function setParams(portHandle: THandle; baudRate, byteSize, stopBits, parity: int; rts, dtr: boolean): boolean;
  function purgePort(portHandle: THandle; flags: int): boolean;
  function closePort(var portHandle: THandle): boolean;
  function getSerialPortNames(): string;
  function setRTS(portHandle: THandle; state: boolean): boolean;
  function setDTR(portHandle: THandle; state: boolean): boolean;
  function setFlowControlMode(portHandle: THandle; mask: int): boolean;
  function getFlowControlMode(portHandle: THandle): int;
  function sendBreak(portHandle: THandle; duration: int): boolean;
  function getLinesStatus(portHandle: THandle): int;
  function readBytes(portHandle: THandle; buffer: PByte; idx, len: int): int;
  function readByte(portHandle: THandle): int;
  function writeBytes(portHandle: THandle; buffer: PByte; idx, len: int): int;
  function writeByte(portHandle: THandle; value: int): int;
  function getInputBufferBytesCount(portHandle: THandle): int;
  function getOutputBufferBytesCount(portHandle: THandle): int;
  function checkPort(const portName: string): int;


implementation

const
  dcb_Binary              = $00000001;
  dcb_ParityCheck         = $00000002;
  dcb_OutxCtsFlow         = $00000004;
  dcb_OutxDsrFlow         = $00000008;
  dcb_DtrControlMask      = $00000030;
  dcb_DtrControlDisable   = $00000000;
  dcb_DtrControlEnable    = $00000010;
  dcb_DtrControlHandshake = $00000020;
  dcb_DsrSensivity        = $00000040;
  dcb_TXContinueOnXoff    = $00000080;
  dcb_OutX                = $00000100;
  dcb_InX                 = $00000200;
  dcb_ErrorChar           = $00000400;
  dcb_NullStrip           = $00000800;
  dcb_RtsControlMask      = $00003000;
  dcb_RtsControlDisable   = $00000000;
  dcb_RtsControlEnable    = $00001000;
  dcb_RtsControlHandshake = $00002000;
  dcb_RtsControlToggle    = $00003000;
  dcb_AbortOnError        = $00004000;
  dcb_Reserveds           = $FFFF8000;

  
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открытие порта. При ошибках - вместо хендла порта - код ошибки (отрицатиельные). useTIOCEXCL не используется (только для Linix)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function openPort(const portName: string): THandle;
var
  portFullName: string;
  dcb: TDCB;
begin
  portFullName := '\\.\'+portName;

  Result := CreateFile(PAnsiChar(portFullName),
                       GENERIC_READ or GENERIC_WRITE,
                       0,
                       nil,
                       OPEN_EXISTING,
                       FILE_FLAG_OVERLAPPED, //  or FILE_FLAG_WRITE_THROUGH
                       0);

  if (Result <> INVALID_HANDLE_VALUE) then
  begin
    if (not GetCommState(Result, dcb)) then
    begin
      CloseHandle(Result);
      Result := ERR_INCORRECT_SERIAL_PORT; // (-4) Incorrect serial port
    end;
  end else
  begin
    case (GetLastError()) of
      ERROR_ACCESS_DENIED:  Result := ERR_PORT_BUSY; // (-1) Port busy
      ERROR_FILE_NOT_FOUND: Result := ERR_PORT_NOT_FOUND; // (-2) Port not found
      else                  Result := ERR_PORT_NOT_OPENED; // (-5) Other error (not opened)
    end;
  end
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка параметов порта.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function setParams(portHandle: THandle; baudRate, byteSize, stopBits, parity: int; rts, dtr: boolean): boolean;
var
  dcb: TDCB;
  tm: COMMTIMEOUTS;
begin
  Result := false;
  if (GetCommState(portHandle, dcb)) then
  begin
    dcb.BaudRate := baudRate;
    dcb.ByteSize := byteSize;
    dcb.StopBits := stopBits;
    dcb.Parity   := parity;
    dcb.Flags    := iif(rts, dcb_RtsControlEnable, 0) or
                    iif(dtr, dcb_DtrControlEnable, 0) or
                    dcb_TXContinueOnXoff or
                    dcb_AbortOnError; // TODO: Возможно из-за этого и не видит дисконнекта?
    dcb.XonLim   := 2048;
    dcb.XoffLim  := 512;
    dcb.XonChar  := #17; // DC1
    dcb.XoffChar := #19; // DC3

    if (SetCommState(portHandle, dcb)) then
    begin
      tm.ReadIntervalTimeout         := 0;
      tm.ReadTotalTimeoutConstant    := 0;
      tm.ReadTotalTimeoutMultiplier  := 0;
      tm.WriteTotalTimeoutConstant   := 0;
      tm.WriteTotalTimeoutMultiplier := 0;
      if (SetCommTimeouts(portHandle, tm)) then Result := true;
    end;
  end;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Очистка буферов порта согласно указанным флагам.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function purgePort(portHandle: THandle; flags: int): boolean;
begin
  Result := PurgeComm(portHandle, flags);
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрытие порта.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function closePort(var portHandle: THandle): boolean;
begin
  Result := CloseHandle(portHandle);
  if (Result) then portHandle := INVALID_HANDLE_VALUE;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение массива строк - имен портов.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function getSerialPortNames(): string;
var
  hkResult: HKEY;
  subkey: string;
  hasMoreElements: boolean;
  keysCount: int;
  valueName: array [0..255] of AnsiChar;
  valueNameSize: dword;
  data: array [0..255] of AnsiChar;
  dataSize: dword;
  enumResult: int;
  i: int;
begin
  subkey := 'HARDWARE\DEVICEMAP\SERIALCOMM\';
  Result := '';
  if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, PAnsiChar(subkey), 0, KEY_READ, hkResult) = ERROR_SUCCESS) then
  begin
    hasMoreElements := true;
    keysCount := 0;
    while (hasMoreElements) do
    begin
      valueNameSize := 256;
      enumResult := RegEnumValueA(hkResult, keysCount, valueName, valueNameSize, nil, nil, nil, nil);
      if (enumResult = ERROR_SUCCESS) then
      begin
        inc(keysCount);
      end else
      if (enumResult = ERROR_NO_MORE_ITEMS) then
      begin
        hasMoreElements := false;
      end else
      begin
        hasMoreElements := false;
      end;
    end;

    if (keysCount > 0) then
    begin
      for i := 0 to keysCount-1 do
      begin
        valueNameSize := 256;
        dataSize := 256;
        if (RegEnumValueA(hkResult, i, valueName, valueNameSize, nil, nil, @data[0], @dataSize) = ERROR_SUCCESS) then
        begin
          Result := Result + Copy(data, 0, dataSize) + #0;
        end;
      end;
    end;
    CloseHandle(hkResult);
  end;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Установка состояния линии RTS.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function setRTS(portHandle: THandle; state: boolean): boolean;
begin
  Result := EscapeCommFunction(portHandle, iif(state, Windows.SETRTS, Windows.CLRRTS));
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Установка состояния линии DTR.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function setDTR(portHandle: THandle; state: boolean): boolean;
begin
  Result := EscapeCommFunction(portHandle, iif(state, Windows.SETDTR, Windows.CLRDTR));
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка режима контроля потока.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function setFlowControlMode(portHandle: THandle; mask: int): boolean;
var dcb: TDCB;
begin
  Result := false;
  if (GetCommState(portHandle, dcb)) then
  begin
    dcb.Flags := (dcb.Flags or dcb_RtsControlEnable) and not (dcb_OutxCtsFlow or dcb_OutX or dcb_InX);
    if (mask <> FLOWCONTROL_NONE) then
    begin
      if (isBitsOn(mask, FLOWCONTROL_RTSCTS_IN)) then dcb.Flags := (dcb.Flags and dcb_RtsControlMask) or dcb_RtsControlHandshake;
      if (isBitsOn(mask, FLOWCONTROL_RTSCTS_OUT)) then dcb.Flags := dcb.Flags or dcb_OutxCtsFlow;
      if (isBitsOn(mask, FLOWCONTROL_XONXOFF_IN)) then dcb.Flags := dcb.Flags or dcb_InX;
      if (isBitsOn(mask, FLOWCONTROL_XONXOFF_OUT)) then dcb.Flags := dcb.Flags or dcb_OutX;
    end;
    if (SetCommState(portHandle, dcb)) then Result := true;
  end;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение режима контроля потока. (-1 - ошибка).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function getFlowControlMode(portHandle: THandle): int;
var dcb: TDCB;
begin
  Result := -1;
  if (GetCommState(portHandle, dcb)) then
  begin
    Result := FLOWCONTROL_NONE;
    if (isBitsOn(dcb.Flags, dcb_RtsControlHandshake)) then Result := Result or FLOWCONTROL_RTSCTS_IN;
    if (isBitsOn(dcb.Flags, dcb_OutxCtsFlow)) then  Result := Result or FLOWCONTROL_RTSCTS_OUT;
    if (isBitsOn(dcb.Flags, dcb_InX)) then Result := Result or FLOWCONTROL_XONXOFF_IN;
    if (isBitsOn(dcb.Flags, dcb_OutX)) then Result := Result or FLOWCONTROL_XONXOFF_OUT;
  end;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Посылка сигнала прерывания в течение заданного времени.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function sendBreak(portHandle: THandle; duration: int): boolean;
begin
  Result := false;
  if (duration > 0) then
  begin
    if (SetCommBreak(portHandle)) then
    begin
      Sleep(duration);
      if (ClearCommBreak(portHandle)) then Result := true;
    end;
  end;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запрос состояний линий. Результат - независимый от архитектуры битовый набор флагов. (-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function getLinesStatus(portHandle: THandle): int;
var modemStat: dword;
begin
  Result := -1;
  if (GetCommModemStatus(portHandle, modemStat)) then
  begin
    Result := 0;
    if (isBitsOn(modemStat, MS_CTS_ON)) then Result := Result or 1;
    if (isBitsOn(modemStat, MS_DSR_ON)) then Result := Result or 2;
    if (isBitsOn(modemStat, MS_RING_ON)) then Result := Result or 4;
    if (isBitsOn(modemStat, MS_RLSD_ON)) then Result := Result or 8;
  end;
end;









/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Чтение из порта в заданную часть массива! Возвращает кол-во считанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function readBytes(portHandle: THandle; buffer: PByte; idx, len: int): int;
var ovp: OVERLAPPED;
begin
  Result := -1;
  ZeroMemory(@ovp, sizeof(ovp));
  ovp.hEvent := CreateEventA(nil, true, false, nil);
  inc(buffer, idx);
  if (not ReadFile(portHandle, buffer^, len, dword(Result), @ovp)) then
  begin
    Result := -1;
    // Проверка на асинхронное чтение.
    if (GetLastError() = ERROR_IO_PENDING) then
    begin
      if (WaitForSingleObject(ovp.hEvent, INFINITE) = WAIT_OBJECT_0) then
      begin
        if (not GetOverlappedResult(portHandle, ovp, dword(Result), false)) then Result := -1; // Если успех, то кол-во считанных байт берем из overlap.
      end;
    end;
  end;
  CloseHandle(ovp.hEvent);
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Чтение из порта одного байта! Возвращает значение считанного байта (=-1 - ошибка, =-2 - байт не считан)!!!
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function readByte(portHandle: THandle): int;
var value: dword;
begin
  Result := readBytes(portHandle, @value, 0, 1);
  case Result of
    0: Result := -2;
    1: Result := value and $FF;
  end;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запись в порт заданной части массива! Возвращает кол-во записанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function writeBytes(portHandle: THandle; buffer: PByte; idx, len: int): int;
var ovp: OVERLAPPED;
begin
  Result := -1;
  ZeroMemory(@ovp, sizeof(ovp));
  ovp.hEvent := CreateEventA(nil, true, false, nil);
  inc(buffer, idx);
  if (not WriteFile(portHandle, buffer^, len, dword(Result), @ovp)) then
  begin
    Result := -1;
    if (GetLastError() = ERROR_IO_PENDING) then
    begin
      if (WaitForSingleObject(ovp.hEvent, INFINITE) = WAIT_OBJECT_0) then
      begin
        if (not GetOverlappedResult(portHandle, ovp, dword(Result), false)) then Result := -1;
      end;
    end;
  end;
  CloseHandle(ovp.hEvent);
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запись в порт одного байта! Возвращает кол-во записанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function writeByte(portHandle: THandle; value: int): int;
begin
  Result := writeBytes(portHandle, @value, 0, 1);
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Получение кол-ва доступных для чтения байт во входном буфере порта (= -1 - ошибка).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function getInputBufferBytesCount(portHandle: THandle): int;
var
  errors: dword;
  cs: COMSTAT;
begin
  if (ClearCommError(portHandle, errors, @cs)) then Result := cs.cbInQue else Result := -1;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Получение кол-ва байт в выходном буфере порта (=-1 - ошибка). По идее редко используемая функция.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function getOutputBufferBytesCount(portHandle: THandle): int;
var
  errors: dword;
  cs: COMSTAT;
begin
  if (ClearCommError(portHandle, errors, @cs)) then Result := cs.cbOutQue else Result := -1;
end;


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Проверка работоспособности порта. Используется для проверки дисконнекта! (0-работает, иначе код ошибки, дисконнект)
//===================================================================================================================================================
// * Не выявил методов, которыми можно было бы детектировать отключение устройства!!!
// * Все методы обращения к порту (за исключением read\write) возвращают успех операции (!) после отключения устройства!
// * Остаётся лишь пинговать устройство на уровне приложения... при этом как-то синхронизацию производить...
//
// * Реализовал через попытку открыть порт заново и произвести анализ ошибок - работает нормально:
//   - При подключенном устройстве - ERROR_ACCESS_DENIED - возвращается ноль.
//   - При отключении - ERROR_FILE_NOT_FOUND (но наверное могут быть и другие) - возвращается код ошибки.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function checkPort(const portName: string): int;
var
  hComm: THandle;
  dcb: TDCB;
begin
  // В принципе есть возможность через маппинг получить имя файла хендла, но там много телодвижений...
  hComm := CreateFile(PAnsiChar('\\.\' + portName),
                      GENERIC_READ or GENERIC_WRITE,
                      0,
                      nil,
                      OPEN_EXISTING,
                      FILE_FLAG_OVERLAPPED,
                      0);
  if (hComm <> INVALID_HANDLE_VALUE) then
  begin
    // Порт открывается без проблем - это проблема, значит предыдущий дескриптор битый ???
    Result := int(ERR_PORT_OPENED);
    if (not GetCommState(hComm, dcb)) then Result := int(ERR_INCORRECT_SERIAL_PORT); // (-4) Это не последовательный порт!
    CloseHandle(hComm); // Закрываем файл в любом случае!
  end else
  begin
    case (GetLastError()) of
      ERROR_ACCESS_DENIED:  Result := 0; // Порт уже занят. Так и должно быть, если он до сих пор открыт, всё ОК!
      ERROR_FILE_NOT_FOUND: Result := int(ERR_PORT_NOT_FOUND); // (-2) Порт не найден.
      else                  Result := int(ERR_PORT_NOT_OPENED); // Какая-то иная ошибка.
    end;
  end;
end;

end.

