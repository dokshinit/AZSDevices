////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2017, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// Реализация операций работы с сокетами. Обертка классами.
////////////////////////////////////////////////////////////////////////////////////////////////////
unit dant_NetSocket;

interface

uses
  Windows, WinSock, dant_log, dant_utils, dant_DataBuffer;

type

  //////////////////////////////////////////////////////////////////////////////////////////////////
  //  Класс для работы с сетью.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TNetSocket = class
    private
      socket: TSocket;
      addr: TSockAddr;
      closed: boolean;

    protected  
      constructor CreateByAccept(sock: TSocket; var addr: TSockAddr);

    public
      constructor Create(family, socktype, protocol: int); overload;
      constructor CreateTCP();
      constructor CreateUDP();
      destructor Destroy(); override;

      // Client
      function connect(var addr: TSockAddr): boolean;

      // Server
      function bind(var addr: TSockAddr): boolean;
      function listen(backlog: int): boolean;
      function accept(var addr: TSockAddr): TNetSocket;

      // Common
      function isClosed(): boolean;
      procedure close();

      function available(): int;
      function clearReceive(): int;
      function receive(const buffer: PByte; maxsize: int; var addr: TSockAddr): int; overload;
      function receive(const buffer: TDataBuffer; var addr: TSockAddr): int; overload;
      function receive(const buffer: PByte; maxsize: int): int; overload;
      function receive(const buffer: TDataBuffer): int; overload;
      function send(const buffer: PByte; size: int; var addr: TSockAddr): int; overload;
      function send(const buffer: TDataBuffer; var addr: TSockAddr): int; overload;
      function send(const buffer: PByte; size: int): int; overload;
      function send(const buffer: TDataBuffer): int; overload;

      function toString(): String;
  end;

  TExWSA = class (TExError);

  procedure ExWSA(msg: string = '');
  procedure ExWSAIf(exp: boolean; msg: string = '');
  function SockAddrToStr(const addr: TSockAddr): String;

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


function SockAddrToStr(const addr: TSockAddr): String;
begin
  with addr.sin_addr.S_un_b do
    Result := Format('%d.%d.%d.%d:%d', [ord(s_b1), ord(s_b2), ord(s_b3), ord(s_b4), ntohs(addr.sin_port)]);
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор. Создаёт сокет и переводит его в неблокирующий режим.
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TNetSocket.Create(family, socktype, protocol: int);
var res: int;
begin
  try
    // Создание сокета.
    socket := WinSock.socket(family, socktype, protocol);
    ExWSAIf(socket = INVALID_SOCKET, 'Ошибка создания сокета!');
    // Перевод сокета в неблокирующий режим.
    res := 1;
    ExWSAIf(ioctlsocket(socket, FIONBIO, res) = SOCKET_ERROR, 'Ошибка перевода сокета в неблокируемый режим!');
  except
    socket := INVALID_SOCKET;
    raise;
  end;
end;

constructor TNetSocket.CreateByAccept(sock: TSocket; var addr: TSockAddr);
var res: int;
begin
  try
    // Создание сокета.
    socket := sock;
    ExWSAIf(socket = INVALID_SOCKET, 'Ошибка создания сокета!');
    // Перевод сокета в неблокирующий режим.
    res := 1;
    ExWSAIf(ioctlsocket(socket, FIONBIO, res) = SOCKET_ERROR, 'Ошибка перевода сокета в неблокируемый режим!');
  except
    socket := INVALID_SOCKET;
    raise;
  end;
end;

constructor TNetSocket.CreateTCP();
begin
  Create(AF_INET, SOCK_STREAM, IPPROTO_TCP);
end;

constructor TNetSocket.CreateUDP();
begin
  Create(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
//  addr.sin_family      := AF_INET;
//  addr.sin_addr.S_addr := htonl(INADDR_ANY);
//  addr.sin_port        := htons(port);
//  bind(socket, addr, sizeof(addr));
end;



////////////////////////////////////////////////////////////////////////////////////////////////////
// Деструктор. Закрывает и освобождает сокет.
////////////////////////////////////////////////////////////////////////////////////////////////////
destructor TNetSocket.Destroy();
var
  res: int;
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
// Соединение с удаленной стороной. (для TCP обязательно, для UDP опционально)
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetSocket.connect(var addr: TSockAddr): boolean;
begin
  Result := (WinSock.connect(socket, addr, sizeof(addr)) = 0);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Привязка локального адреса. (для серверной части)
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetSocket.bind(var addr: TSockAddr): boolean;
begin
  Result := (WinSock.bind(socket, addr, sizeof(addr)) = 0);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Включение прослушки локального адреса на входящие соединения. (для серверной части)
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetSocket.listen(backlog: int): boolean;
begin
  Result := (WinSock.listen(socket, backlog) = 0);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Включение прослушки локального адреса на входящие соединения. (для серверной части)
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetSocket.accept(var addr: TSockAddr): TNetSocket;
var
  insock: TSocket;
  inlen: int;
begin
  inlen := sizeof(addr);
  insock := WinSock.accept(socket, @addr, @inlen);
  if (insock <> INVALID_SOCKET) then
  begin
    Result := TNetSocket.CreateByAccept(insock, addr);
  end else
  begin
    Result := nil;
  end;  
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка наличия данных во входящем буфере сокета. Возвращает число байт!
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetSocket.available(): int;
begin
  if (ioctlsocket(socket, FIONREAD, Result) = SOCKET_ERROR) then
    ExWSA('Ошибка запроса наличия данных во входящем буфере сокета!');
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Очистка входящего буфера сокета.
////////////////////////////////////////////////////////////////////////////////////////////////////
function TNetSocket.clearReceive(): int;
var buf: array [1..1024] of Byte;
    addr: TSockAddr;
    n, sz: int;
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
function TNetSocket.receive(const buffer: PByte; maxsize: int; var addr: TSockAddr): int;
var addrlen: int;
begin
  addrlen := sizeof(addr);
  Result := WinSock.recvfrom(socket, buffer^, maxsize, 0, addr, addrlen);
  if (Result = SOCKET_ERROR) then // Если ошибка - проверяем.
  begin
    if (WSAGetLastError() <> WSAEWOULDBLOCK) then ExWSA('Ошибка чтения данных из сокета!');
    Result := 0; // Если асинхронный режим и операция блокирована (нет данных).
  end;
end;

function TNetSocket.receive(const buffer: TDataBuffer; var addr: TSockAddr): int;
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
function TNetSocket.send(const buffer: PByte; size: int; var addr: TSockAddr): int;
var addrlen: int;
begin
  addrlen := sizeof(addr);
  Result := WinSock.sendto(socket, buffer^, size, 0, addr, addrlen);
  if (Result = SOCKET_ERROR) then
  begin
    if (WSAGetLastError() <> WSAEWOULDBLOCK) then ExWSA('Ошибка записи данных в сокет!');
    Result := 0; // Если асинхронный режим и операция блокирована.
  end;
end;

function TNetSocket.send(const buffer: TDataBuffer; var addr: TSockAddr): int;
var buf: PByte;
begin
  buffer.mark();
  buf := @(buffer.buffer()[buffer.offset() + buffer.pos()]); // Запись с текущей позиции в буфере.
  Result := send(buf, buffer.remaining(), addr);
  if (Result > 0) then buffer.shift(Result); // Смещаем позицию на кол-во отправленных байт.
end;


function TNetSocket.toString(): String;
begin
  Result := Format('socket=$%X', [socket]);
end;


initialization

  InitWSA();

finalization

  DoneWSA();

end.
