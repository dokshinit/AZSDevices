////////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2016, Aleksey Nikolaevich Dokshin. All right reserved.
//  Contacts: dant.it@gmail.com, dokshin@list.ru.
//
////////////////////////////////////////////////////////////////////////////////////////////////////
unit dant_crc;

interface

uses
  dant_log, dant_utils;

  function CalcCRC16(const buf; len: int): word; overload;
  function CalcCRC16(const buf: TByteArray; idx, len: int): word; overload;
  function CalcCRC16Sberbank(const buf; len: int): word; overload;
  function CalcCRC16Sberbank(const buf: TByteArray; idx, len: int): word; overload;

implementation

const

  crctab: array[0..255] of word = (
    $0000, $C0C1, $C181, $0140, $C301, $03C0, $0280, $C241,
    $C601, $06C0, $0780, $C741, $0500, $C5C1, $C481, $0440,
    $CC01, $0CC0, $0D80, $CD41, $0F00, $CFC1, $CE81, $0E40,
    $0A00, $CAC1, $CB81, $0B40, $C901, $09C0, $0880, $C841,
    $D801, $18C0, $1980, $D941, $1B00, $DBC1, $DA81, $1A40,
    $1E00, $DEC1, $DF81, $1F40, $DD01, $1DC0, $1C80, $DC41,
    $1400, $D4C1, $D581, $1540, $D701, $17C0, $1680, $D641,
    $D201, $12C0, $1380, $D341, $1100, $D1C1, $D081, $1040,
    $F001, $30C0, $3180, $F141, $3300, $F3C1, $F281, $3240,
    $3600, $F6C1, $F781, $3740, $F501, $35C0, $3480, $F441,
    $3C00, $FCC1, $FD81, $3D40, $FF01, $3FC0, $3E80, $FE41,
    $FA01, $3AC0, $3B80, $FB41, $3900, $F9C1, $F881, $3840,
    $2800, $E8C1, $E981, $2940, $EB01, $2BC0, $2A80, $EA41,
    $EE01, $2EC0, $2F80, $EF41, $2D00, $EDC1, $EC81, $2C40,
    $E401, $24C0, $2580, $E541, $2700, $E7C1, $E681, $2640,
    $2200, $E2C1, $E381, $2340, $E101, $21C0, $2080, $E041,
    $A001, $60C0, $6180, $A141, $6300, $A3C1, $A281, $6240,
    $6600, $A6C1, $A781, $6740, $A501, $65C0, $6480, $A441,
    $6C00, $ACC1, $AD81, $6D40, $AF01, $6FC0, $6E80, $AE41,
    $AA01, $6AC0, $6B80, $AB41, $6900, $A9C1, $A881, $6840,
    $7800, $B8C1, $B981, $7940, $BB01, $7BC0, $7A80, $BA41,
    $BE01, $7EC0, $7F80, $BF41, $7D00, $BDC1, $BC81, $7C40,
    $B401, $74C0, $7580, $B541, $7700, $B7C1, $B681, $7640,
    $7200, $B2C1, $B381, $7340, $B101, $71C0, $7080, $B041,
    $5000, $90C1, $9181, $5140, $9301, $53C0, $5280, $9241,
    $9601, $56C0, $5780, $9741, $5500, $95C1, $9481, $5440,
    $9C01, $5CC0, $5D80, $9D41, $5F00, $9FC1, $9E81, $5E40,
    $5A00, $9AC1, $9B81, $5B40, $9901, $59C0, $5880, $9841,
    $8801, $48C0, $4980, $8941, $4B00, $8BC1, $8A81, $4A40,
    $4E00, $8EC1, $8F81, $4F40, $8D01, $4DC0, $4C80, $8C41,
    $4400, $84C1, $8581, $4540, $8701, $47C0, $4680, $8641,
    $8201, $42C0, $4380, $8341, $4100, $81C1, $8081, $4040 );

  sbcrctab: array[0..255] of word = (
    $0000, $1021, $2042, $3063, $4084, $50a5, $60c6, $70e7,
    $8108, $9129, $a14a, $b16b, $c18c, $d1ad, $e1ce, $f1ef,
    $1231, $0210, $3273, $2252, $52b5, $4294, $72f7, $62d6,
    $9339, $8318, $b37b, $a35a, $d3bd, $c39c, $f3ff, $e3de,
    $2462, $3443, $0420, $1401, $64e6, $74c7, $44a4, $5485,
    $a56a, $b54b, $8528, $9509, $e5ee, $f5cf, $c5ac, $d58d,
    $3653, $2672, $1611, $0630, $76d7, $66f6, $5695, $46b4,
    $b75b, $a77a, $9719, $8738, $f7df, $e7fe, $d79d, $c7bc,
    $48c4, $58e5, $6886, $78a7, $0840, $1861, $2802, $3823,
    $c9cc, $d9ed, $e98e, $f9af, $8948, $9969, $a90a, $b92b,
    $5af5, $4ad4, $7ab7, $6a96, $1a71, $0a50, $3a33, $2a12,
    $dbfd, $cbdc, $fbbf, $eb9e, $9b79, $8b58, $bb3b, $ab1a,
    $6ca6, $7c87, $4ce4, $5cc5, $2c22, $3c03, $0c60, $1c41,
    $edae, $fd8f, $cdec, $ddcd, $ad2a, $bd0b, $8d68, $9d49,
    $7e97, $6eb6, $5ed5, $4ef4, $3e13, $2e32, $1e51, $0e70,
    $ff9f, $efbe, $dfdd, $cffc, $bf1b, $af3a, $9f59, $8f78,
    $9188, $81a9, $b1ca, $a1eb, $d10c, $c12d, $f14e, $e16f,
    $1080, $00a1, $30c2, $20e3, $5004, $4025, $7046, $6067,
    $83b9, $9398, $a3fb, $b3da, $c33d, $d31c, $e37f, $f35e,
    $02b1, $1290, $22f3, $32d2, $4235, $5214, $6277, $7256,
    $b5ea, $a5cb, $95a8, $8589, $f56e, $e54f, $d52c, $c50d,
    $34e2, $24c3, $14a0, $0481, $7466, $6447, $5424, $4405,
    $a7db, $b7fa, $8799, $97b8, $e75f, $f77e, $c71d, $d73c,
    $26d3, $36f2, $0691, $16b0, $6657, $7676, $4615, $5634,
    $d94c, $c96d, $f90e, $e92f, $99c8, $89e9, $b98a, $a9ab,
    $5844, $4865, $7806, $6827, $18c0, $08e1, $3882, $28a3,
    $cb7d, $db5c, $eb3f, $fb1e, $8bf9, $9bd8, $abbb, $bb9a,
    $4a75, $5a54, $6a37, $7a16, $0af1, $1ad0, $2ab3, $3a92,
    $fd2e, $ed0f, $dd6c, $cd4d, $bdaa, $ad8b, $9de8, $8dc9,
    $7c26, $6c07, $5c64, $4c45, $3ca2, $2c83, $1ce0, $0cc1,
    $ef1f, $ff3e, $cf5d, $df7c, $af9b, $bfba, $8fd9, $9ff8,
    $6e17, $7e36, $4e55, $5e74, $2e93, $3eb2, $0ed1, $1ef0);



function CalcCRC16(const buf; len: int): word;
var
 i: integer;
 crc: word;
 p: PChar;
begin
  p := PChar(@buf);
  crc := $FFFF;
  for i:=0 to (len-1) do crc := (crc shr 8) xor (crctab[(crc and $FF) xor Ord(p[i])]);
  Result := crc;
end;

function CalcCRC16(const buf: TByteArray; idx, len: int): word;
begin
  Result := CalcCRC16(buf[idx], len);
end;


// Метод использующийся в терминалах СБЕРБАНКА.
function CalcCRC16Sberbank(const buf; len: int): word;
var
 i: integer;
 crc: word;
 p: PChar;
begin
  p := PChar(@buf);
  crc := $FFFF;
  for i:=0 to (len-1) do crc := word(sbcrctab[((crc shr 8) xor Ord(p[i])) and $FF] xor (crc shl 8));
  Result := crc;
end;

function CalcCRC16Sberbank(const buf: TByteArray; idx, len: int): word;
begin
  Result := CalcCRC16Sberbank(buf[idx], len);
end;



end.
