////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Модуль содержит часто используемые общие вспомогательные средства.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_utils;

{$MODE Delphi}

interface

uses
  SysUtils;

type
  int = integer;
  TByteArray = array of Byte;
  sstring = ShortString;
  string10 = string[10];
  string25 = string[50];
  string50 = string[50];
  string100 = string[100];

  TCID = string[10];

  function iif(f: boolean; const v1, v2: variant): variant; overload;
  function iifp(f: boolean; const v1, v2: pointer): pointer; overload;
  function iicmp(cmp: int; const v1, v2, v3: variant): variant; overload;
  function iicmp(cmp: int; const v1, v2, v3: pointer): pointer; overload;
  function isBitsOn(val, bits: int64): boolean;
  function isBitOn(val, bits: int64): boolean;
  function isBitsOff(val, bits: int64): boolean;
  function isBitOff(val, bits: int64): boolean;
  function isIn(const val: variant; const args: array of variant): boolean;
  function isNotIn(const val: variant; const args: array of variant): boolean;
  function preInc(var v: int; ofs: int = 1): int; overload;
  function preInc(var v: int64; ofs: int64 = 1): int64; overload;
  function preDec(var v: int; ofs: int = 1): int; overload;
  function preDec(var v: int64; ofs: int64 = 1): int64; overload;
  function postInc(var v: int; ofs: int = 1): int; overload;
  function postInc(var v: int64; ofs: int64 = 1): int64; overload;
  function postDec(var v: int; ofs: int = 1): int; overload;
  function postDec(var v: int64; ofs: int64 = 1): int64; overload;
  function cutFor(var v: int; minv, maxv: int): int; overload;
  function cutFor(var v: int64; minv, maxv: int64): int64; overload;

  function SecondsToStr2(sec: integer): string;
  function SecondsToStr3(sec: integer): string;
  function IntToHexChar(val: integer): char;
  function HexCharToInt(hex: char): integer;
  function StrToHexStr(const s: string): string;
  function HexStrToStr(const s: string): string;
  function BufferToHex(const buffer: PByte; index, len: integer): string;
  function LimitStrAfter(const str: string; ch: char; num: integer): string;
  function IDiv2ToStrF(val: int64; len, dig: integer; var res: string): boolean;
  function IDiv2ToStr2(val: int64): string;
  function IDiv3ToStr3(val: int64): string;
  function FloatToStr2(val: Extended): string;
  function StrCharReplace(const str: string; ch, chnew: char): string;
  function StrFixDecimalSeparator(const str: string; sep: char = chr(0)): string;
  function StrRemoveSpaces(const str: string): string;
  function StrFixNumber(const str: string; sep: char = chr(0)): string;
  function StrToIntSafe(const str: string; defval: integer): integer;
  function StrToInt64Safe(const str: string; defval: int64): int64;
  function StrToFloatSafe(const str: string; defval: Extended): Extended;
  function StrFixToIntSafe(const str: string; defval: integer): integer;
  function StrFixToInt64Safe(const str: string; defval: int64): int64;
  function StrFixToFloatSafe(const str: string; defval: Extended): Extended;
  function StrDub(ch: AnsiChar; count: int): string;

  function PosExt(var resultidx: int; ch: char; const str: sstring; idx: int = 0; len: int = -1): boolean; overload;
  function PosExt(ch: char; const str: sstring; idx: int = 0; len: int = -1): int; overload;
  function isStrOfDigits(const str: sstring; idx, len: int): boolean;

  function slash(const s: string): string;
  function unslash(const s: string): string;
  function DeleteFilesFromPath(const path: string): boolean;

  function DTToMilliseconds(const dt: TDateTime): Int64;
  function GetNowInMilliseconds(): Int64;
  function ExtractDate(const dt: TDateTime): TDateTime; overload;
  function ExtractTime(const dt: TDateTime): TDateTime; overload;
  function CompileDateTime(const date, time: TDateTime): TDateTime; overload;
  function dtwParse(const s, snone: string; isnoinc: boolean = false): TDateTime;
  function DTToFmtStr(const fmt: string; const dt: TDateTime): string;
  function CmpTime(dt1, dt2: TDateTime):integer;
  function CmpDate(dt1, dt2: TDateTime):integer;

  function IRound(val: extended): int64;
  function IRoundDiv1(val: int64): int64;
  function IRoundDiv2(val: int64): int64;
  function IRoundDiv3(val: int64): int64;
  function IRoundDiv4(val: int64): int64;
  function IRoundDiv5(val: int64): int64;
  function IRoundMul1(val: extended): int64;
  function IRoundMul2(val: extended): int64;
  function IRoundMul3(val: extended): int64;

  procedure FreeSafe(var obj);
  procedure FreeAndNilSafe(var obj);
  function copyArraySafe(const src: TByteArray; index, len: int; const dst: TByteArray; dstindex: int): int;

  function min(v1, v2: int): int; overload;
  function min(v1, v2: int64): int64; overload;
  function max(v1, v2: int): int; overload;
  function max(v1, v2: int64): int64; overload;

