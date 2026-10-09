{ %cpu=i8086 }
{ Far var parameters may occupy two register ABI locations. Test both
  halves of addresses from the stack, static data and the heap. }
{$mode objfpc}
{$Q-}

{ Near-data models have a separate register var-parameter bug. This test
  covers far addresses and must not depend on that independent fix. }
{$if defined(FPC_MM_LARGE) or defined(FPC_MM_COMPACT) or defined(FPC_MM_HUGE)}
type
  PByte = ^Byte;

var
  global_value: Byte;
  heap_value: PByte;

procedure Touch(var value: Byte); register;
begin
  Inc(value);
end;

procedure Forward(var value: Byte); register;
begin
  Touch(value);
end;

procedure StackTouch(dummy: LongInt; var value: Byte); register;
begin
  if dummy <> $12345678 then
    Halt(1);
  Touch(value);
end;

procedure Pair(var first, second: Byte); register;
begin
  Inc(first);
  Touch(second);
end;

procedure TestLocal;
var
  local_value: Byte;
begin
  local_value := 1;
  Touch(local_value);
  Forward(local_value);
  StackTouch($12345678, local_value);
  Pair(local_value, global_value);
  if local_value <> 5 then
    Halt(2);
end;

begin
  global_value := 10;
  TestLocal;
  Touch(global_value);
  Forward(global_value);
  if global_value <> 13 then
    Halt(3);
  New(heap_value);
  heap_value^ := 20;
  Touch(heap_value^);
  Forward(heap_value^);
  if heap_value^ <> 22 then
    Halt(4);
  Dispose(heap_value);
end.
{$else}
begin
end.
{$endif}
