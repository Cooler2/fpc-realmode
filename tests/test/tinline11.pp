{ An inline function whose body is a single assignment to the result, with a
  temp for its parameter, calls another inline function that uses its own
  parameter twice.  Expanding the inner call copies the reference to the outer
  parameter temp, so that temp must not be released before its "single" use
  (internal error 200108231 on targets that keep the temp in a register). }

{$mode objfpc}
{$inline on}

type
  PShortString = ^shortstring;
  PRec = ^TRec;
  TRec = record
    name : PShortString;
  end;

function Inner(const s: shortstring): longint; inline;
begin
  result:=length(s)*1000+ord(s[1]);
end;

function Outer(const s: shortstring): longint; inline;
begin
  result:=Inner(s);
end;

var
  r : TRec;
  p : PRec;
  st : shortstring;
begin
  st:='hello';
  r.name:=@st;
  p:=@r;
  if Outer(p^.name^)<>5000+ord('h') then
    halt(1);
end.