implementation

uses
  StrUtils;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение значения по условию: если f=true - v1, иначе - v2.
// Для оптимизации и читабельности кода.
// ВАЖНО: ВСЕ аргументы вычисляются ВСЕГДА, независимо от значения условия!
////////////////////////////////////////////////////////////////////////////////////////////////////
function iif(f: boolean; const v1, v2: variant): variant;
begin
  if (f) then Result := v1 else Result := v2;
end;

function iifp(f: boolean; const v1, v2: pointer): pointer;
begin
  if (f) then Result := v1 else Result := v2;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение значения по условию: если f=true - v1, иначе - v2.
// Для оптимизации и читабельности кода.
// ВАЖНО: ВСЕ аргументы вычисляются ВСЕГДА, независимо от значения условия!
////////////////////////////////////////////////////////////////////////////////////////////////////
function iicmp(cmp: int; const v1, v2, v3: variant): variant;
begin
  if (cmp < 0) then Result := v1 else if (cmp = 0) then Result := v2 else Result := v3;
end;

function iicmp(cmp: int; const v1, v2, v3: pointer): pointer;
begin
  if (cmp < 0) then Result := v1 else if (cmp = 0) then Result := v2 else Result := v3;
end;



////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка битов значения по маске. Если все (по маске) включены = True, иначе = False.
////////////////////////////////////////////////////////////////////////////////////////////////////
function isBitsOn(val, bits: int64): boolean;
begin
  if ((val and bits) = bits) then Result := True else Result := False;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка битов значения по маске. Если хотя бы один (по маске) включен = True, иначе = False.
////////////////////////////////////////////////////////////////////////////////////////////////////
function isBitOn(val, bits: int64): boolean;
begin
  Result := not isBitsOff(val, bits);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка битов значения по маске. Если все (по маске) выключены = True, иначе = False.
////////////////////////////////////////////////////////////////////////////////////////////////////
function isBitsOff(val, bits: int64): boolean;
begin
  if ((val and bits) = 0) then Result := True else Result := False;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка битов значения по маске. Если хотя бы один (по маске) выключен = True, иначе = False.
////////////////////////////////////////////////////////////////////////////////////////////////////
function isBitOff(val, bits: int64): boolean;
begin
  Result := not isBitsOn(val, bits);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка на совпадение значения с одним из значений в массиве.
// Результат: true - если найдено совпадение, false - не найдено.
////////////////////////////////////////////////////////////////////////////////////////////////////
function isIn(const val: variant; const args: array of variant): boolean;
var i: integer;
begin
  Result := false;
  for i:=Low(args) to High(args) do
  begin
    if (args[i] = val) then
    begin
      Result := true;
      exit;
    end;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка на несовпадение значения ни с одним из значений в массиве.
// Результат: true - если не найдено совпадений, false - найдено.
////////////////////////////////////////////////////////////////////////////////////////////////////
function isNotIn(const val: variant; const args: array of variant): boolean;
begin
  Result := not isIn(val, args);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Возвращает значение текущего времени в миллисекундах.
