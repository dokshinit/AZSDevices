unit dant_base64;

interface

uses
  dant_log, dant_utils;

  function Base64Encode(const src; const srclen: int; var dst): int; overload;
  function Base64Encode(const src: TByteArray; const srcindex, srclen: int; var dst: TByteArray; dstindex: int): int; overload;
  function Base64Decode(const src; const srclen: int; var dst): int; overload;
  function Base64Decode(const src: TByteArray; const srcindex, srclen: int; var dst: TByteArray; dstindex: int): int; overload;

implementation


const
  Base64Table: array[0..63] of AnsiChar = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  b64FillChar = '=';
  b64Mask1    = $FC000000;
  b64Mask2    = $03F00000;
  b64Mask3    = $000FC000;
  b64Mask4    = $00003F00;


type
  PBytes = ^TBytes;
  TBytes = packed array[0..0] of byte;

  b64IntChar = packed record case int of
    0: (l : int);
    1: (c : array[0..3] of AnsiChar);
  end;


const
  _FI1 : packed array['A'..'Z'] of byte = (0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25);
  _FI2 : packed array['a'..'z'] of byte = (26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51);
  _FI3 : packed array['0'..'9'] of byte = (52,53,54,55,56,57,58,59,60,61);


function FastIndexOf(const c: AnsiChar): integer;
begin
  case ord(c) of
    $2B,$2D {+-}        : Result := 62;
    $2F,$5F {/_}        : Result := 63;
    $30..$39 {'0'..'9'} : Result := _FI3[c];
    $41..$5A {'A'..'Z'} : Result := _FI1[c];
    $61..$7A {'a'..'z'} : Result := _FI2[c];
    else                  Result := 0;
  end;
end;


function Base64Encode(const src; const srclen: int; var dst): int;
var
  trail, sz, i: int;
  b64: b64IntChar;
  psrc, pdst: PAnsiChar;
begin
  sz    := (srclen div 3) shl 2;
  trail := srclen mod 3;
  if (trail <> 0) then inc(sz, 4); // Надо ли проверять влезет или нет результат?
  Result := sz;

  psrc := PAnsiChar(@src);
  pdst := PAnsiChar(@dst);
  i := 0;
  while (i < (srclen-trail)) do
  begin
    b64.c[3] := psrc[0];
    b64.c[2] := psrc[1];
    b64.c[1] := psrc[2];
    inc(psrc, 3);
    inc(i, 3);

    pdst[0] := Base64Table[(b64.l and b64Mask1) shr 26];
    pdst[1] := Base64Table[(b64.l and b64Mask2) shr 20];
    pdst[2] := Base64Table[(b64.l and b64Mask3) shr 14];
    pdst[3] := Base64Table[(b64.l and b64Mask4) shr 8];
    inc(pdst, 4);
  end;

  b64.l := 0;
  case trail of
    1 : begin
      b64.c[3] := psrc[0];

      pdst[0] := Base64Table[(b64.l and b64Mask1) shr 26];
      pdst[1] := Base64Table[(b64.l and b64Mask2) shr 20];
      pdst[2] := b64FillChar;
      pdst[3] := b64FillChar;
    end;
    2 : begin
      b64.c[3] := psrc[0];
      b64.c[2] := psrc[1];

      pdst[0] := Base64Table[(b64.l and b64Mask1) shr 26];
      pdst[1] := Base64Table[(b64.l and b64Mask2) shr 20];
      pdst[2] := Base64Table[(b64.l and b64Mask3) shr 14];
      pdst[3] := b64FillChar;
    end;
  end;
end;

function Base64Encode(const src: TByteArray; const srcindex, srclen: int; var dst: TByteArray; dstindex: int): int;
begin
  Result := Base64Encode(src[srcindex], srclen, dst[dstindex]);
end;

function Base64Decode(const src; const srclen: int; var dst): int;
var
  trail, szin, szout, i, k : int;
  b64: b64IntChar;
  psrc, pdst: PAnsiChar;
begin
  psrc := PAnsiChar(@src);
  pdst := PAnsiChar(@dst);
  if (psrc[srclen - 1] = b64FillChar) then
  begin
    if (psrc[srclen - 2] = b64FillChar) then trail := 2 else trail := 1;
  end else
  begin
    trail := 0;
  end;  

  if (trail = 0) then szin := srclen else szin := srclen-4;
  szout := (szin shr 2) * 3;
  if (trail <> 0) then
  begin
    if (trail = 1) then inc(szout, 2) else inc(szout, 1);
  end;  
  Result := szout;

  i := 0;
  while (i < szin) do
  begin
    b64.l := 0;
    b64.l := (FastIndexOf(psrc[0]) shl 26) +
             (FastIndexOf(psrc[1]) shl 20) +
             (FastIndexOf(psrc[2]) shl 14) +
             (FastIndexOf(psrc[3]) shl 8);
    inc(psrc, 4);
    inc(i, 4);

    pdst[0] := b64.c[3];
    pdst[1] := b64.c[2];
    pdst[2] := b64.c[1];
    inc(pdst, 3);
  end;

  b64.l := 0;
  case trail of
    1 : begin
      b64.l := (FastIndexOf(psrc[0]) shl 26) +
               (FastIndexOf(psrc[1]) shl 20) +
               (FastIndexOf(psrc[2]) shl 14);
      pdst[0] := b64.c[3];
      pdst[1] := b64.c[2];
    end;
    2 : begin
      b64.l := (FastIndexOf(psrc[0]) shl 26) +
               (FastIndexOf(psrc[1]) shl 20);
      pdst[0] := b64.c[3];
    end;
  end;
end;

function Base64Decode(const src: TByteArray; const srcindex, srclen: int; var dst: TByteArray; dstindex: int): int;
begin
  Result := Base64Decode(src[srcindex], srclen, dst[dstindex]);
end;

end.
