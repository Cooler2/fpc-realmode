{ %cpu=i8086 }
{ Split an address only after a straight-line store consumes its BX parameter.
  Cover suffix branches, empty loops and cases that must retain the old path. }
{$mode objfpc}
{$Q-}
type
  TBlock = packed record
    signature: Byte;
    owner, paragraphs: Word;
    reserved: array[0..2] of Byte;
    name: array[0..7] of Byte;
  end;
  TGuarded = packed record
    before: Word;
    block: TBlock;
    after: Word;
  end;
  PBlock = ^TBlock;
  TBuild = procedure(dst: PBlock; signature: Byte; owner, count: Word); register;
var
  guarded: TGuarded;
  round, count, i: Word;

procedure Build(var dst: TBlock; signature: Byte; owner, count: Word); register;
var j: Word;
begin
  dst.signature := signature;
  dst.owner := owner;
  dst.paragraphs := count;
  for j := 0 to 2 do dst.reserved[j] := 0;
  for j := 0 to 7 do dst.name[j] := 0;
end;

procedure BuildBranch(var dst: TBlock; signature: Byte; owner, count: Word); register;
var j: Word;
begin
  dst.signature := signature;
  dst.owner := owner;
  dst.paragraphs := count;
  if count <> 0 then
    for j := 0 to count-1 do
      if (j and 1)=0 then dst.name[j] := signature
      else dst.name[j] := Byte(count);
  for j := 0 to 2 do dst.reserved[j] := 0;
end;

procedure EarlyBranch(var dst: TBlock; signature: Byte; owner, count: Word); register;
var j: Word;
begin
  if signature <> 0 then dst.signature := signature
  else dst.signature := $FF;
  dst.owner := owner;
  dst.paragraphs := count;
  for j := 0 to 7 do dst.name[j] := 0;
end;

procedure LateOwner(var dst: TBlock; signature: Byte; owner, count: Word); register;
var j: Word;
begin
  dst.signature := signature;
  dst.owner := owner;
  for j := 0 to 7 do dst.name[j] := 0;
  dst.paragraphs := owner xor count;
end;

procedure PointerValue(dst: PBlock; signature: Byte; owner, count: Word); register;
var j: Word;
begin
  dst^.signature := signature;
  dst^.owner := owner;
  dst^.paragraphs := count;
  for j := 0 to 7 do dst^.name[j] := 0;
end;

procedure Reset;
begin
  FillChar(guarded, SizeOf(guarded), $AA);
  guarded.before := $1234;
  guarded.after := $5678;
end;

procedure Check(owner, paragraphs: Word; signature: Byte);
begin
  if (guarded.before <> $1234) or (guarded.after <> $5678) then Halt(1);
  if (guarded.block.owner <> owner) or
     (guarded.block.paragraphs <> paragraphs) or
     (guarded.block.signature <> signature) then Halt(2);
end;

begin
  { Pointer-typed views preserve the ABI and avoid the independent pinned-base
    near var-address loader defect. The tested callees use var parameters. }
  for round := 0 to 255 do
  begin
    Reset;
    TBuild(@Build)(@guarded.block, Byte(round), round*257, $FFFF-round);
    Check(round*257, $FFFF-round, Byte(round));
    for i := 0 to 2 do if guarded.block.reserved[i] <> 0 then Halt(3);
    for i := 0 to 7 do if guarded.block.name[i] <> 0 then Halt(4);
    for count := 0 to 8 do
    begin
      Reset;
      TBuild(@BuildBranch)(@guarded.block, Byte(round), round*257, count);
      Check(round*257, count, Byte(round));
      for i := 0 to 2 do if guarded.block.reserved[i] <> 0 then Halt(5);
      for i := 0 to 7 do
        if i >= count then
        begin
          if guarded.block.name[i] <> $AA then Halt(6);
        end
        else if (i and 1)=0 then
        begin
          if guarded.block.name[i] <> Byte(round) then Halt(7);
        end
        else if guarded.block.name[i] <> Byte(count) then Halt(8);
    end;
    Reset;
    TBuild(@EarlyBranch)(@guarded.block, Byte(round), round*257, round);
    if round=0 then Check(0, 0, $FF)
    else Check(round*257, round, Byte(round));
    Reset;
    TBuild(@LateOwner)(@guarded.block, Byte(round), round*257, round);
    Check(round*257, (round*257) xor round, Byte(round));
    Reset;
    PointerValue(@guarded.block, Byte(round), round*257, round);
    Check(round*257, round, Byte(round));
    for i := 0 to 7 do if guarded.block.name[i] <> 0 then Halt(9);
  end;
end.