////////////////////////////////////////////////////////////////////////////////////////////////////
function DTToMilliseconds(const dt: TDateTime): Int64;
begin
  Result := trunc(dt * 86400000.0); // Дробную часть отбрасываем!
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Возвращает значение текущего времени в миллисекундах.
////////////////////////////////////////////////////////////////////////////////////////////////////
function GetNowInMilliseconds(): Int64;
begin
  Result := DTToMilliseconds(Now());
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Извлечение даты с отбрасыванием времени.
////////////////////////////////////////////////////////////////////////////////////////////////////
function ExtractDate(const dt: TDateTime): TDateTime; overload;
begin
  Result := System.int(dt);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Извлечение времени с отбрасыванием даты.
////////////////////////////////////////////////////////////////////////////////////////////////////
function ExtractTime(const dt: TDateTime): TDateTime; overload;
begin
  Result := System.frac(dt);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Комбинация даты и времени (ненужные части соответствующих аргуметов отбрасываются).
////////////////////////////////////////////////////////////////////////////////////////////////////
function CompileDateTime(const date, time: TDateTime): TDateTime; overload;
begin
  Result := ExtractDate(date) + ExtractTime(time);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Сравнение времени двух штампов (даты не сравниваются).
// Возвращает: -1 меньше, 0-равно, 1-больше.
////////////////////////////////////////////////////////////////////////////////////////////////////
function CmpTime(dt1, dt2: TDateTime):integer;
var d1, d2: double;
begin
  d1 := Frac(dt1);
  d2 := Frac(dt2);
  if (d1 < d2) then begin Result := -1; exit; end;
  if (d1 > d2) then begin Result := 1; exit; end;
  Result := 0;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Сравнение дат двух штампов (время не сравнивается).
// Возвращает: -N меньше на N дней, 0-равно, N-больше на N дней.
////////////////////////////////////////////////////////////////////////////////////////////////////
function CmpDate(dt1, dt2: TDateTime):integer;
var d1, d2: double;
begin
  d1 := Trunc(dt1);
  d2 := Trunc(dt2);
  CmpDate := Round(d1 - d2);
end;



////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование кол-ва секунд в строку вида m:ss.
////////////////////////////////////////////////////////////////////////////////////////////////////
function SecondsToStr2(sec: integer):string;
var s,m:integer;
begin
  m := sec div 60;
  s := sec - m*60;
  SecondsToStr2 := Format('%.1d:%.2d', [m, s]);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование кол-ва секунд в строку вида h:mm:ss.
////////////////////////////////////////////////////////////////////////////////////////////////////
function SecondsToStr3(sec: integer):string;
var s,m,h:integer;
begin
  h := sec div 3600;
  m := (sec - h*3600) div 60;
  s := sec - h*3600 - m*60;
  SecondsToStr3 := Format('%d:%.2d:%.2d', [h, m, s]);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение числового эквивалента HEX символа.
////////////////////////////////////////////////////////////////////////////////////////////////////
function IntToHexChar(val: integer): char;
begin
  Result := '0';
  case val of
    0..9: Result := chr(ord('0') + val);
    10..16: Result := chr(ord('A') + val - 10);
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение числового эквивалента HEX символа.
////////////////////////////////////////////////////////////////////////////////////////////////////
function HexCharToInt(hex: char):integer;
begin
  Result := 0;
  case hex of
    '0'..'9': Result := ord(hex)-ord('0');
    'A'..'F': Result := ord(hex)-ord('A') +10;
    'a'..'f': Result := ord(hex)-ord('a') +10;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование участка буфера в HEX строку.
////////////////////////////////////////////////////////////////////////////////////////////////////
function BufferToHex(const buffer: PByte; index, len: integer): string;
var
  p: PByte;
  i, n: integer;
