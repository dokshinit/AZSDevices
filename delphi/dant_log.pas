////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Модуль содержит средства для контроля выполнения программы.
//  - Общие исключения и средства для удобного их вызова и упрощения кода.
//  - Средства глобального перехвата и логирования исключений.
//  - Средства вывода в лог сообщений.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_log;

interface

uses
  SysUtils, SyncObjs, dant_utils;


type
  int = integer;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Исключение (для реализации удобной схемы прерывания выполнения блока кода с гарантированной
  // безопасностью исполнения).
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TExException = class (Exception)
    public
      errorID: int;

      constructor Create(const msg: string = ''); overload;
      constructor Create(errid: int; const msg: string = ''); overload;
      constructor Create(const fmt: string; const args: array of const); overload;
      constructor Create(errid: int; const fmt: string; const args: array of const); overload;
  end;


  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Исключение "Прерывание" (для реализации удобной схемы прерывания выполнения
  // блока кода с гарантированной безопасностью исполнения).
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TExBreak = class (TExException);

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Исключение "Выход" (используется в процедурах для инициации выхода с
  // последующей корректной его обработкой). Например для выхода с последующим
  // удалением всех созданных объектов.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TExExit = class (TExException);

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Исключение "Ошибка". Конструктор без параметра не добавил - всегда должна
  // быть указана расшифровка ошибки и\или её причина.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  TExError = class (TExException);


  // Вызов исключения "Прерывание".
  procedure ExBreak(errid: int; const msg: string = ''); overload;
  procedure ExBreak(const msg: string = ''); overload;
  // Вызов исключения "Прерывание" по условию.
  procedure ExBreakIf(expr: boolean; errid: int; const msg: string = ''); overload;
  procedure ExBreakIf(expr: boolean; const msg: string = ''); overload;

  // Вызов исключения "Выход".
  procedure ExExit(errid: int; const msg: string = ''); overload;
  procedure ExExit(const msg: string = ''); overload;
  // Вызов исключения "Выход" по условию.
  procedure ExExitIf(expr: boolean; errid: int; const msg: string = ''); overload;
  procedure ExExitIf(expr: boolean; const msg: string = ''); overload;

  // Вызов исключения "Ошибка" по условию.
  procedure ExError(errid: int; const msg: string = ''); overload;
  procedure ExError(const msg: string = ''); overload;
  // Вызов исключения "Ошибка" по условию.
  procedure ExErrorIf(expr: boolean; errid: int; const msg: string = ''); overload;
  procedure ExErrorIf(expr: boolean; const msg: string = ''); overload;


  //////////////////////////////////////////////////////////////////////////////////////////////////
  // ВЫВОД В ФАЙЛОВЫЙ ЛОГ
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Вывод строки в файл с синхронизацией вывода (последовательный) для потоков.
  function logToFileSync(const sync: TCriticalSection; const name, msg: String; isdts: Boolean = True): Boolean; overload;
  function logToFileSync(const sync: TCriticalSection; const name, fmt: String; const args: array of const; isdts: Boolean = True): Boolean; overload;

  // ДАЛЕЕ ВО ВСЕХ КОМАНДАХ ИСПОЛЬЗУЕТСЯ СИНХРОНИЗИРОВАННЫЙ ВЫВОД!!!

  // Вывод строки в файл логирования исключений.
  function logEx(const msg: String; isdts: Boolean = True): Boolean; overload;
  function logEx(const fmt: String; const args: array of const; isdts: Boolean = True): Boolean;  overload;
  // Вывод строки в файл логирования сообщений.
  function logMsg(const msg: String; isdts: Boolean = True): Boolean;  overload;
  function logMsg(const fmt: String; const args: array of const; isdts: Boolean = True): Boolean;  overload;
  // Вывод строки в файл логирования сообщений с ТРК (каждая ТРК в свой файл).
  function logTrk(const trkid: int; const msg: String; isdts: boolean = True): Boolean; overload;
  function logTrk(const trkid: int; const fmt: String; const args: array of const; isdts: Boolean = True): Boolean; overload;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // АВТОМАТИЧЕСКОЕ ЛОГИРОВАНИЕ ИСКЛЮЧЕНИЙ
  //////////////////////////////////////////////////////////////////////////////////////////////////

var
  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Вывод всех фреймов при исключении: True - все фреймы, False - до первого обработчика исключения.
  //////////////////////////////////////////////////////////////////////////////////////////////////
  isAllFramesInExceptionLog: Boolean = true;

  // Не выводить в лог исключения TExException и его потомков.
  isOwnExInExceptionLog: Boolean = false;

  // Абсолютный путь к каталогу вывода лог файлов. Сделано для исключения ошибок при изменении
  // программой текущего каталога (например в АРМ при импорте файлов!).
  FullLogPath: string;


  // Включение\отключение глобального логирования исключений.
  procedure setExceptionLog(i: Boolean);



implementation

uses
  Classes,
  // Для отладки
  JclDebug, JclHookExcept, TypInfo, TlHelp32;

var
  LastExceptInfo    : TJclLocationInfo;
  LastExceptInfoStr : String;
  LastExceptMsg     : String;

  // Для синхронизации операций записи в лог (файлового вывода) между разными потоками.
  IOCS_Ex: TCriticalSection;
  IOCS_Msg: TCriticalSection;
  IOCS_Trk: array [1..32] of TCriticalSection;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Конструктор для исключения.
////////////////////////////////////////////////////////////////////////////////////////////////////
constructor TExException.Create(const msg: string = '');
begin
  inherited Create(msg);
  errorID := 0;
end;

constructor TExException.Create(errid: int; const msg: string = '');
begin
  inherited Create(msg);
  errorID := errid;
end;

constructor TExException.Create(const fmt: string; const args: array of const);
begin
  inherited Create(Format(fmt, args));
  errorID := 0;
end;

constructor TExException.Create(errid: int; const fmt: string; const args: array of const);
begin
  inherited Create(Format(fmt, args));
  errorID := errid;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вызов исключения "Прерывание".
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExBreak(errid: int; const msg: string);
begin
  raise TExBreak.Create(errid, msg);
end;

procedure ExBreak(const msg: string);
begin
  ExBreak(0, msg);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вызов исключения "Прерывание" при expr = True.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExBreakIf(expr: boolean; errid: int; const msg: string);
begin
  if (expr) then raise TExBreak.Create(errid, msg);
end;

procedure ExBreakIf(expr: boolean; const msg: string);
begin
  ExBreakIf(expr, 0, msg);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вызов исключения "Выход".
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExExit(errid: int; const msg: string);
begin
  raise TExExit.Create(errid, msg);
end;

procedure ExExit(const msg: string);
begin
  ExExit(0, msg);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вызов исключения "Выход" при expr = True.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExExitIf(expr: boolean; errid: int; const msg: string);
begin
  if (expr) then raise TExExit.Create(errid, msg);
end;

procedure ExExitIf(expr: boolean; const msg: string);
begin
  ExExitIf(expr, 0, msg);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вызов исключения "Ошибка".
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExError(errid: int; const msg: string);
begin
  raise TExError.Create(errid, msg);
end;

procedure ExError(const msg: string);
begin
  ExError(0, msg);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вызов исключения "Ошибка" при expr = True.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure ExErrorIf(expr: boolean; errid: int; const msg: string);
begin
  if (expr) then raise TExError.Create(errid, msg);
end;

procedure ExErrorIf(expr: boolean; const msg: string);
begin
  ExErrorIf(expr, 0, msg);
end;


function StrInjectReturnShifts(msg: string; offset: int): String;
var
  stab: String;
  i: int;
begin
  SetLength(stab, offset);
  for i:=1 to offset do stab[i] := ' ';

  Result := '';
  for i:=1 to Length(msg) do
  begin
    Result := Result + msg[i];
    if (msg[i] = #10) then Result := Result + stab;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вывод строки в логфайл с синхронизацией вывода между потоками.
//--------------------------------------------------------------------------------------------------
// name - имя файла, s - сообщение (%T в имени преобразуется в таймштамп, но только первый!)
////////////////////////////////////////////////////////////////////////////////////////////////////
function logToFileSync(const sync: TCriticalSection; const name, msg: String; isdts: boolean): Boolean;
var
  FL: TextFile;
  dt: TDateTime;
  y, m, d, hh, mm, ss, ms: Word;
  n: int;
  ts, sname, smsg: String;
  errid: int;
begin
  Result := False;

  dt := Now();
  DecodeDate(dt, y, m, d);
  DecodeTime(dt, hh, mm, ss, ms);
  sname := name;
  smsg := msg;

  if (sname = '') then
  begin
    sname := 'common.log';
  end else
  begin
    n := Pos('%T', sname);
    if (n <> 0) then
    begin
      sname := Copy(sname, 1, n-1) + Format('%.4d_%.2d_%.2d', [y, m, d]) + Copy(sname, n+2, Length(sname));
    end;
  end;

  if (isdts) then
  begin
      // Таймштамп для сообщения.
      ts := Format('%.4d.%.2d.%.2d %.2d:%.2d:%.2d.%.3d  ', [y, m, d, hh, mm, ss, ms]);
      // Делаем оступ равный длине таймштампа для вставки после каждого перевода строки (форматирование).
      smsg := ts + StrInjectReturnShifts(smsg, Length(ts));
  end;

  // Вход в секцию с синхронным доступом из потоков.
  sync.Enter;
  try
    try
      Result := False;
      AssignFile(FL, sname);
      {$I-}
      Append(FL);
      {$I+}
      errid := IOResult;
      if (errid <> 0) then
      begin
        {$I-}
        Rewrite(FL);
        {$I+}
        errid := IOResult;
      end;
      if (errid = 0) then
      begin
        try
          {$I-}
          Writeln(FL, smsg);
          {$I+}
          errid := IOResult;
          if (errid = 0) then
          begin
            {$I-}
            Flush(FL);
            {$I+}
            errid := IOResult;
            if (errid = 0) then Result := True;
          end;
        except
        end;
      end;
      {$I-}
      CloseFile(FL);
      {$I+}
      errid := IOResult;
      if (errid <> 0) then Result := False;
      //raise TExBreak.Create('Проверка ошибки!'); // По идее её должно отфильтровывать!

    except
      Result := False;
    end;
  finally
    // Выход из секции с синхронным доступом из потоков.
    sync.Leave;
  end;
end;


function logToFileSync(const sync: TCriticalSection; const name, fmt: String; const args: array of const; isdts: Boolean = True): Boolean;
begin
  Result := logToFileSync(sync, name, Format(fmt, args), isdts);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вывод строки в лог исключений.
////////////////////////////////////////////////////////////////////////////////////////////////////
function logEx(const msg: String; isdts: boolean): Boolean;
begin
  Result := logToFileSync(IOCS_Ex, FullLogPath + 'Ex_%T.log', msg, isdts);
end;


function logEx(const fmt: String; const args: array of const; isdts: Boolean = True): Boolean;
begin
  Result := logEx(Format(fmt, args), isdts);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вывод строки в лог сообщений.
////////////////////////////////////////////////////////////////////////////////////////////////////
function logMsg(const msg: String; isdts: boolean): Boolean;
begin
  Result := logToFileSync(IOCS_Msg, FullLogPath + 'Msg_%T.log', msg, isdts);
end;


function logMsg(const fmt: String; const args: array of const; isdts: Boolean = True): Boolean;
begin
  Result := logMsg(Format(fmt, args), isdts);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Вывод строки в файл логирования сообщений с ТРК (каждая ТРК в свой файл).
////////////////////////////////////////////////////////////////////////////////////////////////////
function logTrk(const trkid: int; const msg: String; isdts: boolean): Boolean;
begin
  Result := False;
  if (trkid >= 1) and (trkid <= 32) then
  begin
    Result := logToFileSync(IOCS_Trk[trkid], FullLogPath + 'Trk_%T-'+Format('%.2d',[trkid])+'.log', msg, isdts);
  end;
end;


function logTrk(const trkid: int; const fmt: String; const args: array of const; isdts: Boolean = True): Boolean;
begin
  Result := logTrk(trkid, Format(fmt, args), isdts);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Процедура обработки перехваченных исключений
//--------------------------------------------------------------------------------------------------
// ExceptObj - объект исключения; ExceptAddr - адрес исключения; IsOS - системное или нет;
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure LogExceptionProc(ExceptObj: TObject; ExceptAddr: Pointer; IsOS: Boolean);
var
  Info: TJclLocationInfo;
  Frame: TJclExceptFrame;
  isHandled, isFirst: Boolean;
  s: String;
  i: int;
  Code, Handler: Pointer;
  SL: TStringList;
begin
  if (ExceptObj is TExExit) then Exit;

  if (not isOwnExInExceptionLog) then
  begin
    // Не логировать пользовательские исключения унаследованные от базового!
    if (ExceptObj is TExException) then Exit;
    if (ExceptObj.ClassType.InheritsFrom(TExException)) then Exit;
  end;

  Info := GetLocationInfo(ExceptAddr);
  // Исключаем случаи, когда исключения происходят внутри процедур вывода лога для предотвращения
  // рекускии (при ошибках выводом в файл например). Для корректной работы требуется, чтобы была
  // включена отладочная информация!!!
  if ((Info.UnitName = 'dant_log') and (Pos('log', Info.ProcedureName) = 1)) then exit;

  s := '  Exception ' + ExceptObj.ClassName;
  if (ExceptObj is Exception) then
  begin
    s := s + ': ';
    s := s + StrInjectReturnShifts(Exception(ExceptObj).Message, Length(s));
  end;

  if (IsOS) then s := s + ' (OS Exception)';
  // >> Шапка
  logEx('====================================================================================================', False);
  logEx('[ ' + DateTimeToStr(Now()) + ' ]', False);
  logEx('----------------------------------------------------------------------------------------------------', False);
  logEx(s, False);

  s := Format('    (Code 0x%p, Line %d, Procedure "%s", Module "%s", Unit "%s")',
              [Info.Address, Info.LineNumber, Info.ProcedureName, Info.UnitName, Info.SourceName]);
  // >> Конец шапки, детализация
  logEx(s, False);
  logEx('----------------------------------------------------------------------------------------------------', False);

  if (stExceptFrame in JclStackTrackingOptions) then
  begin
    i := 0;
    isHandled := False;
    isFirst := True;
    isAllFramesInExceptionLog := True;
    // Раскручиваем фреймы до первого обработчика исключения (или всё, если стоит флаг isAllExceptionFrames
    while (((isAllFramesInExceptionLog) or (not isHandled)) and (i < JclLastExceptFrameList.Count)) do
    begin
      Frame := JclLastExceptFrameList.Items[I];
      isHandled := Frame.HandlerInfo(ExceptObj, Handler);
      Code := Frame.CodeLocation;

      Info := GetLocationInfo(Code);
      s := Format('    FRAME 0x%p: Line %5d, Procedure "%s", Module "%s", Unit "%s", Code 0x%p, Type %s',
                  [Frame.FrameLocation,
                   Info.LineNumber, Info.ProcedureName, Info.UnitName, Info.SourceName,
                   Code, GetEnumName(TypeInfo(TExceptFrameKind), Ord(Frame.FrameKind))]);
      logEx(s, False); // >> Фрейм возниконовения ошибки

      // Первый элемент запоминаем для внешних обработчиков (try ...except)
      if (isFirst) then
      begin
        LastExceptInfo := Info;
        LastExceptInfoStr := s;
        LastExceptMsg  := Exception(ExceptObj).Message;
        isFirst := False;
      end;

      if (isHandled) then
      begin
        Info := GetLocationInfo(Handler);
        s := Format('             HANDLER: Line %5d, Procedure "%s", Module "%s", Unit "%s", Code 0x%p',
                    [Info.LineNumber, Info.ProcedureName, Info.UnitName, Info.SourceName,
                     Handler, GetEnumName(TypeInfo(TExceptFrameKind), Ord(Frame.FrameKind))]);
        logEx(s, False); // >> Фрейм обработчика исключения
      end;
      i := i + 1;
    end;
  end;

  logEx('', False); // >> разделитель

  SL := TStringList.Create;
  with TJclStackInfoList.Create(True, 0, nil) do
  begin
    try
      AddToStrings(SL, False, True, True);
      for i:=0 to SL.Count-1 do
      begin
        logEx('    ' + SL[i], False);
      end;
    finally
      Free;
    end;
  end;
  FreeAndNil(SL);

  logEx('', False); // >> разделитель
  logEx('', False); // >> разделитель
  logEx('', False); // >> разделитель
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка глобального перехвата исключений
//--------------------------------------------------------------------------------------------------
// i -  True - включить, False - выключить
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure setExceptionLog(i: Boolean);
begin
 if (i) then
   JclAddExceptNotifier(LogExceptionProc)
 else
   JclRemoveExceptNotifier(LogExceptionProc);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка\освобождение объектов критических секций для синхронизации доступа.
// Выхывается только при инициализации и финализации модуля!
//--------------------------------------------------------------------------------------------------
// isenable -  True - включить, False - выключить
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure setIOCS(isenable: boolean);
var i: int;
begin
  if (isenable) then
  begin
    IOCS_Ex := TCriticalSection.Create;
    IOCS_Msg := TCriticalSection.Create;
    for i := 1 to 32 do IOCS_Trk[i] := TCriticalSection.Create;
  end else
  begin
    for i := 1 to 32 do IOCS_Trk[i].Free;
    IOCS_Msg.Free;
    IOCS_Ex.Free;
  end;
end;


initialization

  FullLogPath := 'log\';  // По умолчанию каталог log в текущем каталоге.
  setIOCS(true);
  JclStackTrackingOptions := JclStackTrackingOptions + [stExceptFrame];
  JclStartExceptionTracking;
  setExceptionLog(true);
  
finalization

  JclStopExceptionTracking;
  setIOCS(false);

end.


