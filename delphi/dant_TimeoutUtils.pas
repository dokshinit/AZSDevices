unit dant_TimeoutUtils;

interface

uses
  Windows, dant_log, dant_utils;

type  
  TExTimeout = class (TExError);

  procedure ExTimeout(const msg: string = '');
  procedure ExTimeoutIf(expr: boolean; const msg: string = '');

type
  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Класс для удобной работы с таймаутами.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TTimeout = class
  private
    ftimeout: Int64;
    fstartTime: Int64;
    fcheckTime: Int64;

  public
    constructor Create(timeout: Int64);
    //
    function timeout(): Int64;
    function startTime(): Int64;
    function checkTime(): Int64;
    //
    function elapsed(): Int64; // Вычисление прошедшего времени с начала таймаута.
    function remaining(): Int64; // Вычисление оставшегося времени до конца таймаута.
    //
    function check(): boolean;
    procedure checkEx(const msg: String); overload;
    procedure checkEx(const fmt: String; const args: array of const); overload;
  end;


implementation


procedure ExTimeout(const msg: string = '');
begin
  raise TExTimeout.Create(msg);
end;


procedure ExTimeoutIf(expr: boolean; const msg: string = '');
begin
  if (expr) then raise TExTimeout.Create(msg);
end;


constructor TTimeout.Create(timeout: Int64);
begin
  ftimeout := timeout;
  fstartTime := GetNowInMilliseconds();
  fcheckTime := fstartTime; // По умолчанию первая проверка в момент создания - расхождение = 0.
end;


function TTimeout.timeout(): Int64;
begin
  Result := ftimeout;
end;


function TTimeout.startTime(): Int64;
begin
  Result := fstartTime;
end;


function TTimeout.checkTime(): Int64;
begin
  Result := fcheckTime;
end;


function TTimeout.elapsed(): Int64; // Вычисление прошедшего времени с начала таймаута.
begin
  Result := fcheckTime - fstartTime;
end;


function TTimeout.remaining(): Int64; // Вычисление оставшегося времени до конца таймаута.
begin
  Result := (fstartTime + ftimeout) - fcheckTime;
end;


function TTimeout.check(): boolean;
begin
  fcheckTime := GetNowInMilliseconds();
  Result := (fcheckTime - fstartTime) <= ftimeout;
end;


procedure TTimeout.checkEx(const msg: String);
begin
  if (not check()) then raise TExTimeout.Create(msg);
end;


procedure TTimeout.checkEx(const fmt: String; const args: array of const);
begin
  if (not check()) then raise TExTimeout.Create(fmt, args);
end;


end.
