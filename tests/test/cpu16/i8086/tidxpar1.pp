{ %cpu=i8086 }
{ Indexed accesses must not force register parameter lifetimes into BX.
  Exercise loads, register stores and constant stores, including aliasing. }
{$mode objfpc}
{$Q-}
type
  TBytes = array[0..15] of Byte;
  TWords = array[0..7] of Word;
  PBytes = ^TBytes;
  PWords = ^TWords;
  TBlock = packed record
    signature: Byte;
    owner, paragraphs: Word;
    reserved: array[0..2] of Byte;
    name: array[0..7] of Byte;
  end;
  PBlock = ^TBlock;
  TCopyBytes = procedure(dst,src: PBytes); register;
  TCopyWords = procedure(dst,src: PWords); register;
  TBuild = procedure(dst: PBlock; signature: Byte; owner,paragraphs: Word); register;
  TMixWords = procedure(dst,a,b: PWords; count: Word); register;
var
  source, target: TBytes;
  words1, words2: TWords;
  words3: TWords;
  block: TBlock;
  i, round: Word;

procedure CopyBytes(var dst: TBytes; const src: TBytes); register;
var j: Word;
begin
  for j := 0 to 15 do dst[j] := src[j];
end;

procedure CopyWords(var dst: TWords; const src: TWords); register;
var j: Word;
begin
  for j := 0 to 7 do dst[j] := src[j];
end;

procedure Build(var dst: TBlock; signature: Byte; owner, paragraphs: Word); register;
var j: Word;
begin
  dst.signature := signature;
  dst.owner := owner;
  dst.paragraphs := paragraphs;
  for j := 0 to 2 do dst.reserved[j] := 0;
  for j := 0 to 7 do dst.name[j] := 0;
end;

procedure MixWords(var dst: TWords; const a,b: TWords; count: Word); register;
var j: Word;
begin
  if count <> 0 then
    for j := 0 to count-1 do
      if (j and 1)=0 then dst[j] := a[j] xor b[j]
      else dst[j] := a[j]+b[j];
end;

begin
  { A var/const address and a pointer value use the same register ABI.
    Pointer-typed call sites avoid the independent near-address parameter
    loader defect in the pinned baseline, while exercising var/const callees. }
  for round := 0 to 255 do
  begin
    for i := 0 to 15 do source[i] := Byte(round + i * 17);
    TCopyBytes(@CopyBytes)(@target, @source);
    TCopyBytes(@CopyBytes)(@target, @target);
    for i := 0 to 15 do if target[i] <> source[i] then Halt(1);
    for i := 0 to 7 do words1[i] := Word(round * 257 + i * 997);
    TCopyWords(@CopyWords)(@words2, @words1);
    TCopyWords(@CopyWords)(@words2, @words2);
    for i := 0 to 7 do if words2[i] <> words1[i] then Halt(2);
    for i := 0 to 7 do words3[i] := Word(round * 997 + i * 257);
    TMixWords(@MixWords)(@words2,@words1,@words3,0);
    for i := 0 to 7 do if words2[i] <> words1[i] then Halt(6);
    TMixWords(@MixWords)(@words2,@words1,@words3,8);
    for i := 0 to 7 do
      if (i and 1)=0 then
      begin
        if words2[i] <> (words1[i] xor words3[i]) then Halt(7);
      end
      else if words2[i] <> Word(words1[i]+words3[i]) then Halt(8);
    TMixWords(@MixWords)(@words1,@words1,@words1,8);
    for i := 0 to 7 do
      if (i and 1)=0 then
      begin
        if words1[i] <> 0 then Halt(9);
      end
      else if words1[i] <> Word(2*(round*257+i*997)) then Halt(10);
    FillChar(block, SizeOf(block), $AA);
    TBuild(@Build)(@block, Byte(round), round * 257, $FFFF-round);
    if (block.signature <> Byte(round)) or (block.owner <> round * 257) or
       (block.paragraphs <> $FFFF-round) then Halt(3);
    for i := 0 to 2 do if block.reserved[i] <> 0 then Halt(4);
    for i := 0 to 7 do if block.name[i] <> 0 then Halt(5);
  end;
end.
