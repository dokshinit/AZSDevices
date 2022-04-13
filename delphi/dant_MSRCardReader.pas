////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2018, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_MSRCardReader;

interface

uses
  dant_utils;

const
  // Состояния считывания треков.
  MSR_STATE_WAIT = 0; // Ожидание данных.
  MSR_STATE_READ = 1; // Чтение трека.
  MSR_STATE_NEXT = 2; // Ожидание начала трека.

type
  // Структура для возврата результата проверки считанных треков.
  TMSRTracks = record
    Track1, Track2, Track3: string[50];
    Len1, Len2, Len3: int;
    State: int;
    isReaded: boolean;
  end;

// Возвращает считанные треки, если есть (при этом очищает их).
function MSRReader_CheckReadedTracks(): TMSRTracks;
// Запуск перехвата клавиатуры для детекции и чтения треков.
function MSRReader_Open(): boolean;
// Остановка перехвата клавиатуры.
procedure MSRReader_Close();


implementation

uses
  Windows, SysUtils,
  dant_sync, dant_qptime;

const
  ScanKeyToChar: string =
                  #0#0'1234567890-='#0#0+
                  'qwertyuiop[]'#13#0'as'+
                  'dfghjkl;'#39'`'#0'\zxcv'+
                  'bnm,./'#0#0#0' ';

  ScanKeyToShiftedChar: string =
                  #0#0'!@#$%^&*()_+'#0#0+
                  'QWERTYUIOP{}'#13#0'AS'+
                  'DFGHJKL:"~'#0'\ZXCV'+
                  'BNM<>?'#0#0#0' ';

  KeyTimeout = 50; // Время ожидания нажатия следующей клавиши. При превышении - завершение чтения.

var
  hook: HHOOK;

  tracks: array [1..3, 1..256] of char; // Треки.
  lens: array [1..3] of int;            // Текущие длины треков.
  curtrack: int;                        // Номер текущего (читаемого) трека (1..2).

  state: int;              // Текущее состояние: 0-нет ввода, 1 - чтение трека, 2 - ожидание след.трека.
  isShiftPressed: boolean; // Флаг индикации нажатия SHIFT.
  tmStart: int64;          // Время начала считывания карты.
  tmLastPressedKey: int64; // Время последней нажатой клавиши.
  lastPressedKey: int;             // Последняя нажатая клавиша.
  lastPressedKeyBlocking: boolean; // Как была обработана: true - вывод заблокирован, false - нет.

  syncState: TCriticalSectionExt; // Синхронизатор доступа к модели (данным чтения).


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверяем, если идёт чтение и время истекло, то завершаем чтение.
// Только для внутреннего использования. Не синхронизированный доступ с состоянию!
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure CheckAndUpdateTimeouts(tm: int64);
begin
  if ((state <> MSR_STATE_WAIT) and (tm - tmLastPressedKey > KeyTimeout)) then
  begin
    if (state = MSR_STATE_READ) then lens[curtrack] := 0; // Текущий читаемый трек откидываем.
    state := MSR_STATE_WAIT;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Возвращает считанные треки, если есть (при этом очищает их).
////////////////////////////////////////////////////////////////////////////////////////////////////
function MSRReader_CheckReadedTracks(): TMSRTracks;
begin
  syncState.Enter();
  try
    CheckAndUpdateTimeouts(GetQPCounterMilliSec());

    Result.State := state;
    if (state = MSR_STATE_WAIT) then
    begin
      with Result do
      begin
        Len1 := lens[1];
        Len2 := lens[2];
        Len3 := lens[3];
        isReaded := (Len1 > 0) or (Len2 > 0) or (Len3 > 0);
        SetLength(Track1, len1);
        if (Len1 > 0) then Move(tracks[1][1], Track1[1], Len1);
        SetLength(Track2, len2);
        if (Len2 > 0) then Move(tracks[2][1], Track2[1], Len2);
        SetLength(Track3, len3);
        if (Len3 > 0) then Move(tracks[3][1], Track3[1], Len3);
      end;
      lens[1] := 0;
      lens[2] := 0;
      lens[3] := 0;
    end else
    begin
      with Result do
      begin
        Len1 := 0;
        Len2 := 0;
        Len3 := 0;
        isReaded := false;
        Track1 := '';
        Track2 := '';
        Track3 := '';
      end;
    end;
  finally
    syncState.Leave();
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Перехватчик обработчика сообщений от клавиатуры.
//--------------------------------------------------------------------------------------------------
// Ожидается маркер одной из дорожек, после чего переход в состояние чтения дорожек.
// Чтение данных до финального маркера, переход в состояние ожидания следующей дорожки.
// Ожидание следующей дорожки или чтение дорожки идет до момента истечения таймаута символа (любые
// символы между треками при этом фильтруются).
////////////////////////////////////////////////////////////////////////////////////////////////////
function KeyboardProc(code: int; wParam: int; lParam: int): LRESULT; stdcall;
var
  tm: int64;
  key: byte;
  ch: char;
  prevstate, nextstate: int;

  procedure clearAllTracks();
  begin
    lens[1] := 0;
    lens[2] := 0;
    lens[3] := 0;
  end;

  function scanToChar(scan: int): char;
  begin
    if (isShiftPressed) then Result := ScanKeyToShiftedChar[scan + 1] else Result := ScanKeyToChar[scan + 1];
  end;

