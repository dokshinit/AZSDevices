unit dant_sync;

interface

uses
  SysUtils, Classes, Windows;

type

  TMutex = class(TObject)
    protected
      fHandle: THandle;
      
    public
      constructor Create(const name: string);
      destructor Destroy(); override;

      function getHandle(): THandle;

      function get(timeout: integer): boolean;
      function release(): boolean;
  end;

  TCriticalSectionExt = class(TObject)
    protected
      fSection: TRTLCriticalSection;

    public
      constructor Create();
      destructor Destroy(); override;

      function TryEnter(): boolean;
      procedure Enter();
      procedure Leave();

      function getLockCount(): integer;
      function getRecursionCount(): integer;
  end;



implementation


constructor TMutex.Create(const name: string);
begin
  inherited Create();
  fHandle := CreateMutex(nil, false, PChar(name));
  if (fHandle = 0) then abort;
end;

destructor TMutex.Destroy();
begin
  if (fHandle <> 0) then CloseHandle(fHandle);
  inherited;
end;

function TMutex.getHandle(): THandle;
begin
  Result := fHandle;
end;

function TMutex.get(timeout: integer): boolean;
begin
  Result := (WaitForSingleObject(fHandle, timeout) = WAIT_OBJECT_0);
end;

function TMutex.release(): boolean;
begin
  Result := ReleaseMutex(fHandle);
end;




constructor TCriticalSectionExt.Create();
begin
  inherited Create();
  InitializeCriticalSection(fSection);
end;

destructor TCriticalSectionExt.Destroy();
begin
  DeleteCriticalSection(fSection);
  inherited;
end;

function TCriticalSectionExt.TryEnter(): boolean;
begin
  Result := TryEnterCriticalSection(fSection);
end;

procedure TCriticalSectionExt.Enter();
begin
  EnterCriticalSection(fSection);
end;

procedure TCriticalSectionExt.Leave();
begin
  LeaveCriticalSection(fSection);
end;

function TCriticalSectionExt.getLockCount(): integer;
begin
  Result := fSection.LockCount;
end;

function TCriticalSectionExt.getRecursionCount(): integer;
begin
  Result := fSection.RecursionCount;
end;


end.