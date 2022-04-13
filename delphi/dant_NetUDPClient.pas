////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// Реализация операций сетевого ввода\вывода посредством UDP протокола (датаграм).
////////////////////////////////////////////////////////////////////////////////////////////////////
unit dant_NetUDPClient;

interface

uses
  Windows, WinSock, dant_log, dant_utils, dant_DataBuffer;

type

  //////////////////////////////////////////////////////////////////////////////////////////////////
  //  Класс для работы с сетью.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TNetUDPClient = class
  private
    socket: TSocket;
    //
    sDeviceName: string;
    //

  public
    constructor Create(port: Integer);
    destructor Destroy(); override;

    function available(): integer;
    function clearReceive(): integer;
    function receive(buffer: PByte; maxsize: Integer; var addr: TSockAddr): Integer; overload;
    function receive(buffer: TDataBuffer; var addr: TSockAddr): Integer; overload;
    function send(buffer: PByte; size: Integer; var addr: TSockAddr): Integer; overload;
    function send(buffer: TDataBuffer; var addr: TSockAddr): Integer; overload;

    function toString(): String;
  end;

  TExWSA = class (TExError);

  procedure ExWSA(msg: string = '');
  procedure ExWSAIf(exp: boolean; msg: string = '');
  function SockAddrToStr(var addr: TSockAddr): String;

implementation

uses
  SysUtils;

////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
var
  WSAInited: boolean = false;
  WSAData: TWSAData;

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
    if WSAStartup(MAKEWORD(1,0), WSAData) <> 0 then ExWSA('Ошибка при инициализации механизма сокетов!');
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


function SockAddrToStr(var addr: TSockAddr): String;
begin
  with addr.sin_addr.S_un_b do Result := Format('%d.%d.%d.%d:%d', [ord(s_b1), ord(s_b2), ord(s_b3), ord(s_b4), ntohs(addr.sin_port)]);
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TNetUDPClient.Create(port: Integer);
var
  res: integer;
  addr: TSockAddr;
begin
  try
    // Создание сокета.
    socket := WinSock.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    ExWSAIf(socket = INVALID_SOCKET, 'Ошибка создания сокета!');
    addr.sin_family      := AF_INET;
    addr.sin_addr.S_addr := htonl(INADDR_ANY);
    addr.sin_port        := htons(port);
    bind(socket, addr, SizeOf(addr));
    // Перевод сокета в неблокирующий режим.
    res := 1;
    ExWSAIf(ioctlsocket(socket, FIONBIO, res) = SOCKET_ERROR, 'Ошибка перевода сокета в неблокируемый режим!');
  except
    socket := INVALID_SOCKET;
    raise;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
destructor TNetUDPClient.Destroy();
var
  res: integer;
begin
  try
    if (socket <> INVALID_SOCKET) then
    begin
      // Перевод сокета в блокирующий режим перед закрытием!
      res := 0;
      ioctlsocket(socket, FIONBIO, res);
      WinSock.shutdown(socket, SD_BOTH);
      WinSock.closesocket(socket);
    end;
  except
  end;
  socket := INVALID_SOCKET;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка наличия данных во входящем буфере сокета. Возвращает число байт!
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetUDPClient.available(): integer;
begin
  if (ioctlsocket(socket, FIONREAD, Result) = SOCKET_ERROR) then
    ExWSA('Ошибка запроса наличия данных во входящем буфере сокета!');
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Очистка входящего буфера сокета.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetUDPClient.clearReceive(): integer;
var buf: array [1..1024] of Byte;
    addr: TSockAddr;
    n, sz: integer;
begin
  Result := 0;
  while (true) do
  begin
    n := available();
    if (n <= 0) then break;
    sz := receive(@buf, 1024, addr);
    if (sz > 0) then Result := Result + sz;
  end;
end;



////////////////////////////////////////////////////////////////////////////////////////////////////
// Чтение данных из сокета (в пределах размера буфера и таймаута).
// Происходит чтение только в рамках порции данных возвращенных первым успешным запросом!
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetUDPClient.receive(buffer: PByte; maxsize: Integer; var addr: TSockAddr): Integer;
var addrlen: Integer;
begin
  addrlen := sizeof(addr);
  Result := WinSock.recvfrom(socket, buffer^, maxsize, 0, addr, addrlen);
  if (Result = SOCKET_ERROR) then // Если ошибка - проверяем.
  begin
    if (WSAGetLastError() <> WSAEWOULDBLOCK) then ExWSA('Ошибка чтения данных из сокета!');
    Result := 0; // Если асинхронный режим и операция блокирована (нет данных).
  end;
end;

function TNetUDPClient.receive(buffer: TDataBuffer; var addr: TSockAddr): Integer;
var buf: PByte;
begin
  buffer.mark();
  buf := @(buffer.buffer()[buffer.offset() + buffer.pos()]); // Запись с текущей позиции в буфере.
  Result := receive(buf, buffer.remaining(), addr); // Можем получить кол-во до конца раб.окна.
  if (Result > 0) then buffer.shift(Result); // Смещаем позицию на кол-во полученных байт.
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Запись в сокет.
// Если данные не записаны полностью в пределах таймаута - возвращает кол-во записанных.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetUDPClient.send(buffer: PByte; size: Integer; var addr: TSockAddr): Integer;
var addrlen: Integer;
begin
  addrlen := sizeof(addr);
  Result := WinSock.sendto(socket, buffer^, size, 0, addr, addrlen);
  if (Result = SOCKET_ERROR) then
  begin
    if (WSAGetLastError() <> WSAEWOULDBLOCK) then ExWSA('Ошибка записи данных в сокет!');
    Result := 0; // Если асинхронный режим и операция блокирована.
  end;
end;

function TNetUDPClient.send(buffer: TDataBuffer; var addr: TSockAddr): Integer;
var buf: PByte;
begin
  buffer.mark();
  buf := @(buffer.buffer()[buffer.offset() + buffer.pos()]); // Запись с текущей позиции в буфере.
  Result := send(buf, buffer.remaining(), addr);
  if (Result > 0) then buffer.shift(Result); // Смещаем позицию на кол-во отправленных байт.
end;


function TNetUDPClient.toString(): String;
begin
  Result := Format('name=%s', [sDeviceName]);
end;


initialization

  InitWSA();

finalization

  DoneWSA();

end.