begin
  Result := '';
  p := buffer;
  if (p <> nil) then
  begin
    SetLength(Result, len * 2);
    inc(p, index);
    n := 1;
    for i:=1 to len do
    begin
      Result[n] := IntToHexChar((p^ shr 4) and $F);
      Result[n+1] := IntToHexChar(p^ and $F);
      inc(n, 2);
      inc(p);
    end;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование строки в HEX строку.
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrToHexStr(const s: string): string;
var i: integer;
begin
  Result := '';
  for i:=1 to Length(s) do
  begin
    Result := Result + IntToHex(ord(s[i]), 2);
  end;
  Result := AnsiUpperCase(Result);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование HEX строки в строку. Длина строки должна быть кратна 2!
////////////////////////////////////////////////////////////////////////////////////////////////////
function HexStrToStr(const s: string): string;
var i, n, len: integer;
begin
  Result := '';
  if (Length(s) mod 2) <> 0 then exit; // Ошибка! Не чётная длина!

  len := Length(s) div 2;
  SetLength(Result, len);
  i := 1;
  for n:=1 to len do
  begin
    Result[n] := chr((HexCharToInt(s[i]) shl 4) or HexCharToInt(s[i+1]));
    i := i + 2;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Создание строки заданной длины заполненной указанным символом.
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrDub(ch: AnsiChar; count: int): string;
begin
  SetLength(Result, count);
  FillChar(Result[1], count, ord(ch));
end;





////////////////////////////////////////////////////////////////////////////////////////////////////
// Удаление всех файлов в указанном каталоге (подкаталоги не затрагиваются!)
// Результат: true-выполнено, false-ошибка.
////////////////////////////////////////////////////////////////////////////////////////////////////
function DeleteFilesFromPath(const path: string): boolean;
var
  XSearch: TSearchRec;