begin
  syncState.Enter();
  try
    tm := GetQPCounterMilliSec(); //GetTickCount(); //GetNowInMilliseconds();
    CheckAndUpdateTimeouts(tm);

    if (state = MSR_STATE_WAIT) then
    begin
      Result := CallNextHookEx(hook, code, wParam, lParam);
      if (code < 0) then exit;
    end else
    begin
      // Если в режиме чтения трека или ожидания - фильтруем вывод.
      // Фильтр не делается только для режима ожидания.
      Result := 1;
    end;

    key := ((lParam shr 16) and $FF); // Скан-код клавиши.
    prevstate := state;
    nextstate := state;

    if (isBitsOff(lParam, $40000000)) then // Клавиша была нажата.
    begin
      if (key in [$2A, $36]) then // shift pressed
      begin
        isShiftPressed := true;
        if (state <> MSR_STATE_WAIT) then tmLastPressedKey := tm;
        exit;
      end;

      ch := scanToChar(key);

      case ch of
        '%': // начало первой дорожки
            begin
              Result := iif(state = MSR_STATE_WAIT, 0, 1); // Если начало - не подавляем вывод.
              if (state = MSR_STATE_WAIT) then clearAllTracks();
              curtrack := 1;
              state := MSR_STATE_READ;
              nextstate := MSR_STATE_READ;
            end;

        ';': // начало второй дорожки
            begin
              Result := iif(state = MSR_STATE_WAIT, 0, 1); // Если начало - не подавляем вывод.
              if (state = MSR_STATE_WAIT) then clearAllTracks();
              curtrack := 2;
              state := MSR_STATE_READ;
              nextstate := MSR_STATE_READ;
            end;

        '+': // начало третьей дорожки
            begin
              Result := iif(state = MSR_STATE_WAIT, 0, 1); // Если начало - не подавляем вывод.
              if (state = MSR_STATE_WAIT) then clearAllTracks();
              curtrack := 3;
              state := MSR_STATE_READ;
              nextstate := MSR_STATE_READ;
            end;

        '?': // конец дорожки
            begin
              if (state = MSR_STATE_READ) then nextstate := MSR_STATE_NEXT; // Ждем след.трек.
            end;

        #13: // конец дорожки (опционально).
            begin
              if (state = MSR_STATE_READ) then
              begin
                state := MSR_STATE_NEXT;     // Игнорируем этот символ!
                nextstate := MSR_STATE_NEXT; // Ждем след.трек.
              end;
            end;
      end;


      // Заносим данные в треки.
      if ((state = MSR_STATE_READ) and (ch <> #0)) then tracks[curtrack][preInc(lens[curtrack])] := ch;

      state := nextstate;
      lastPressedKey := key;
      lastPressedKeyBlocking := Result <> 0;
      // Обновляем таймаут.
      if (state <> MSR_STATE_WAIT) then tmLastPressedKey := tm;

    end else
    begin // клавиша была отпущена
      if (key in [$2A, $36]) then isShiftPressed := false;
      if (lastPressedKey = key) then Result := iif(lastPressedKeyBlocking, 1, 0);
    end;

  finally
    syncState.Leave();
  end;

end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Запуск перехвата клавиатуры для детекции и чтения треков.
////////////////////////////////////////////////////////////////////////////////////////////////////
function MSRReader_Open(): boolean;
begin
  syncState.Enter();
  try
    lens[1] := 0;
    lens[2] := 0;
    lens[3] := 0;
    state := MSR_STATE_WAIT;
    isShiftPressed := (GetKeyState(vk_Shift) < 0);
    if (hook = 0) then
    begin
      hook := SetWindowsHookEx(WH_KEYBOARD, @KeyboardProc, 0, GetCurrentThreadID());
    end;
    Result := (hook <> 0);
  finally
    syncState.Leave();
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Остановка перехвата клавиатуры.
////////////////////////////////////////////////////////////////////////////////////////////////////
procedure MSRReader_Close();
begin
  syncState.Enter();
  try
    if (hook <> 0) then
    begin
      UnhookWindowsHookEx(hook);
      hook := 0;
    end;
    lens[1] := 0;
    lens[2] := 0;
    lens[3] := 0;
    state := MSR_STATE_WAIT;
  finally
    syncState.Leave();
  end;
end;


initialization

  syncState := TCriticalSectionExt.Create();

  hook := 0;
  lens[1] := 0;
  lens[2] := 0;
  lens[3] := 0;
  state := MSR_STATE_WAIT;

finalization

  MSRReader_Close();

  FreeAndNilSafe(syncState);

end.


