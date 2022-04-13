////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// Написал свою реализацию т.к. в штатной из System - не возвращает вообще ничего при неполном
// результате. А мне надо было чтобы откидывало только последний неполный символ и возвращало
// остальное.
////////////////////////////////////////////////////////////////////////////////////////////////////

unit dant_utf8;

interface

uses
  dant_utils;

  // PChar/PWideChar Unicode <-> UTF8 conversion
  function dant_UnicodeToUTF8(Dest: PChar; MaxDestBytes: Cardinal; Source: PWideChar; SourceChars: Cardinal): Cardinal;
  function dant_UTF8ToUnicode(Dest: PWideChar; MaxDestChars: Cardinal; Source: PChar; SourceBytes: Cardinal): Cardinal;

  // WideString <-> UTF8 conversion
  function dant_UTF8Encode(const WS: WideString): UTF8String;
  function dant_UTF8Decode(const S: UTF8String): WideString;

  // Ansi <-> UTF8 conversion
  function dant_AnsiToUtf8(const S: string): UTF8String;
  function dant_Utf8ToAnsi(const S: UTF8String): string;

  // Реализация для конвертирования cp866 <-> cp1251.
  function dant_AnsiToOem(const s: string): string;
  function dant_OemToAnsi(const s: string): string;


implementation

const
  tab866to1251: array [0..255] of byte = (
    $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,
    $10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,
    $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,
    $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,
    $40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,
    $50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,
    $60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,
    $70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,

    $C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,
    $D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,
    $E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF,
    $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,
    $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,
    $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,
    $F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF,
    $A8,$B8,$AA,$BA,$AF,$BF,$A1,$A2,$B0,$3F,$B7,$3F,$B9,$A4,$3F,$A0);

  tab1251to866: array [0..255] of byte = (
    $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,
    $10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,
    $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,
    $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,
    $40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,
    $50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,
    $60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,
    $70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,
    $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,
    $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,
    $FF,$F6,$F7,$3F,$FD,$3F,$3F,$3F,$F0,$3F,$F2,$3F,$3F,$3F,$3F,$F4,
    $F8,$3F,$3F,$3F,$3F,$3F,$3F,$FA,$F1,$FC,$F3,$3F,$3F,$3F,$3F,$F5,
    $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,
    $90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F,
    $A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,
    $E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF);


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование Unicode строки в строку UTF8.
// Если строка не помещается в приёмный буфер, то записывается столько СИМВОЛОВ, сколько влезает!!!
// Т.е. если символ занимает три байта, а осталось два - не запишется.
// Возвращается кол-во реально записанных байт.
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_UnicodeToUtf8(Dest: PChar; MaxDestBytes: Cardinal; Source: PWideChar; SourceChars: Cardinal): Cardinal;
var
  i, count: Cardinal;
  c: Cardinal;
begin
  Result := 0;
  if (Source = nil) then Exit; // Если не задан источник - ошибка.

  count := 0;
  i := 0;
  if (Dest <> nil) then // Если задан приёмник декодируем туда и рассчитываем длину декодируемой строки.
  begin
    while ((i < SourceChars) and (count < MaxDestBytes)) do
    begin
      c := Cardinal(Source[i]);
      Inc(i);
      if (c <= $7F) then
      begin
        Dest[count] := Char(c);
        Inc(count);
      end
      else if (c > $7FF) then
      begin
        if (count + 3 > MaxDestBytes) then break; // Не влезает!
        Dest[count] := Char($E0 or (c shr 12));
        Dest[count+1] := Char($80 or ((c shr 6) and $3F));
        Dest[count+2] := Char($80 or (c and $3F));
        Inc(count,3);
      end
      else //  $7F < Source[i] <= $7FF
      begin
        if (count + 2 > MaxDestBytes) then break; // Не влезает!
        Dest[count] := Char($C0 or (c shr 6));
        Dest[count+1] := Char($80 or (c and $3F));
        Inc(count,2);
      end;
    end;
    // Убрал дополнение нулём. Не нужно, да и это неправильно - может портить последний символ!
    //if (count >= MaxDestBytes) then count := MaxDestBytes-1;
    //Dest[count] := #0;
  end
  else
  begin // Если не задан приёмник - просто рассчитываем длину декодируемой строки.
    while (i < SourceChars) do
    begin
      c := Cardinal(Source[i]);
      Inc(i);
      Inc(count);
      if (c > $7F) then
      begin
        Inc(count);
        if (c > $7FF) then Inc(count);
      end;
    end;
  end;
  Result := count; // Возвращаем полное кол-во байт (записанных или рассчитаных).
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
// Преобразование UTF8 строки в строку Unicode.
// Если строка не помещается в приёмный буфер, то записывается столько СИМВОЛОВ, сколько влезает!!!
// Т.е. если символ занимает три байта, а осталось два - не запишется.
// Возвращается кол-во реально записанных байт.
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_Utf8ToUnicode(Dest: PWideChar; MaxDestChars: Cardinal; Source: PChar; SourceBytes: Cardinal): Cardinal;
var
  i, count: Cardinal;
  c: Byte;
  wc: Cardinal;