begin
  try
    FindFirst(path + '\*.*', faAnyFile + faReadOnly, XSearch);
    DeleteFile(path + '\' + XSearch.Name);
    while FindNext(XSearch) = 0 do DeleteFile(path + '\' + XSearch.Name);
    FindClose(XSearch);
    Result := true;
  except
    Result := false;
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Завершение слэшем строки (если еще не завершена слэшем).
// Из строки сначала удаляются ведущие и концевые пробелы!
////////////////////////////////////////////////////////////////////////////////////////////////////
function slash(const s: string): string;
var i: integer;
begin
  Result := Trim(s);
  i := Length(Result);
  if (i > 0) then
    if (Result[i] <> '\') then Result := Result + '\';
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Удаление из строки завершающего слэша (если он есть).
// Из строки сначала удаляются ведущие и концевые пробелы!
////////////////////////////////////////////////////////////////////////////////////////////////////
function unslash(const s: string): string;
var i: integer;
begin
  Result := Trim(s);
  i := Length(Result);
  if (i > 0) then
    if (Result[i] = '\') then Result := Copy(Result, 1, i-1);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование строки в таймштамп.
// Если строка пустая - из второй строки, если та пустая - текущая дата.
// Если задан isnoinc, и дата без времени, то производится увеличение на 1 сутки (для отработки
// условия "не включено справа").
////////////////////////////////////////////////////////////////////////////////////////////////////
function dtwParse(const s, snone: string; isnoinc: boolean = false): TDateTime;
var ss: String;
begin
  Result := Now();
  try
    ss := Trim(s);
    if (ss = '') then ss := Trim(snone);
    if (ss = '') then exit;
    Result := StrToDateTime(ss);
  except
  end;
  if (isnoinc and (frac(Result) = 0)) then Result := Result + 1; // Добавляем день.
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование даты в строку согласно форматной строке.
// Для удобства стандартная процедура оформлена как ф-ция!
////////////////////////////////////////////////////////////////////////////////////////////////////
function DTToFmtStr(const fmt: string; const dt: TDateTime): string;
begin
  DateTimeToString(Result, fmt, dt);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Безопасное преобразование строки в число. При ошибках - возвращается значение по умолчанию.
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrToIntSafe(const str: string; defval: integer): integer;
begin
  try Result := StrToInt(str); except Result := defval; end;
end;

function StrFixToIntSafe(const str: string; defval: integer): integer;
begin
  try Result := StrToInt(StrFixNumber(str)); except Result := defval; end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Безопасное преобразование строки в число. При ошибках - возвращается значение по умолчанию.
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrToInt64Safe(const str: string; defval: int64): int64;
begin
  try Result := StrToInt64(str); except Result := defval; end;
end;

function StrFixToInt64Safe(const str: string; defval: int64): int64;
begin
  try Result := StrToInt64(StrFixNumber(str)); except Result := defval; end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Безопасное преобразование строки в число. При ошибках - возвращается значение по умолчанию.
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrToFloatSafe(const str: string; defval: Extended): Extended;
begin
  try Result := StrToFloat(StrFixDecimalSeparator(str)); except Result := defval; end;
end;

function StrFixToFloatSafe(const str: string; defval: Extended): Extended;
begin
  try Result := StrToFloat(StrFixNumber(str)); except Result := defval; end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Конвертация вещественного числа в целое с округлением "по 0.5".
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRound(val: extended): int64;
begin
  Result := trunc(val) + iif(Frac(val) >= 0.5, 1, 0);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Конвертация вещественного числа в целое с предварительным умножением на 10 и округлением
// "по 0.5". Т.е. сумму в рублях превращаем в копейки (округление из-за неточночтей вещ.чисел).
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundMul1(val: extended): int64;
begin
  Result := IRound(val * 10);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Конвертация вещественного числа в целое с предварительным умножением на 100 и округлением
// "по 0.5". Т.е. сумму в рублях превращаем в копейки (округление из-за неточночтей вещ.чисел).
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundMul2(val: extended): int64;
begin
  Result := IRound(val * 100);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Конвертация вещественного числа в целое с предварительным умножением на 1000 и округлением
// "по 0.5". Т.е. сумму в рублях превращаем в копейки (округление из-за неточночтей вещ.чисел).
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundMul3(val: extended): int64;
begin
  Result := IRound(val * 1000);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Правильное деление целого числа на 10 с округлением "по 0.5".
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundDiv1(val: int64): int64;
begin
  if (val mod 10 >= 5) then Result := val div 10 + 1 else Result := val div 10;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Правильное деление целого числа на 100 с округлением "по 0.5".
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundDiv2(val: int64): int64;
begin
  if (val mod 100 >= 50) then Result := val div 100 + 1 else Result := val div 100;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Правильное деление целого числа на 1000 с округлением "по 0.5".
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundDiv3(val: int64): int64;
begin
  if (val mod 1000 >= 500) then Result := val div 1000 + 1 else Result := val div 1000;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Правильное деление целого числа на 10000 с округлением "по 0.5".
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundDiv4(val: int64): int64;
begin
  if (val mod 10000 >= 5000) then Result := val div 10000 + 1 else Result := val div 10000;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Правильное деление целого числа на 100000 с округлением "по 0.5".
////////////////////////////////////////////////////////////////////////////////////////////////////
function IRoundDiv5(val: int64): int64;
begin
  if (val mod 100000 >= 50000) then Result := val div 100000 + 1 else Result := val div 100000;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Ограничение строки после первого вхождения заданного символа.
// Если найден указанный символ, то после него допускается только указанное кол-во символов,
// остальные обрезаются. Используется в частности для контроля кол-ва знаков после запятой в
// текстовых представлениях чисел.
////////////////////////////////////////////////////////////////////////////////////////////////////
function LimitStrAfter(const str: string; ch: char; num: integer): string;
var i: integer;
begin
  i := Pos(ch, str);
  if (i > 0) then
  begin
    if (Length(str) - i > num) then
    begin
      Result := MidStr(str, 1, i + num);
      Exit;
    end;
  end;  
  Result := str;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование целого числа деленного на 100 в строку с заданными параметрами, при ошибках
// преобразования возвращает false.
////////////////////////////////////////////////////////////////////////////////////////////////////
function IDiv2ToStrF(val: int64; len, dig: integer; var res: string): boolean;
begin
  try
    res := FloatToStrF(val/100, ffFixed, len, dig);
    Result := true;
  except
    res := '';
    Result := false;
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование целого числа деленного на 100 в строку с двумя разрядами после запятой, при
// ошибках преобразования возвращает пустую строку.
////////////////////////////////////////////////////////////////////////////////////////////////////
function IDiv2ToStr2(val: int64): string;
begin
  try
    Result := FloatToStrF(val/100, ffFixed, 18, 2);
  except
    Result := '';
  end;
end;

function IDiv3ToStr3(val: int64): string;
begin
  try
    Result := FloatToStrF(val/1000, ffFixed, 18, 3);
  except
    Result := '';
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование вещественного в строку с двумя разрядами после запятой, при ошибках преобразования
// возвращает пустую строку.
////////////////////////////////////////////////////////////////////////////////////////////////////
function FloatToStr2(val: Extended): string;
begin
  try
    Result := FloatToStrF(val, ffFixed, 18, 2);
  except
    Result := '';
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Замещение символов в строке (все включения).
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrCharReplace(const str: string; ch, chnew: char): string;
var i: integer;
    s: string;
begin
  s := str;
  for i:=1 to Length(s) do
  begin
    if (s[i] = ch) then s[i] := chnew;
  end;
  Result := s;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Замена десятичных разделителей на корректный символ (по умолчанию - текущий).
// Повторяет уже существующую ф-цию sdofunc.CheckDecimalSeparator()!
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrFixDecimalSeparator(const str: string; sep: char = chr(0)): string;
var i: integer;
begin
  Result := str;
  if (sep = chr(0)) then sep := DecimalSeparator;
  for i:=1 to Length(Result) do
    if ((Result[i] = '.') or (Result[i] = ',')) then Result[i] := sep;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Удаление всех пробелов из строки (всех, а не только ведущих и концевых!).
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrRemoveSpaces(const str: string): string;
var i, n, len: integer;
begin
  len := Length(str);
  n := 0;
  for i := 1 to len do if (str[i] <> ' ') then n := n + 1;
  SetLength(Result, n);
  n := 1;
  for i := 1 to len do
  begin
    if (str[i] <> ' ') then
    begin
      Result[n] := str[i];
      n := n + 1;
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Удаление всех пробелов и замена десятичных разделителей на корректный символ (по умолчанию - текущий).
////////////////////////////////////////////////////////////////////////////////////////////////////
function StrFixNumber(const str: string; sep: char = chr(0)): string;
var i, n, len: integer;
begin
  if (sep = chr(0)) then sep := DecimalSeparator;
  len := Length(str);
  n := 0;
  for i := 1 to len do if (str[i] <> ' ') then n := n + 1;
  SetLength(Result, n);
  n := 1;
  for i := 1 to len do
  begin
    case str[i] of
      ' ':       continue; // Игнорируем пробелы.
      '.', ',':  Result[n] := sep; // Исправляем разделители.
      else       Result[n] := str[i]; // Остальное - как есть.
    end;
    n := n + 1;
  end;
end;




////////////////////////////////////////////////////////////////////////////////////////////////////
procedure FreeSafe(var obj);
var tmp: TObject;
begin
  try
    tmp := TObject(obj);
    if (Assigned(tmp)) then tmp.Free();
  except
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
procedure FreeAndNilSafe(var obj);
var tmp: TObject;
begin
  try
    tmp := TObject(obj);
    if (Assigned(tmp)) then
    begin
      pointer(obj) := nil;
      tmp.Free();
    end;
  except
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Копирование части одного массива в другой.
function copyArraySafe(const src: TByteArray; index, len: int; const dst: TByteArray; dstindex: int): int;
var n: int;
begin
  Result := 0;
  n := Length(src) - index;
  if (n < len) then len := n; // Обрезаем по массиву-источнику.
  n := Length(dst) - dstindex;
  if (n < len) then len := n; // Обрезаем по массиву-приёмнику.
  if (len > 0) then
  begin
    for n := 0 to len - 1 do dst[dstindex + n] := src[index + n];
    Result := len; // Кол-во скопированных байт (которые можно было скопировать корректно).
  end;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Операции определения минимальных\максимальных значений.
function min(v1, v2: int): int;
begin
  if (v1 < v2) then Result := v1 else Result := v2;
end;

function min(v1, v2: int64): int64;
begin
  if (v1 < v2) then Result := v1 else Result := v2;
end;

function max(v1, v2: int): int;
begin
  if (v1 > v2) then Result := v1 else Result := v2;
end;

function max(v1, v2: int64): int64;
begin
  if (v1 > v2) then Result := v1 else Result := v2;
end;



////////////////////////////////////////////////////////////////////////////////////////////////////
// Префиксные операции - значение возвращает ПОСЛЕ изменения.
function preInc(var v: int; ofs: int = 1): int;
begin
  System.inc(v, ofs);
  Result := v;
end;

function preInc(var v: int64; ofs: int64 = 1): int64;
begin
  System.inc(v, ofs);
  Result := v;
end;

function preDec(var v: int; ofs: int = 1): int;
begin
  System.dec(v, ofs);
  Result := v;
end;

function preDec(var v: int64; ofs: int64 = 1): int64;
begin
  System.dec(v, ofs);
  Result := v;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Постфиксные операции - значение возвращает ДО изменения.
function postInc(var v: int; ofs: int = 1): int;
begin
  Result := v;
  System.inc(v, ofs);
end;

function postInc(var v: int64; ofs: int64 = 1): int64;
begin
  Result := v;
  System.inc(v, ofs);
end;

function postDec(var v: int; ofs: int = 1): int;
begin
  Result := v;
  System.dec(v, ofs);
end;

function postDec(var v: int64; ofs: int64 = 1): int64;
begin
  Result := v;
  System.dec(v, ofs);
end;



////////////////////////////////////////////////////////////////////////////////////////////////////
// Обрезка значения переменной по указанному диапазону значений.
// Позиция иинимального и максимального значения не важна (меняются местами, если нужно).
function cutFor(var v: int; minv, maxv: int): int;
var n: int;
begin
  if (minv > maxv) then begin n := minv; minv := maxv; maxv := n; end;
  if (v < minv) then v := minv;
  if (v > maxv) then v := maxv;
  Result := v;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Обрезка значения переменной по указанному диапазону значений.
// Позиция иинимального и максимального значения не важна (меняются местами, если нужно).
function cutFor(var v: int64; minv, maxv: int64): int64;
var n: int64;
begin
  if (minv > maxv) then begin n := minv; minv := maxv; maxv := n; end;
  if (v < minv) then v := minv;
  if (v > maxv) then v := maxv;
  Result := v;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Расширенный поиск символа в строке (с определенной позиции, с ограничением длины).
function PosExt(var resultidx: int; ch: char; const str: sstring; idx: int = 0; len: int = -1): boolean; overload;
var
  i, n, idx2: int;
begin
  Result := false;
  idx2 := Length(str);
  if (idx > idx2) then exit; // Если вышли за строку.
  if (len < 0) then len := idx2-idx+1; // Если длина не задана - длина до конца строки.
  if (idx2 > idx+len-1) then idx2 := idx+len-1; // Если длина не до конца строки, сдвигаем конец до указанной длины.
  for i:=idx to idx2 do
  begin
    if (str[i] = ch) then
    begin
      resultidx := i;
      Result := true;
      exit;
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Расширенный поиск символа в строке (с определенной позиции, с ограничением длины).
function PosExt(ch: char; const str: sstring; idx: int = 0; len: int = -1): int; overload;
begin
  if (not PosExt(Result, ch, str, idx, len)) then Result := -1;
end;

//////////////////////////////////////////////////////////////////////////////////////////////////
// Проверка, являются ли все символы заданного отрезка строки - цифрами.
function isStrOfDigits(const str: sstring; idx, len: int): boolean;
var i: int;
begin
  Result := false;
  if (Length(str) < idx+len-1) then exit;
  for i:=idx to idx+len-1 do if ((str[i] < '0') or (str[i] > '9')) then exit;
  Result := true;
end;





end.