begin
  Result := 0;
  if (Source = nil) then Exit; // Если не задан источник - ошибка.

  //Result := Cardinal(-1);
  count := 0;
  i := 0;
  if (Dest <> nil) then // Если задан приёмник декодируем туда и рассчитываем длину декодируемой строки.
  begin
    while ((i < SourceBytes) and (count < MaxDestChars)) do
    begin
      wc := Cardinal(Source[i]);
      Inc(i);
      if ((wc and $80) <> 0) then
      begin
        if (i >= SourceBytes) then break; // Неполный символ - отбрасываем и заканчиваем.
        wc := wc and $3F;
        if ((wc and $20) <> 0) then
        begin
          c := Byte(Source[i]);
          Inc(i);
          if ((c and $C0) <> $80) then break;  // Неверный символ - отбрасываем и заканчиваем.
          if (i >= SourceBytes) then break;    // Неполный символ - отбрасываем и заканчиваем.
          wc := (wc shl 6) or (c and $3F);
        end;
        c := Byte(Source[i]);
        Inc(i);
        if ((c and $C0) <> $80) then break; // Неверный символ - отбрасываем и заканчиваем.

        Dest[count] := WideChar((wc shl 6) or (c and $3F));
      end
      else
      begin
        Dest[count] := WideChar(wc);
      end;  
      Inc(count);
    end;
    // Убрал дополнение нулём. Не нужно.
    //if count >= MaxDestChars then count := MaxDestChars-1;
    //Dest[count] := #0;
  end
  else
  begin // Если не задан приёмник - просто рассчитываем длину декодируемой строки.
    while (i < SourceBytes) do
    begin
      c := Byte(Source[i]);
      Inc(i);
      if ((c and $80) <> 0) then
      begin
        if (i >= SourceBytes) then break; // Неполный символ - отбрасываем и заканчиваем.
        c := c and $3F;
        if (c and $20) <> 0 then
        begin
          c := Byte(Source[i]);
          Inc(i);
          if ((c and $C0) <> $80) then break; // Неверный символ - отбрасываем и заканчиваем.
          if (i >= SourceBytes) then break;   // Неполный символ - отбрасываем и заканчиваем.
        end;
        c := Byte(Source[i]);
        Inc(i);
        if ((c and $C0) <> $80) then break; // Неверный символ - отбрасываем и заканчиваем.
      end;
      Inc(count);
    end;
  end;
  Result := count; // Возвращаем полное символов (записанных или рассчитаных).
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_Utf8Encode(const WS: WideString): UTF8String;
var
  L: Integer;
  Temp: UTF8String;
begin
  Result := '';
  if WS = '' then Exit;
  SetLength(Temp, Length(WS) * 3); // С максимальным запасом.
  L := dant_UnicodeToUtf8(PChar(Temp), Length(Temp)+1, PWideChar(WS), Length(WS));
  SetLength(Temp, L);
  Result := Temp;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_Utf8Decode(const S: UTF8String): WideString;
var
  L: Integer;
  Temp: WideString;
begin
  Result := '';
  if S = '' then Exit;
  SetLength(Temp, Length(S)); // С максимальным запасом.
  L := dant_Utf8ToUnicode(PWideChar(Temp), Length(Temp)+1, PChar(S), Length(S));
  SetLength(Temp, L);
  Result := Temp;
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_AnsiToUtf8(const S: string): UTF8String;
begin
  Result := dant_Utf8Encode(S);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_Utf8ToAnsi(const S: UTF8String): string;
begin
  Result := dant_Utf8Decode(S);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_AnsiToOem(const s: string): string;
var i, n: int;
begin
  n := Length(s);
  SetLength(Result, n);
  for i:=1 to n do Result[i] := char(tab1251to866[byte(s[i])]);
end;


////////////////////////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////////////////////////
function dant_OemToAnsi(const s: string): string;
var i, n: int;
begin
  n := Length(s);
  SetLength(Result, n);
  for i:=1 to n do Result[i] := char(tab866to1251[byte(s[i])]);
end;


end.
