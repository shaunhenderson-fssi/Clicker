unit TClicker;

{
  Author:      Shaun (Bill) Henderson
  Company:     Foodstuffs SI
  Created:     April 2026
  Purpose:     Mainly to enable easy replacement of P1.exe on SCO

  Description:
  This form provides a small GUI-automation and inspection tool used to
  locate windows, read their properties, and interact with their controls.
  It allows the user to load and edit automation scripts, execute scripted
  actions, and visually inspect UI elements by hovering the mouse over them.

  The interface includes a script editor with synchronized line numbers,
  buttons for loading and saving script files, and a status area for
  reporting activity. A timer-driven inspector monitors the mouse position
  and retrieves information about the window or control currently under
  the cursor.

  The form also exposes helper routines for interacting with external
  windows, including clicking buttons, setting text in edit controls,
  finding dialogs by title, and performing simulated mouse clicks.

  Notes:
  - The TRichEdit pair (mmoScript and mmoLineNumbers) is used to display
  script text alongside line numbers. Scrolling is synchronized manually
  using EM_GETFIRSTVISIBLELINE and EM_LINESCROLL.

  - The Timer1 component drives the live UI inspector. When enabled, it
  polls the mouse position and updates lblStatus with information about
  the window under the cursor.

  - Script files are loaded and saved using btnLoad and btnSave. The
  filename is tracked in FScriptFilename so the Save button can be
  enabled/disabled appropriately. Files have a .script extension.

  - Automation helpers (ClickButtonSmart, ClickButtonByCaption,
  SetEditText, LeftClickAt, CloseWindowByCaption, etc.) wrap WinAPI
  calls for interacting with external windows. These functions assume
  standard Windows controls and may require adjustments for custom UI
  frameworks.

  - The form handles WM_VSCROLL and WM_MOUSEWHEEL messages to keep the
  line-number gutter aligned with the script editor.

  - This unit is intended for debugging, UI inspection, and script-driven
  automation. It is not designed as a general-purpose text editor.

}

interface

uses
  System.Classes, // TStringList
  System.Generics.Collections, // TArray
  System.SysUtils, // Trim, SameText
  System.TypInfo, // PropInfo
  // System.UITypes, //MessageDlg
  System.Variants, // VarIsNull
  System.Win.ComObj, // CreateOleObject

  Winapi.ActiveX, // CoInitialize
  Winapi.Messages, // Scroll stuff
  Winapi.ShellAPI, // ShellExecute
  Winapi.Windows, // HWND

  Vcl.ComCtrls, // TRichEdit
  Vcl.Controls, // TControl, TWinControl
  Vcl.Dialogs, // TOpenDialog
  Vcl.ExtCtrls, // TTimer
  Vcl.Forms, // TForm
  Vcl.Graphics, // fsBold
  Vcl.StdCtrls, Vcl.Menus; // TButton, TEdit, TLabel, etc

type
  TForm1 = class(TForm)
    btnGo: TButton;
    defaultWindowName: TEdit;
    lblDefaultWindowName: TLabel;
    grpTop: TGroupBox;
    grpBottom: TGroupBox;
    Timer1: TTimer; // this is for when the mouse hovers over something
    grpMiddle: TGroupBox;
    lblStatus: TLabel;
    GroupBox1: TGroupBox;
    GroupBox2: TGroupBox;
    mmoScript: TRichEdit;
    mmoLineNumbers: TRichEdit;
    MainMenu1: TMainMenu;
    File1: TMenuItem;
    Load1: TMenuItem;
    Save1: TMenuItem;
    Quit1: TMenuItem;
    Help1: TMenuItem;
    Reference1: TMenuItem;
    Encryption1: TMenuItem;
    lblPauseTime: TLabel;
    edtPauseTime: TEdit;

    procedure btnGoClick(Sender: TObject);
    procedure tmrInspectorTimer(Sender: TObject);
    procedure mmoScriptChange(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Quit1Click(Sender: TObject);
    procedure Reference1Click(Sender: TObject);
    procedure Encryption1Click(Sender: TObject);
    procedure mmoScriptKeyPress(Sender: TObject; var Key: Char);
    procedure FormDestroy(Sender: TObject);

  private
    FScriptFilename: string;
    FEncryptInput: TEdit;
    FEncryptOutput: TEdit;
    procedure EncryptClick(Sender: TObject);
    procedure CloseWindowByCaption(const WindowTitle: string);
    procedure LeftClickAt(ScreenX, ScreenY: Integer);
    function SetEditText(Edit: HWND; const Value: string): Boolean;
    procedure RunScriptFile(FileName: string);
    procedure RunScriptLines(Lines: TStrings; const SourceName: string);
    procedure ClickElementInternal(const WindowName: string; var Token: string);
    function ExecuteCommand(const parts: TArray<string>; lineNumber: Integer; const SourceName: string): Boolean;
  end;

  PEnumEditsCtx = ^TEnumEditsCtx;

  TEnumEditsCtx = record
    Parent: HWND;
    List: TArray<HWND>;
  end;

  PEnumButtonsCtx = ^TEnumButtonsCtx;

  TEnumButtonsCtx = record
    Parent: HWND;
    Caption: string;
    Found: HWND;
  end;

  PEnumListCtx = ^TEnumListCtx;

  TEnumListCtx = record
    List: TArray<HWND>;
  end;

  PFindWinCtx = ^TFindWinCtx;

  TFindWinCtx = record
    // Search inputs
    TitleOrClass: string; // the exact caption OR class to match
    ExtraClasses: TArray<string>; // additional classes to accept
    // Result
    Found: HWND;
  end;

  PFindByIdCtx = ^TFindByIdCtx;

  TFindByIdCtx = record
    TargetId: Integer;
    Found: HWND;
  end;

  TModifiers = set of (mdCtrl, mdAlt, mdShift, mdWin);

  TFindCaptionCtx = record
    Wanted: string;
    Classes: PPointer;
    ClassCount: Integer;
    Found: HWND;
    Count: Integer;
  end;

  PFindCaptionCtx = ^TFindCaptionCtx;

const
  DIALOG_CLASS = '#32770';
  CR = #13;
  LF = #10;
  CRLF = CR + LF;

  // Icons that go next to line numbers
  RUNNING = '⇒';
  COMPLETED = '✓';
  ERROR = '⚠';

  // UI Automation constants
  UIA_NamePropertyId = 30005;
  UIA_InvokePatternId = 10000;
  TreeScope_Element = $0001;
  TreeScope_Children = $0002;
  TreeScope_Descendants = $0004;
  CLSID_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';
  IID_IUIAutomation: TGUID = '{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}';
  IID_IUIAutomationElement: TGUID = '{D22108AA-8AC5-49A5-837B-37BBB3D7591E}';
  IID_IUIAutomationInvokePattern: TGUID = '{FB377FBE-8EA6-46D5-9C73-6499642D3059}';

  CmdColorMap: array [0 .. 10] of record Cmd: string;
  Color: TColor;
  end = ((Cmd: '#'; Color: clGray), (Cmd: 'DumpWindow'; Color: clRed),
    (Cmd: 'DumpHere'; Color: clRed), (Cmd: 'ClickButton'; Color: clGreen),
    (Cmd: 'ClickElement'; Color: clGreen), (Cmd: 'MouseClick'; Color: clGreen),
    (Cmd: 'PressKey'; Color: clBlue), (Cmd: 'SetText'; Color: clBlue),
    (Cmd: 'TypeText'; Color: clBlue), (Cmd: 'Close'; Color: $0000A5FF), // orange-ish
    (Cmd: 'Sleep'; Color: $00FF00FF) // purple
  );

  // Treat these as "edit-like" window classes
  EDIT_CLASS_NAMES: array [0 .. 4] of PChar = ('Edit', 'TEdit', 'TAKPEdit', 'TAKPScanEdit', 'TRichEdit');

  // Treat these as "button-like" classes (plus we also match by caption text)
  BUTTON_CLASS_NAMES: array [0 .. 4] of PChar = ('Button', 'TButton', 'TAKPButton', 'TFSTouchButton', 'TSpeedButton');

var
  Form1: TForm1;
  IDs: Array of Integer;
  LastTopWindow: HWND;
  FAliases: TStringList;

implementation

{$R *.dfm}
{ ===================== Mouse inspector (unit-scope) ===================== }

var
  GMouseHook: HHOOK = 0;
  GLastTick: DWORD = 0;
  GInspectOn: Boolean = False;

function DeepChildWindowFromPoint(const PtScreen: TPoint): HWND; forward;
function DescribeAtPoint(const PtScreen: TPoint): string; forward;

{ =================== Unit-scope helpers =================== }

function FindTopWindowByTitleOrClass(const TitleOrClass: string): HWND;
begin
  // Try caption first
  Result := FindWindow(nil, PChar(TitleOrClass));
  if Result <> 0 then
    Exit;

  // Try as exact class name
  Result := FindWindow(PChar(TitleOrClass), nil);
end;

procedure ShowTextDialog(const Title, Text: string; Width: Integer = 800; Height: Integer = 600; ShowScrollbars: Boolean = True);
var
  F: TForm;
  M: TMemo;
  B: TButton;
begin
  F := TForm.Create(nil);
  try
    F.Caption := Title;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.Width := Width;
    F.Height := Height;

    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    if ShowScrollbars then
      M.ScrollBars := ssBoth
    else
      M.ScrollBars := ssNone;
    M.ReadOnly := True;
    M.WordWrap := False;
    M.Lines.Text := Text;

    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Close';
    B.ModalResult := mrOK;
    B.Align := alBottom;
    B.Default := True;
    B.Cancel := True;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

function RectToStr(const R: TRect): string;
begin
  Result := Format('[%d %d]',
    [Round((R.Left + R.Right) / 2), Round((R.Top + R.Bottom) / 2)]);
end;

function FormatWindowChildren(Parent: HWND): string;
var
  child: HWND;
  cls, txt: array [0 .. 255] of Char;
  R: TRect;
  S: TStringBuilder;
  ID: LongInt;
begin
  S := TStringBuilder.Create;
  try
    child := 0;
    while True do
    begin
      child := FindWindowEx(Parent, child, nil, nil); // iterate direct children
      if child = 0 then
        Break;

      GetClassName(child, cls, Length(cls));
      GetWindowText(child, txt, Length(txt));
      GetWindowRect(child, R);
      ID := GetWindowLong(child, GWL_ID);

      // add the id to the array
      if not TArray.Contains<Integer>(IDs, ID) then
      begin
        IDs := IDs + [ID];

        S.AppendLine(Format('Child ID=%d Text="%s" HWND=%p Pos=%s Class=%s',
          [ID, txt, Pointer(child), RectToStr(R), cls]));
      end;
    end;

    if S.Length = 0 then
      Result := 'No direct children.'
    else
      Result := S.ToString;
  finally
    S.Free;
  end;
end;

function IsClassIn(AWnd: HWND; const ClassNames: array of PChar): Boolean;
var
  Buf: array [0 .. 255] of Char;
  i: Integer;
begin
  Result := False;
  if (GetClassName(AWnd, Buf, Length(Buf)) <= 0) then
    Exit;

  for i := Low(ClassNames) to High(ClassNames) do
    if SameText(Buf, ClassNames[i]) then
      Exit(True);
end;

function EnumChildProc(HWND: HWND; lParam: lParam): BOOL; stdcall;
var
  ctx: PEnumEditsCtx;
begin
  ctx := PEnumEditsCtx(lParam);

  // Collect any "edit-like" window (Edit, TAKPEdit, TAKPScanEdit)
  if IsClassIn(HWND, EDIT_CLASS_NAMES) then
  begin
    SetLength(ctx^.List, Length(ctx^.List) + 1);
    ctx^.List[High(ctx^.List)] := HWND;
  end;

  // Recurse
  EnumChildWindows(HWND, @EnumChildProc, lParam);
  Result := True;
end;

function GetAllDescendantEdits(Parent: HWND): TArray<HWND>;
var
  ctx: TEnumEditsCtx;
begin
  SetLength(ctx.List, 0);
  ctx.Parent := Parent;
  EnumChildWindows(Parent, @EnumChildProc, lParam(@ctx));
  Result := ctx.List;
end;

function GetWndClassName(HWND: HWND): string;
var
  Buf: array [0 .. 255] of Char;
  n: Integer;
begin
  n := GetClassName(HWND, Buf, Length(Buf));
  if n > 0 then
    SetString(Result, Buf, n)
  else
    Result := '';
end;

function FormatEditsSummary(Parent: HWND): string;
var
  Edits: TArray<HWND>;
  S: TStringBuilder;
  R: TRect;
  t: array [0 .. 255] of Char;
  cls: string;
  ID, j: Integer;
begin
  S := TStringBuilder.Create;
  try
    Edits := GetAllDescendantEdits(Parent);
    if Length(Edits) = 0 then
      Exit('No descendant Edit controls found. (Classes checked: Edit, TAKPEdit, TAKPScanEdit)');

    j := 0;
    for var i := 0 to High(Edits) do
    begin
      GetWindowText(Edits[i], t, Length(t));
      GetWindowRect(Edits[i], R);
      cls := GetWndClassName(Edits[i]);
      ID := GetWindowLong(Edits[i], GWL_ID);

      if not TArray.Contains<Integer>(IDs, ID) then
      begin
        Inc(j);
        IDs := IDs + [ID];
        S.AppendLine(Format('#%d ID=%d HWND=%p Class=%s Text="%s" Rect=%s',
          [j, ID, Pointer(Edits[i]), cls, t, RectToStr(R)]));
      end;
    end;

    Result := S.ToString;
  finally
    S.Free;
  end;
end;

function EnumFindButtonByCaptionProc(h: HWND; lParam: LPARAM): BOOL; stdcall;
var
  ctx: PEnumButtonsCtx;
  TextBuf: array[0..255] of Char;
begin
  ctx := PEnumButtonsCtx(lParam);

  if GetWindowText(h, TextBuf, Length(TextBuf)) > 0 then
  begin
    if SameText(TextBuf, ctx^.Caption) then
    begin
      ctx^.Found := h;
      Exit(False); // stop enumeration
    end;
  end;

  Result := True; // continue
end;

function EnumCollectButtonsProc(HWND: HWND; lParam: lParam): BOOL; stdcall;
var
  ctx: PEnumListCtx;
  t: array [0 .. 255] of Char;
begin
  ctx := PEnumListCtx(lParam);

  if IsClassIn(HWND, BUTTON_CLASS_NAMES) or (GetWindowText(HWND, t, Length(t)) > 0) then
  begin
    SetLength(ctx^.List, Length(ctx^.List) + 1);
    ctx^.List[High(ctx^.List)] := HWND;
  end;

  Result := True;
end;

function GetAllDescendantButtons(Parent: HWND): TArray<HWND>;
var
  ctx: TEnumListCtx;
begin
  SetLength(ctx.List, 0);
  EnumChildWindows(Parent, @EnumCollectButtonsProc, lParam(@ctx));
  Result := ctx.List;
end;

function FormatButtonsSummary(Parent: HWND): string;
var
  Btns: TArray<HWND>;
  S: TStringBuilder;
  R: TRect;
  t: array [0 .. 255] of Char;
  cls: string;
  ID, j: Integer;
begin
  S := TStringBuilder.Create;
  try
    Btns := GetAllDescendantButtons(Parent);
    if Length(Btns) = 0 then
      Exit('No descendant Button-like controls found. (Classes checked: Button, TAKPButton, TFSTouchButton)');

    j := 0;
    for var i := 0 to High(Btns) do
    begin
      GetWindowText(Btns[i], t, Length(t));
      GetWindowRect(Btns[i], R);
      cls := GetWndClassName(Btns[i]);

      ID := GetWindowLong(Btns[i], GWL_ID);

      if not TArray.Contains<Integer>(IDs, ID) then
      begin
        Inc(j);
        IDs := IDs + [ID];

        S.AppendLine(Format('#%d ID=%d HWND=%p Class=%s Text="%s" Rect=%s',
          [j, ID, Pointer(Btns[i]), cls, t, RectToStr(R)]));
      end;
    end;

    Result := S.ToString;
  finally
    S.Free;
  end;
end;

function ShowEditsOrChildrenFor(const TitleOrClass,
  ContextMsg: string): Boolean;
var
  W: HWND;
  Msg: string;
begin
  Result := False;
  W := FindTopWindowByTitleOrClass(TitleOrClass);
  if W = 0 then
  begin
    ShowTextDialog('Error',
      Format('%s' + CRLF + 'Window "%s" NOT FOUND (by caption or class).',
      [ContextMsg, TitleOrClass]), 500, 200);
    Exit;
  end;

  Msg := '* ' + TitleOrClass + ' *' + CRLF +
    'Immediate children:' + CRLF + FormatWindowChildren(W) + CRLF + CRLF +
    'Descendant Edits (Edit/TAKPEdit/TAKPScanEdit):' + CRLF + FormatEditsSummary(W) + CRLF + CRLF +
    'Descendant Buttons (Button/TAKPButton/TFSTouchButton or any with text):' + CRLF + FormatButtonsSummary(W);

  ShowTextDialog('Error', Msg);
  Result := True;
end;

function StripInlineComment(const S: string): string;
var
  i: Integer;
  inQuote: Boolean;
  ch: Char;
begin
  Result := Trim(S);
  inQuote := False;
  i := 1;
  while i <= Length(S) do
  begin
    ch := S[i];

    if ch = '"' then
    begin
      // toggle quote state, handle doubled quotes "" as an escaped quote
      if (i < Length(S)) and (S[i + 1] = '"') then
      begin
        Inc(i, 2); // skip the escaped quote
        Continue;
      end
      else
        inQuote := not inQuote;
    end
    else if ((ch = ';') or (ch = '#')) and not inQuote then
    begin
      // comment begins here; truncate
      Result := Trim(Copy(S, 1, i - 1));
      Exit;
    end;

    Inc(i);
  end;

  Result := Trim(S);
end;

function Tokenize(const S: string): TArray<string>;
var
  lineNoComment: string;
  SL: TStringList;
begin
  Result := [];
  lineNoComment := StripInlineComment(S);
  if lineNoComment = '' then
    Exit(); // empty after stripping comment

  SL := TStringList.Create;
  try
    SL.StrictDelimiter := True;
    // only split on the delimiter, not on whitespace classes
    SL.Delimiter := ' '; // space-delimited
    SL.QuoteChar := '"'; // keep quoted chunks intact
    SL.DelimitedText := lineNoComment;
    // Remove empty tokens caused by multiple spaces
    for var i := SL.Count - 1 downto 0 do
      if SL[i] = '' then
        SL.Delete(i);
    Result := SL.ToStringArray;
  finally
    SL.Free;
  end;
end;

procedure SendInputKey(VK: UINT; KeyDown: Boolean; Extended: Boolean);
var
  Inp: TInput;
begin
  ZeroMemory(@Inp, SizeOf(Inp));
  Inp.Itype := INPUT_KEYBOARD;
  Inp.ki.wVk := VK;
  if not KeyDown then
    Inp.ki.dwFlags := Inp.ki.dwFlags or KEYEVENTF_KEYUP;
  if Extended then
    Inp.ki.dwFlags := Inp.ki.dwFlags or KEYEVENTF_EXTENDEDKEY;
  SendInput(1, @Inp, SizeOf(Inp));
end;

function IsExtendedVK(VK: UINT): Boolean;
begin
  // Extended keys need KEYEVENTF_EXTENDEDKEY
  // See MS docs: arrows, insert/delete/home/end/page keys, numpad '/', etc.
  case VK of
    VK_INSERT, VK_DELETE, VK_HOME, VK_END, VK_PRIOR, VK_NEXT, VK_LEFT, VK_RIGHT,
      VK_UP, VK_DOWN, VK_DIVIDE, VK_NUMLOCK, VK_SNAPSHOT, VK_CANCEL:
      // PrintScreen, Break/Pause behave specially; extended is ok.
      Result := True;
  else
    Result := False;
  end;
end;

procedure TypeText(const S: string);
var
  i: Integer;
  ch: Char;
  VK: UINT;
  k: SHORT;
  shiftNeeded: Boolean;
begin
  for i := 1 to S.Length do
  begin
    ch := S[i];
    k := VkKeyScanEx(ch, GetKeyboardLayout(0));
    if (k = -1) then
      Continue; // char not mappable; you might handle unicode via SendInput scan codes

    VK := BYTE(k);
    shiftNeeded := (k and $0100) <> 0; // bit 0x100 means SHIFT

    if shiftNeeded then
      SendInputKey(VK_SHIFT, True, False);
    SendInputKey(VK, True, IsExtendedVK(VK));
    SendInputKey(VK, False, IsExtendedVK(VK));
    if shiftNeeded then
      SendInputKey(VK_SHIFT, False, False);
  end;
end;

function ClassAllowed(h: HWND; Classes: PPointer; Count: Integer): Boolean;
type
  TPointerArray = array[0..MaxInt div SizeOf(Pointer) - 1] of Pointer;
  PPointerArray = ^TPointerArray;
var
  Buf: array[0..255] of Char;
  Arr: PPointerArray;
  i: Integer;
begin
  Result := False;

  if (Classes = nil) or (Count <= 0) then
    Exit;

  if GetClassName(h, Buf, Length(Buf)) = 0 then
    Exit;

  Arr := PPointerArray(Classes);

  for i := 0 to Count - 1 do
    if SameText(Buf, PChar(Arr^[i])) then
      Exit(True);
end;

function EnumFindByCaption(h: HWND; lParam: LPARAM): BOOL; stdcall;
var
  Ctx: PFindCaptionCtx;
  Txt: array[0..255] of Char;
begin
  Ctx := PFindCaptionCtx(lParam);

  if not ClassAllowed(h, Ctx^.Classes, Ctx^.ClassCount) then
    Exit(True);

  if (GetWindowText(h, Txt, Length(Txt)) > 0) and
     SameText(Txt, Ctx^.Wanted) then
  begin
    Inc(Ctx^.Count);
    Ctx^.Found := h;
  end;

  Result := True;
end;

function FindByCaption(Parent: HWND; const Caption: string; const AcceptedClasses: array of PChar): HWND;
var
  Ctx: TFindCaptionCtx;
begin
  Ctx.Wanted := Caption;
  Ctx.Classes := @AcceptedClasses[0];
  Ctx.ClassCount := Length(AcceptedClasses);
  Ctx.Found := 0;
  Ctx.Count := 0;

  EnumChildWindows(Parent, @EnumFindByCaption, LPARAM(@Ctx));

  if Ctx.Count > 1 then
    raise Exception.CreateFmt(
      'Ambiguous control name "%s" (%d matches)',
      [Caption, Ctx.Count]);

  Result := Ctx.Found;
end;

function TryParseControlIdToken(const S: string; out ID: Integer): Boolean;
var
  t: string;
begin
  if SameText(Copy(S, 1, 3), 'ID:') then
    t := Copy(S, 4, MaxInt)
  else
    t := S;

  Result := TryStrToInt(t, ID);
end;

function EnumFindByIdProc(h: HWND; lParam: lParam): BOOL; stdcall;
var
  ctx: PFindByIdCtx;
begin
  ctx := PFindByIdCtx(lParam);
  if ctx^.Found <> 0 then
    Exit(False);

  if GetWindowLong(h, GWL_ID) = ctx^.TargetId then
  begin
    ctx^.Found := h;
    Exit(False);
  end;

  Result := True;
end;

function FindDescendantByControlId(Parent: HWND; CtrlId: Integer): HWND;
var
  ctx: TFindByIdCtx;
begin
  Result := 0;
  if (Parent = 0) then
    Exit;
  ctx.TargetId := CtrlId;
  ctx.Found := 0;
  EnumChildWindows(Parent, @EnumFindByIdProc, lParam(@ctx));
  Result := ctx.Found;
end;

function FindById(Parent: HWND; ID: Integer): HWND;
begin
  Result := FindDescendantByControlId(Parent, ID);
end;

function TryParseHWNDToken(const S: string; out h: HWND): Boolean;
var
  t: string;
  V: UInt64;
begin
  //Result := False;
  h := 0;
  t := Trim(S);

  // Accept forms: HWND:001A1CE4, 001A1CE4, 0x001A1CE4, $001A1CE4
  if SameText(Copy(t, 1, 5), 'HWND:') then
    t := Copy(t, 6, MaxInt);

  if (Length(t) >= 2) and (t[1] = '0') and (UpCase(t[2]) = 'X') then
    t := Copy(t, 3, MaxInt)
  else if (Length(t) >= 1) and (t[1] = '$') then
    t := Copy(t, 2, MaxInt);

  for var ch in t do
    if not CharInSet(ch, ['0'..'9','A'..'F','a'..'f']) then
      Exit(False);

  if not TryStrToUInt64('$' + t, V) then
    Exit(False);

  h := HWND(V);
  Result := (h <> 0) and IsWindow(h);
end;

function ResolveControl(Parent: HWND; Token: string; const AcceptedClasses: array of PChar): HWND;
var
  ID: Integer;
  h: HWND;
begin
  //Result := 0;

  // 1) Caption / name (PRIMARY)
  Result := FindByCaption(Parent, Token, AcceptedClasses);
  if Result <> 0 then Exit;

  // 2) ID:xxx or numeric token (SECONDARY)
  if TryParseControlIdToken(Token, ID) then
  begin
    Result := FindById(Parent, ID);
    if Result <> 0 then Exit;
  end;

  // 3) HWND:xxxx (LAST RESORT)
  if TryParseHWNDToken(Token, h) then
    Exit(h);

  raise Exception.CreateFmt(
    'Control "%s" not found (by name, ID, or HWND)', [Token]);
end;

function KeyNameToVK(const Name: string; out VK: UINT): Boolean;
var
  S: string;
  n: Integer;
  k: SHORT;
begin
  // Result := False;
  S := Trim(Name);

  // 1) Single displayable character? (letter/digit/punct) → resolve via layout
  if S.Length = 1 then
  begin
    k := VkKeyScanEx(S[1], GetKeyboardLayout(0));
    if k <> -1 then
    begin
      VK := BYTE(k);
      Exit(True);
    end
    else
    begin
      Exit(False);
    end;
  end;

  // 2) Named keys
  if SameText(S, 'Enter') then
    VK := VK_RETURN
  else if SameText(S, 'Esc') or SameText(S, 'Escape') then
    VK := VK_ESCAPE
  else if SameText(S, 'Tab') then
    VK := VK_TAB
  else if SameText(S, 'Backspace') then
    VK := VK_BACK
  else if SameText(S, 'Space') then
    VK := VK_SPACE
  else if SameText(S, 'Left') then
    VK := VK_LEFT
  else if SameText(S, 'Right') then
    VK := VK_RIGHT
  else if SameText(S, 'Up') then
    VK := VK_UP
  else if SameText(S, 'Down') then
    VK := VK_DOWN
  else if SameText(S, 'Insert') then
    VK := VK_INSERT
  else if SameText(S, 'Delete') then
    VK := VK_DELETE
  else if SameText(S, 'Home') then
    VK := VK_HOME
  else if SameText(S, 'End') then
    VK := VK_END
  else if SameText(S, 'PageUp') or SameText(S, 'PgUp') then
    VK := VK_PRIOR
  else if SameText(S, 'PageDown') or SameText(S, 'PgDn') then
    VK := VK_NEXT
  else if SameText(S, 'PrintScreen') then
    VK := VK_SNAPSHOT
  else if SameText(S, 'Pause') or SameText(S, 'Break') then
    VK := VK_CANCEL
  else if SameText(S, 'Apps') or SameText(S, 'Menu') then
    VK := VK_APPS
  else if SameText(S, 'NumLock') then
    VK := VK_NUMLOCK
  else if SameText(S, 'CapsLock') then
    VK := VK_CAPITAL
  else if SameText(S, 'ScrollLock') then
    VK := VK_SCROLL
  else if SameText(S, 'Numpad0') then
    VK := VK_NUMPAD0
  else if SameText(S, 'Numpad1') then
    VK := VK_NUMPAD1
  else if SameText(S, 'Numpad2') then
    VK := VK_NUMPAD2
  else if SameText(S, 'Numpad3') then
    VK := VK_NUMPAD3
  else if SameText(S, 'Numpad4') then
    VK := VK_NUMPAD4
  else if SameText(S, 'Numpad5') then
    VK := VK_NUMPAD5
  else if SameText(S, 'Numpad6') then
    VK := VK_NUMPAD6
  else if SameText(S, 'Numpad7') then
    VK := VK_NUMPAD7
  else if SameText(S, 'Numpad8') then
    VK := VK_NUMPAD8
  else if SameText(S, 'Numpad9') then
    VK := VK_NUMPAD9
  else if SameText(S, 'NumpadAdd') or SameText(S, 'NumpadPlus') then
    VK := VK_ADD
  else if SameText(S, 'NumpadSub') or SameText(S, 'NumpadMinus') then
    VK := VK_SUBTRACT
  else if SameText(S, 'NumpadMul') or SameText(S, 'NumpadMultiply') then
    VK := VK_MULTIPLY
  else if SameText(S, 'NumpadDiv') or SameText(S, 'NumpadDivide') then
    VK := VK_DIVIDE
  else if SameText(S, 'NumpadDec') or SameText(S, 'NumpadDecimal') then
    VK := VK_DECIMAL

  else
  begin
    // 3) Function keys F1..F24
    if (S.Length >= 2) and (UpCase(S[1]) = 'F') and TryStrToInt(Copy(S, 2, MaxInt), n) and (n >= 1) and (n <= 24) then
    begin
      VK := VK_F1 + (n - 1);
      Exit(True);
    end;

    // 4) Final attempt: if someone passed a single punctuation as a "name"
    if S.Length = 1 then
    begin
      k := VkKeyScanEx(S[1], GetKeyboardLayout(0));
      if k <> -1 then
      begin
        VK := BYTE(k);
        Exit(True);
      end;
    end;

    // No mapping found
    Exit(False);
  end;

  // If we got here via the named-keys block, success:
  Result := True;
end;

function ParseModifiers(var Token: string): TModifiers;
var
  parts: TArray<string>;
  i: Integer;
  t: string;
begin
  Result := [];
  // Token is like   Ctrl+Alt+Shift+F5   or  "Ctrl+ ="
  parts := Token.Split(['+']);
  if Length(parts) = 0 then
    Exit;

  // Look at all but the last part for modifiers; leave the last part as the key name
  for i := 0 to High(parts) - 1 do
  begin
    t := Trim(parts[i]);
    if SameText(t, 'Ctrl') or SameText(t, 'Control') then
      Include(Result, mdCtrl)
    else if SameText(t, 'Alt') then
      Include(Result, mdAlt)
    else if SameText(t, 'Shift') then
      Include(Result, mdShift)
    else if SameText(t, 'Win') or SameText(t, 'Windows') then
      Include(Result, mdWin);
  end;

  // Rebuild Token as the last segment (the true key name)
  Token := Trim(parts[High(parts)]);
end;

procedure SendChord(const Chord: string);
var
  Token: string;
  mods: TModifiers;
  VK: UINT;
  ext: Boolean;
begin
  Token := Chord; // may contain Ctrl+Shift+X
  mods := ParseModifiers(Token);

  if not KeyNameToVK(Token, VK) then
    raise Exception.CreateFmt('Unknown key: "%s"', [Token]);

  // Press modifiers (down) in a conventional order: Ctrl, Shift, Alt, Win
  if mdCtrl in mods then
    SendInputKey(VK_CONTROL, True, False);
  if mdShift in mods then
    SendInputKey(VK_SHIFT, True, False);
  if mdAlt in mods then
    SendInputKey(VK_MENU, True, False);
  if mdWin in mods then
    SendInputKey(VK_LWIN, True, False); // left Win

  // Press the main key
  ext := IsExtendedVK(VK);
  SendInputKey(VK, True, ext);
  SendInputKey(VK, False, ext);

  // Release modifiers (reverse order)
  if mdWin in mods then
    SendInputKey(VK_LWIN, False, False);
  if mdAlt in mods then
    SendInputKey(VK_MENU, False, False);
  if mdShift in mods then
    SendInputKey(VK_SHIFT, False, False);
  if mdCtrl in mods then
    SendInputKey(VK_CONTROL, False, False);
end;

function ResolveAlias(const Token: string): string;
begin
  if FAliases.IndexOfName(Token) >= 0 then
    Result := FAliases.Values[Token]
  else
    Result := Token;
end;

function IsEditLike(h: HWND): Boolean;
begin
  // Reuse edit-like classes
  Result := IsClassIn(h, EDIT_CLASS_NAMES);
end;

function GetTopLevelWindow(h: HWND): HWND;
begin
  if h = 0 then
    Exit(0);

  // First walk parent chain
  Result := h;
  while GetParent(Result) <> 0 do
    Result := GetParent(Result);

  // Then resolve owner (important for popup / borderless forms)
  if GetWindow(Result, GW_OWNER) <> 0 then
    Result := GetWindow(Result, GW_OWNER);
end;

function SameTextArray(const S: string; const Arr: TArray<string>): Boolean;
begin
  for var i := 0 to High(Arr) do
    if SameText(S, Arr[i]) then
      Exit(True);
  Result := False;
end;

function GetWndClass(h: HWND): string;
var
  Buf: array [0 .. 255] of Char;
  n: Integer;
begin
  n := GetClassName(h, Buf, Length(Buf));
  if n > 0 then
    SetString(Result, Buf, n)
  else
    Result := '';
end;

function GetWndText(h: HWND): string;
var
  len: Integer;
  Buf: array [0 .. 1023] of Char;
begin
  len := GetWindowText(h, Buf, Length(Buf));
  if len > 0 then
    SetString(Result, Buf, len)
  else
    Result := '';
end;

function EnumWinFindProc(HWND: HWND; lParam: lParam): BOOL; stdcall;
var
  ctx: PFindWinCtx;
  cls, txt: string;
begin
  ctx := PFindWinCtx(lParam);
  if ctx^.Found <> 0 then
    Exit(False); // already found

  // Consider only top-level windows
  if GetWindow(HWND, GW_OWNER) = 0 then
  begin
    cls := GetWndClass(HWND);
    txt := GetWndText(HWND);

    // Match by caption OR by class OR any extra class names provided
    if SameText(txt, ctx^.TitleOrClass) or SameText(cls, ctx^.TitleOrClass) or SameTextArray(cls, ctx^.ExtraClasses) then
    begin
      ctx^.Found := HWND;
      Exit(False);
    end;
  end;

  Result := True; // keep enumerating
end;

// ---------- Diagnostics helpers ----------

function DeepChildWindowFromPoint(const PtScreen: TPoint): HWND;
var
  h, child: HWND;
  ptClient: TPoint;
begin
  h := WindowFromPoint(PtScreen);
  if h = 0 then
    Exit(0);

  Result := h;

  while True do
  begin
    ptClient := PtScreen;
    Winapi.Windows.ScreenToClient(h, ptClient);

    child := ChildWindowFromPointEx(h, ptClient, CWP_SKIPINVISIBLE or CWP_SKIPDISABLED or CWP_SKIPTRANSPARENT);

    if (child = 0) or (child = h) then
      Break;

    Result := child;
    h := child;
  end;
end;

function GetWindowTextSafe(h: HWND): string;
var
  Len: Integer;
begin
  Result := '';
  if h = 0 then Exit;

  Len := GetWindowTextLength(h);
  if Len <= 0 then Exit;

  SetLength(Result, Len);
  GetWindowText(h, PChar(Result), Len + 1);
end;

function GetCaptionAtPoint(const pt: TPoint): string;
var
  h: HWND;
  ctrl: TWinControl;
  child: TControl;
  i: Integer;
  localPt: TPoint;
  PropInfo: PPropInfo;
begin
  Result := '';

  h := WindowFromPoint(pt);
  if h = 0 then
    Exit;

  ctrl := FindControl(h);
  if ctrl = nil then
    Exit;

  localPt := ctrl.ScreenToClient(pt);

  for i := 0 to ctrl.ControlCount - 1 do
  begin
    child := ctrl.Controls[i];
    if child.Visible and PtInRect(child.BoundsRect, localPt) then
    begin
      // Try CaptionValue
      PropInfo := GetPropInfo(child, 'CaptionValue');
      if PropInfo <> nil then
        Exit(GetStrProp(child, PropInfo));

      // Fallback: normal Caption
      PropInfo := GetPropInfo(child, 'Caption');
      if PropInfo <> nil then
        Exit(GetStrProp(child, PropInfo));
    end;
  end;
end;

function GetWindowCaptionOrID(h: HWND): string;
var
  Buf: array [0 .. 255] of Char;
  ID: LongInt;
begin
  GetWindowText(h, Buf, Length(Buf));
  Result := Buf;

  if Result = '' then
  begin
    ID := GetWindowLong(h, GWL_ID);
    Result := Format('%d', [ID]);
  end;
end;

function DescribeWindow(h: HWND): string;
  function FirstLine(const S: string): string;
  var
    p: Integer;
  begin
    p := Pos(#13, S);
    if p = 0 then
      p := Pos(#10, S);

    if p > 0 then
      Result := Copy(S, 1, p - 1)
    else
      Result := S;
  end;

var
  cls, txt: array [0 .. 255] of Char;
  sTxt, parentTxt: string;
  ID: LongInt;
  R: TRect;
  ParentH: HWND;
begin
  if h = 0 then
    Exit('No window');

  var pt: TPoint;
  GetCursorPos(pt);

  // Control info
  GetClassName(h, cls, Length(cls));
  ID := GetWindowLong(h, GWL_ID);

  GetWindowText(h, txt, Length(txt));
  sTxt := txt;

  if sTxt = '' then
    sTxt := GetCaptionAtPoint(pt);

  sTxt := FirstLine(sTxt);

  // Parent info
  ParentH := GetParent(h);
  if ParentH <> 0 then
    parentTxt := GetWindowCaptionOrID(ParentH)
  else
    parentTxt := '(none)';

  GetWindowRect(h, R);

  Result := Format
    ('ID=%d Text="%s" Parent="%s" HWND=%p Pos=%s Class=%s Mouse=[%d %d]',
    [ID, sTxt, parentTxt, Pointer(h), RectToStr(R), cls, pt.X, pt.Y]);
end;

function DescribeAtPoint(const PtScreen: TPoint): string;
var
  h: HWND;
  cls, txt: array [0 .. 255] of Char;
  ID: LongInt;
  R: TRect;
begin
  h := DeepChildWindowFromPoint(PtScreen);
  if h = 0 then
    Exit(Format('No window at (%d,%d)', [PtScreen.X, PtScreen.Y]));

  GetClassName(h, cls, Length(cls));
  GetWindowText(h, txt, Length(txt));
  GetWindowRect(h, R);
  ID := GetWindowLong(h, GWL_ID);

  Result := Format('ID=%d Text="%s" HWND=%p Pos=%s Class=%s',
    [ID, txt, Pointer(h), RectToStr(R), cls]);
end;

{ ---- Buttons matching by caption text and custom classes ---- }

function FindDescendantButtonByCaption(Parent: HWND; const Caption: string): HWND;
var
  ctx: TEnumButtonsCtx;
begin
  Result := 0;
  if Parent = 0 then Exit;

  ctx.Parent := Parent;
  ctx.Caption := Caption;
  ctx.Found := 0;

  EnumChildWindows(Parent, @EnumFindButtonByCaptionProc, LPARAM(@ctx));

  Result := ctx.Found;
end;

{ ---- Misc helpers ---- }

function DoCryptXOR(Action, Src: string): string;
var
  KeyLen, KeyPos: Integer;
  offset: Integer;
  dest: string;
  SrcPos, SrcAsc: Integer;
  TmpSrcAsc: Integer;
  Range: Integer;
begin

  if Src = '' then
  begin
    Result := '';
    Exit;
  end;

  var Key := 'PAPA_MIA';
  dest := '';
  KeyLen := Length(Key);
  KeyPos := 0;
  Range := 256;

  if Action = 'E' then //encrypt
  begin
    offset := Range - 101;
    for SrcPos := 1 to Length(Src) do
    begin
      SrcAsc := (Ord(Src[SrcPos]) + offset) mod 255;
      if KeyPos < KeyLen then
        KeyPos := KeyPos + 1
      else
        KeyPos := 1;
      SrcAsc := SrcAsc xor Ord(Key[KeyPos]);
      dest := dest + Format('%1.2x', [SrcAsc]);
      offset := SrcAsc;
    end;
  end;

  if Action = 'D' then //decrypt
  begin
    SrcPos := 1;
    offset := Range - 101;

    repeat
      SrcAsc := StrToInt('$' + Copy(Src, SrcPos, 2));
      if KeyPos < KeyLen then
        KeyPos := KeyPos + 1
      else
        KeyPos := 1;
      TmpSrcAsc := SrcAsc xor Ord(Key[KeyPos]);
      if TmpSrcAsc <= offset then
        TmpSrcAsc := 255 + TmpSrcAsc - offset
      else
        TmpSrcAsc := TmpSrcAsc - offset;
      dest := dest + chr(TmpSrcAsc);
      offset := SrcAsc;
      SrcPos := SrcPos + 2;
    until SrcPos >= Length(Src);
  end;
  Result := dest;
end;

function FindTopWindowByTitleOrClassFlexible(const TitleOrClass: string; const ExtraClasses: TArray<string>): HWND;
var
  ctx: TFindWinCtx;
begin
  // 1) Fast checks (caption / class)
  Result := FindTopWindowByTitleOrClass(TitleOrClass);
  if Result <> 0 then
    Exit;

  // 2) Enumerate all top-level windows and match:
  // - caption == TitleOrClass
  // - class == TitleOrClass
  // - class is in ExtraClasses (e.g., 'TFormPOSOptionsBox', '#32770', etc.)
  ctx.TitleOrClass := TitleOrClass;
  ctx.ExtraClasses := ExtraClasses;
  ctx.Found := 0;

  EnumWindows(@EnumWinFindProc, lParam(@ctx));
  Result := ctx.Found;
end;

function RequireTopWindowFlexible(const TitleOrClass: string): HWND;
begin
  // Default extra classes including the common dialog class and custom one
  Result := FindTopWindowByTitleOrClassFlexible(TitleOrClass, [DIALOG_CLASS, 'TFormPOSOptionsBox']);
  if Result = 0 then
    raise Exception.CreateFmt('Window not found (caption OR class): "%s"',
      [TitleOrClass]);
end;

function NormalizeLabel(const S: string): string;
var
  t: string;
begin
  t := Trim(S);
  if (t <> '') and (t[Length(t)] = ':') then
    Delete(t, Length(t), 1);
  Result := Trim(t);
end;

function FindEditNearLabel(Parent: HWND; const LabelText: string): HWND;
var
  LabelHwnd: HWND;
  TextBuf: array [0 .. 255] of Char;
  LabelRect, EditRect: TRect;
  BestEdit: HWND;
  BestDx: Integer;
  Wanted: string;
begin
  Result := 0;
  BestEdit := 0;
  BestDx := MaxInt;
  Wanted := NormalizeLabel(LabelText);

  LabelHwnd := 0;
  while True do
  begin
    LabelHwnd := FindWindowEx(Parent, LabelHwnd, 'Static', nil);
    if LabelHwnd = 0 then
      Break;

    if GetWindowText(LabelHwnd, TextBuf, Length(TextBuf)) > 0 then
    begin
      if SameText(NormalizeLabel(TextBuf), Wanted) then
      begin
        GetWindowRect(LabelHwnd, LabelRect);

        var Edits := GetAllDescendantEdits(Parent);
        for var E in Edits do
        begin
          GetWindowRect(E, EditRect);

          var sameRow := Abs(((LabelRect.Top + LabelRect.Bottom) div 2) - ((EditRect.Top + EditRect.Bottom) div 2)) < 24;
          var toRight := EditRect.Left >= LabelRect.Left;

          if sameRow and toRight then
          begin
            var dx := EditRect.Left - LabelRect.Right;
            if dx < 0 then
              dx := 0;

            if dx < BestDx then
            begin
              BestDx := dx;
              BestEdit := E;
            end;
          end;
        end;

        if BestEdit <> 0 then
          Exit(BestEdit);
      end;
    end;
  end;
end;

function FindDialogByTitle(const Title: string): HWND;
begin
  Result := FindWindow(PChar(DIALOG_CLASS), PChar(Title));
end;

function RequireDialogFlexible(const TitleOrClass: string): HWND;
var
  h: HWND;
begin
  h := FindDialogByTitle(TitleOrClass);
  if h <> 0 then
    Exit(h);

  h := FindTopWindowByTitleOrClass(TitleOrClass);
  if h <> 0 then
    Exit(h);

  raise Exception.CreateFmt('Window not found (dialog/top/class): "%s"',
    [TitleOrClass]);
end;

function FindDescendantByTextOrClass(Parent: HWND; const Token: string): HWND;
var
  h: HWND;
  clsBuf, txtBuf: array[0..255] of Char;
begin
  Result := 0;
  h := 0;

  while True do
  begin
    h := FindWindowEx(Parent, h, nil, nil);
    if h = 0 then
      Break;

    GetClassName(h, clsBuf, Length(clsBuf));
    GetWindowText(h, txtBuf, Length(txtBuf));

    if SameText(clsBuf, Token) or SameText(txtBuf, Token) then
      Exit(h);

    // recurse
    Result := FindDescendantByTextOrClass(h, Token);
    if Result <> 0 then
      Exit;
  end;
end;

function ResolveRootWindow(const Token: string): HWND;
var
  h, top: HWND;
begin
  //Result := 0;

  // 1) Try dialog / top-level window (existing behavior)
  Result := FindTopWindowByTitleOrClassFlexible(Token, [DIALOG_CLASS]);
  if Result <> 0 then
    Exit;

  // 2) Try control under last known top window
  top := LastTopWindow; // capture this in the inspector
  if top <> 0 then
  begin
    Result := FindDescendantByTextOrClass(top, Token);
    if Result <> 0 then
      Exit;
  end;

  // 3) Try HWND token
  if TryParseHWNDToken(Token, h) then
  begin
    Result := h;
    Exit;
  end;
end;

function GetButtonText(h: HWND): string;
var
  Buf: array[0..255] of Char;
begin
  Result := '';
  if h = 0 then Exit;
  if GetWindowText(h, Buf, Length(Buf)) > 0 then
    Result := Buf;
end;

function GetEditText(h: HWND): string;
var
  Len: Integer;
begin
  Result := '';
  if h = 0 then Exit;

  Len := GetWindowTextLength(h);
  if Len <= 0 then Exit;

  SetLength(Result, Len);
  GetWindowText(h, PChar(Result), Len + 1);
end;

procedure BringWindowToForeground(hWnd: HWND);
var
  ForeThreadID: DWORD;
  ThisThreadID: DWORD;
begin
  if hWnd = 0 then Exit;

  // If minimized, restore first
  if IsIconic(hWnd) then
    ShowWindow(hWnd, SW_RESTORE);

  // If already foreground, nothing to do
  if GetForegroundWindow = hWnd then
    Exit;

  ForeThreadID := GetWindowThreadProcessId(GetForegroundWindow, nil);
  ThisThreadID := GetCurrentThreadId;

  // Temporarily attach threads so focus is allowed
  AttachThreadInput(ThisThreadID, ForeThreadID, True);
  try
    BringWindowToTop(hWnd);
    SetForegroundWindow(hWnd);
    SetFocus(hWnd);
  finally
    AttachThreadInput(ThisThreadID, ForeThreadID, False);
  end;
end;

procedure ClickByMouse(h: HWND);
var
  R: TRect;
  X, Y: Integer;
begin
  if h = 0 then Exit;

  // Bring app to foreground
  BringWindowToForeground(GetTopLevelWindow(h));

  // Get control bounds
  GetWindowRect(h, R);

  // Click the centre of the control
  X := (R.Left + R.Right) div 2;
  Y := (R.Top + R.Bottom) div 2;

  // Move mouse & click
  SetCursorPos(X, Y);

  mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
  mouse_event(MOUSEEVENTF_LEFTUP,   0, 0, 0, 0);
end;

{ =================== Instance helpers =================== }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FScriptFilename := '';
  FAliases := TStringList.Create;
  FAliases.CaseSensitive := False;
  FAliases.StrictDelimiter := True;
  FAliases.Delimiter := '=';

  if ParamCount >= 1 then
  begin
    FScriptFilename := ParamStr(1);

    //Load script then click Run
    if FileExists(FScriptFilename) then
    begin
      mmoScript.Lines.LoadFromFile(FScriptFilename);

      TThread.Queue(nil,
        procedure
        begin
          btnGo.Click;
        end);

    end
    else
      raise Exception.CreateFmt('Script file not found: %s', [FScriptFilename]);
  end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FAliases.Free;
end;

procedure TForm1.CloseWindowByCaption(const WindowTitle: string);
var
  W: HWND;
begin
  W := FindWindow(nil, PChar(WindowTitle));
  if W <> 0 then
    PostMessage(W, WM_CLOSE, 0, 0);
end;

procedure TForm1.EncryptClick(Sender: TObject);
begin
  FEncryptOutput.Text := DoCryptXOR('E', FEncryptInput.Text);
end;

procedure TForm1.Encryption1Click(Sender: TObject);
var
  F: TForm;
  EInput, EOutput: TEdit;
  BEncrypt, BClose: TButton;
begin
  F := TForm.Create(nil);
  try
    F.Caption := 'Encrypt Text';
    F.Position := poScreenCenter;
    F.Width := 500;
    F.Height := 200;

    // Input edit
    EInput := TEdit.Create(F);
    EInput.Parent := F;
    EInput.Left := 16;
    EInput.Top := 16;
    EInput.Width := F.ClientWidth - 32;
    EInput.PasswordChar := '*';
    EInput.Anchors := [akLeft, akTop, akRight];

    // Output edit (read-only)
    EOutput := TEdit.Create(F);
    EOutput.Parent := F;
    EOutput.Left := 16;
    EOutput.Top := 56;
    EOutput.Width := F.ClientWidth - 32;
    EOutput.ReadOnly := True;
    EOutput.Anchors := [akLeft, akTop, akRight];

    // Store references for the event handler
    FEncryptInput := EInput;
    FEncryptOutput := EOutput;

    // Encrypt button
    BEncrypt := TButton.Create(F);
    BEncrypt.Parent := F;
    BEncrypt.Caption := 'Encrypt';
    BEncrypt.Left := 16;
    BEncrypt.Top := 96;
    BEncrypt.OnClick := EncryptClick;

    // Close button
    BClose := TButton.Create(F);
    BClose.Parent := F;
    BClose.Caption := 'Close';
    BClose.Left := 120;
    BClose.Top := 96;
    BClose.ModalResult := mrClose;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure TForm1.tmrInspectorTimer(Sender: TObject);
var
  pt: TPoint;
  h: HWND;
  S: string;
begin
  GetCursorPos(pt);
  h := DeepChildWindowFromPoint(pt);
  S := DescribeWindow(h);

  // Show live info
  Caption := 'Clicker - ' + S;
  // OutputDebugString(PChar('Inspect: ' + S));
end;

procedure TForm1.btnLoadClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Script files (*.script)|*.script|All files (*.*)|*.*';
    dlg.DefaultExt := 'script';
    dlg.Options := [ofFileMustExist, ofPathMustExist];

    if dlg.Execute then
    begin
      mmoScript.PlainText := True;
      mmoScript.Lines.LoadFromFile(dlg.FileName, TEncoding.UTF8);
      FScriptFilename := dlg.FileName;
      Save1.Enabled := True;
    end;
  finally
    dlg.Free;
  end;
end;

procedure TForm1.btnSaveClick(Sender: TObject);
var
  SL: TStringList;
begin
  if FScriptFilename = '' then
    Exit; // should never happen if button is disabled correctly

  // mmoScript.Lines.SaveToFile(FScriptFilename); //this saves as rich (formatted) text
  SL := TStringList.Create;
  try
    SL.Text := mmoScript.Text; // plain text
    SL.SaveToFile(FScriptFilename, TEncoding.UTF8);
    Save1.Enabled := False;
  finally
    SL.Free;
  end;
end;

procedure TForm1.LeftClickAt(ScreenX, ScreenY: Integer);
var
  Inputs: array [0 .. 1] of TInput;
begin

  SetCursorPos(ScreenX, ScreenY);

  ZeroMemory(@Inputs, SizeOf(Inputs));

  Inputs[0].Itype := INPUT_MOUSE;
  Inputs[0].mi.dwFlags := MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_MOVE;
  Inputs[0].mi.dx := MulDiv(ScreenX, 65535, GetSystemMetrics(SM_CXSCREEN) - 1);
  Inputs[0].mi.dy := MulDiv(ScreenY, 65535, GetSystemMetrics(SM_CYSCREEN) - 1);

  Inputs[1].Itype := INPUT_MOUSE;
  Inputs[1].mi.dwFlags := MOUSEEVENTF_LEFTDOWN or MOUSEEVENTF_LEFTUP;

  // pass pointer to first element
  SendInput(Length(Inputs), @Inputs[0], SizeOf(TInput));
end;

procedure TForm1.mmoScriptChange(Sender: TObject);
begin
  // sync mmoLineNumbers so that both have the same number of lines
  mmoLineNumbers.Lines.Clear;

  for var i := 0 to mmoScript.Lines.Count - 1 do
    mmoLineNumbers.Lines.Add(IntToStr(i + 1));

  mmoLineNumbers.ScrollPosition := mmoScript.ScrollPosition;
  if FScriptFilename <> '' then
    Save1.Enabled := True;

  lblStatus.Caption := 'Ready';
end;

procedure TForm1.mmoScriptKeyPress(Sender: TObject; var Key: Char);
begin
  mmoLineNumbers.ScrollPosition := mmoScript.ScrollPosition;
end;

procedure TForm1.Quit1Click(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TForm1.Reference1Click(Sender: TObject);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('Comments:');
    SL.Add('  There are multiple different types of comment. You can start a comment with # or ;');
    SL.Add('  Comments finish when they reach the end of the line');
    SL.Add('');
    SL.Add('Commands:');
    SL.Add('  These script commands are all case insensitive. Each line is token based. If a token has spaces, enclose it in "quotes".');
    SL.Add('');
    SL.Add('  ClickButton <dialogName> <buttonValue>');
    SL.Add('    Clicks a button with known text. Use the title bar to get the name and value. For Dialog name, you can also use ID or HWND');
    SL.Add('  ClickElement <windowName> <elementName> or ClickElement <elementName>');
    SL.Add('    Clicks a named element. If you leave out the windowName, it will default to what is in the "Default window name" box e.g. PointOfSale');
    SL.Add('  MouseClick X Y');
    SL.Add('    Left clicks the mouse at the specified coords. Use this as a last resort when ClickButton and ClickElement dont work');
    SL.Add('');
    SL.Add('  SetText <dialogName> <controlName> <value>');
    SL.Add('    Writes some text into an input box. The control name does not need to be the actual name of the control, it can be the label next to the control');
    SL.Add('    If you leave out the dialogName, it will default to what is in the "Default window name" box e.g. PointOfSale');
    SL.Add('    This also sets the focus to controlName, so you can now use `PressKey Enter`');
    SL.Add('  PressKey <keyName>');
    SL.Add('    Presses any key on the keyboard, accepts modifiers e.g. Ctrl+Alt+Del, Alt+F4, etc. Tip: be careful as to which window is active when using this');
    SL.Add('  TypeText <text>');
    SL.Add('    Runs multiple PressKey commands. Put the text inside "quotes" if there are spaces');
    SL.Add('  TypePassword <encryptedText> or TypePassword <form|dialog> <field|control> <encryptedText>');
    SL.Add('    Types in a password using TypeText. Use the Help > Encryption menu to encrypt text. This allows using passwords in script files.');
    SL.Add('    Tip: if using the short form, use MouseClick before this so the mouse can focus on the control');
    SL.Add('  Load <filename>');
    SL.Add('    Opens a script from "C:\Scripts\<filename>.script", this is similar to a procedure e.g. can have a "login" script, then call it');
    SL.Add('');
    SL.Add('  SetPause <time>');
    SL.Add('    Sets the default time (in ms) between commands, the default is 100 ms');
    SL.Add('  Sleep <milliseconds>');
    SL.Add('    Pauses execution, default is 1 second. Also see the "Default pause time" at the top of the window');
    SL.Add('  Alias <name> <value>');
    SL.Add('    Allows to set an alias e.g. instead of using a control ID which might change, use an alias then only change it in one place');
    SL.Add('  If <"Button"|"Edit"> <WindowName> <name|id|hwnd> "Expected text"');
    SL.Add('    Similar to an assert function. The script will continue only when the expected text is found. There is no "else" function');
    SL.Add('    If WindowName is omitted, it will default to what is in the default window box');
    SL.Add('  Close <windowName>');
    SL.Add('    Closes a window or dialog');
    SL.Add('  LaneTool');
    SL.Add('    Runs the LaneTool program if it exists. Useful on SCOs to stop NCR full screen application. This is the only exe that can be run, so dont get any ideas');
    SL.Add('  DumpWindow <windowName>');
    SL.Add('    Outputs debug info in a new window, allowing you to copy and paste and use the information in scripts');
    SL.Add('  DumpHere');
    SL.Add('    Outputs debug info under the mouse cursor. Useful if you dont know the window name or if it is borderless');
    SL.Add('    Tip: you can use the Sleep command to pause, then move the mouse into position');
    SL.Add('');
    SL.Add('You can also use this in a batch file e.g. `Clicker.exe "C:\Scripts\filename.script"` and it will load and run the filename script');

    ShowTextDialog('Reference', SL.Text, 830, 600, true);
  finally
    SL.Free;
  end;
end;

function TForm1.SetEditText(Edit: HWND; const Value: string): Boolean;
var
  Top: HWND;
begin
  Result := False;
  if Edit = 0 then Exit;

  // 1) Resolve top-level window
  Top := GetTopLevelWindow(Edit);
  if Top = 0 then Exit;

  // 2) Bring target app to foreground
  BringWindowToForeground(Top);
  SetActiveWindow(Top);

  // 3) Ensure focus chain is valid
  Winapi.Windows.SetFocus(Edit);
  LastTopWindow := Top;

  // 4) Set text
  SendMessage(Edit, WM_SETTEXT, 0, LPARAM(PChar(Value)));

  Result := True;
end;

procedure TForm1.RunScriptLines(Lines: TStrings; const SourceName: string);
var
  lineNumber: Integer;
  Line: string;
  parts: TArray<string>;
begin
  for lineNumber := 0 to Lines.Count - 1 do
  begin
    Line := Trim(Lines[lineNumber]);
    if Line = '' then
      Continue;

    parts := Tokenize(Line);
    if Length(parts) = 0 then
      Continue;

    lblStatus.Caption :=
      Format('Running %s:%d → %s',
        [SourceName, lineNumber + 1, Line]);

    Application.ProcessMessages;

    // ---- COMMAND DISPATCH ----
    mmoLineNumbers.Lines[lineNumber] :=
      Format('%s %d', [RUNNING, lineNumber + 1]);

    if ExecuteCommand(parts, lineNumber, SourceName) then
      mmoLineNumbers.Lines[lineNumber] :=
        Format('%s %d', [COMPLETED, lineNumber + 1])
    else
    begin
      mmoLineNumbers.Lines[lineNumber] :=
        Format('%s %d', [ERROR, lineNumber + 1]);
      lblStatus.Caption := 'Completed with error';
      Application.ProcessMessages;
      ShowTextDialog('Error', Format('Error on line %d. Command in %s failed.' + CRLF + '%s',
        [lineNumber, SourceName, Line]));
      Exit;
    end;

    Sleep(StrToIntDef(edtPauseTime.Text, 100));
  end;

  lblStatus.Caption := 'Completed all tasks';
end;

function ResolveEditHandle(W: HWND; const Token: string): HWND;
var
  Edits: TArray<HWND>;
  Index, CtrlId: Integer;
  h: HWND;
begin
  // Result := 0;

  // --- 1) HWND:... or hex handle ---
  if TryParseHWNDToken(Token, h) then
  begin
    if (h <> 0) and IsEditLike(h) then
      Exit(h)
    else
      Exit(0);
  end;

  // --- 2) ID:... or decimal control ID ---
  if TryParseControlIdToken(Token, CtrlId) then
  begin
    Result := FindDescendantByControlId(W, CtrlId);
    if (Result <> 0) and IsEditLike(Result) then
      Exit
    else
      Exit(0);
  end;

  // --- 3) Friendly names -> first/second edit ---
  if SameText(Token, 'Name') or SameText(Token, 'EditName') then
    Index := 1
  else if SameText(Token, 'Password') or SameText(Token, 'EditPassword') then
    Index := 2
  else if TryStrToInt(Token, Index) then
    Index := Index // 1-based index
  else
    Index := -1;

  if Index > 0 then
  begin
    Edits := GetAllDescendantEdits(W);
    if (Index >= 1) and (Index <= Length(Edits)) then
      Exit(Edits[Index - 1])
    else
      Exit(0);
  end;

  // --- 4) Last resort: near label heuristic ---
  Result := FindEditNearLabel(W, Token);
end;

procedure ExpandLoadCommands(Lines: TStringList);
var
  i: Integer;
  Parts: TArray<string>;
  LoadFile: string;
  InsertLines: TStringList;
begin
  i := 0;
  while i < Lines.Count do
  begin
    Parts := Tokenize(Lines[i]);

    if (Length(Parts) >= 2) and SameText(Parts[0], 'Load') then
    begin
      LoadFile := Parts[1];

      if not LoadFile.Contains('\') then
        LoadFile := Format('C:\Scripts\%s.script', [LoadFile]);

      if not FileExists(LoadFile) then
        raise Exception.CreateFmt(
          'Load failed on line %d: %s not found',
          [i + 1, LoadFile]
        );

      InsertLines := TStringList.Create;
      try
        InsertLines.LoadFromFile(LoadFile, TEncoding.UTF8);

        // Remove the "Load xxx" line
        Lines.Delete(i);

        // Insert loaded file contents at the same position
        for var j := 0 to InsertLines.Count - 1 do
          Lines.Insert(i + j, InsertLines[j]);

        // IMPORTANT: do NOT increment i here
        // Newly inserted lines must also be scanned for Load
        Continue;
      finally
        InsertLines.Free;
      end;
    end;

    Inc(i);
  end;
end;

procedure TForm1.ClickElementInternal(const WindowName: string; var Token: string);
var
  Root, Ctrl: HWND;
  ClassName: array[0..255] of Char;
begin
  Token := ResolveAlias(Token);
  Root := RequireDialogFlexible(WindowName);

  Ctrl := ResolveControl(
    Root,
    Token,
    BUTTON_CLASS_NAMES
  );

  GetClassName(Ctrl, ClassName, Length(ClassName));

  if SameText(ClassName, 'Button') or SameText(ClassName, 'TButton') then
  begin
    // Standard Windows buttons
    SendMessage(Ctrl, BM_CLICK, 0, 0);
  end
  else
  begin
    // Touch buttons, custom controls, etc.
    ClickByMouse(Ctrl);
  end;
end;

function TForm1.ExecuteCommand(const parts: TArray<string>; lineNumber: Integer; const SourceName: string): Boolean;
var
  ScriptName, ScriptPath: string;
  bOK: Boolean;
begin

  bOK := False;
  Result := bOK;

  if SameText(parts[0], 'DumpWindow') then
  begin
    // DumpWindow <WindowCaptionOrClass>
    IDs := [];

    if Length(parts) = 1 then
      if (ShowEditsOrChildrenFor(defaultWindowName.Text, 'DumpWindow')) then
        bOK := True
    else if Length(parts) = 2 then
      if (ShowEditsOrChildrenFor(ResolveAlias(parts[1]), 'DumpWindow')) then
        bOK := True
    else
      raise Exception.CreateFmt
        ('Error on line %d. DumpWindow usage: DumpWindow <windowCaptionOrClass>',
        [lineNumber + 1]);
  end

  else if SameText(parts[0], 'ClickButton') then
  begin
    // ClickButton <Caption|ButtonOK>
    // ClickButton <WindowCaptionOrClass> <Caption|ButtonOK>
    if Length(parts) = 2 then
    begin
      var W := RequireDialogFlexible(defaultWindowName.Text);
      var Token := ResolveAlias(parts[1]);
      var Btn := ResolveControl(W, Token, BUTTON_CLASS_NAMES);

      if Btn = 0 then
      begin
        ShowTextDialog('Error',
          Format('Error on line %d. Button "%s" not found in "%s".' + CRLF + CRLF + '%s',
          [lineNumber + 1, Token, defaultWindowName.Text, FormatButtonsSummary(W)]), 500, 200);
      end
      else
      begin
        ClickByMouse(Btn);
        bOK := True;
      end;
    end
    else if Length(parts) = 3 then
    begin
      var W := RequireDialogFlexible(ResolveAlias(parts[1]));
      var Token := ResolveAlias(parts[2]);
      var Btn := ResolveControl(W, Token, BUTTON_CLASS_NAMES);

      if Btn = 0 then
      begin
        ShowTextDialog('Error',
          Format('Error on line %d. Button "%s" not found in "%s".' + CRLF + CRLF + '%s',
          [lineNumber + 1, Token, defaultWindowName.Text, FormatButtonsSummary(W)]), 500, 200);
      end
      else
      begin
        ClickByMouse(Btn);
        bOK := True;
      end;
    end
    else
      raise Exception.CreateFmt
        ('Error on line %d. ClickButton usage: ClickButton <caption|name>  OR  ClickButton <window> <caption|name>',
        [lineNumber + 1]);
  end

  else if SameText(parts[0], 'ClickElement') then
  begin
    var WindowName, Token: string;

    if Length(parts) = 2 then
    begin
      // ClickElement <token>
      WindowName := defaultWindowName.Text;
      Token := ResolveAlias(parts[1]);
    end
    else if Length(parts) = 3 then
    begin
      // ClickElement <windowName> <token>
      WindowName := ResolveAlias(parts[1]);
      Token := ResolveAlias(parts[2]);
    end
    else
      raise Exception.CreateFmt(
        'ClickElement usage: ClickElement <token> OR ClickElement "Window Name" <token> (line %d)',
        [lineNumber + 1]);

    ClickElementInternal(WindowName, Token);
    bOK := True;
  end


  else if SameText(parts[0], 'MouseClick') then
  begin
    if Length(parts) <> 3 then
      raise Exception.CreateFmt
        ('Error on line %d. MouseClick usage: MouseClick <x> <y>',
        [lineNumber + 1]);

    LeftClickAt(StrToInt(parts[1]), StrToInt(parts[2]));
    bOK := True;
  end

  else if SameText(parts[0], 'SetText') then
  begin
    // Supported:
    // 1) SetText <Name|Index|ID:nnn|HWND:hex> <text>         (uses Default window name)
    // 2) SetText <Window> <Name|Index|ID:nnn|HWND:hex> <text>

    if Length(parts) < 3 then
      raise Exception.CreateFmt('Error on line %d. SetText usage:' + CRLF +
        '  SetText <Name|Index|ID:nnn|HWND:hex> <text>' + CRLF + '  SetText <window> <Name|Index|ID:nnn|HWND:hex> <text>',
        [lineNumber + 1]);

    if Length(parts) = 3 then
    begin
      // -------- Default window form --------
      // SetText <field> <text>

      var RootWnd := ResolveRootWindow(defaultWindowName.Text);
      if RootWnd = 0 then
        raise Exception.CreateFmt(
          'Error on line %d. Root "%s" not found.',
          [lineNumber + 1, defaultWindowName.Text]
        );

      var EditWnd := ResolveEditHandle(RootWnd, ResolveAlias(parts[1]));
      if EditWnd = 0 then
        raise Exception.CreateFmt(
          'Error on line %d. No Edit matched "%s" under "%s".',
          [lineNumber + 1, ResolveAlias(parts[1]), defaultWindowName.Text]
        );

      SetEditText(EditWnd, ResolveAlias(parts[2]));
      Exit(True);
    end
    else // Length(Parts) >= 4
    begin
      // -------- Explicit window form --------
      // SetText <window> <field> <text...>

      var RootWnd := ResolveRootWindow(ResolveAlias(parts[1]));
      if RootWnd = 0 then
        raise Exception.CreateFmt(
          'Error on line %d. Root "%s" not found.',
          [lineNumber + 1, parts[1]]
        );

      var EditWnd := ResolveEditHandle(RootWnd, ResolveAlias(parts[2]));
      if EditWnd = 0 then
        raise Exception.CreateFmt(
          'Error on line %d. No Edit matched "%s" under "%s".',
          [lineNumber + 1, ResolveAlias(parts[2]), parts[1]]
        );

      SetEditText(EditWnd, parts[3]);
      Exit(True);

    end;
  end

  else if SameText(parts[0], 'Close') then
  begin
    if Length(parts) <> 2 then
      raise Exception.CreateFmt
        ('Error on line %d. Close usage: Close <window name>',
        [lineNumber + 1]);

    CloseWindowByCaption(ResolveAlias(parts[1]));
    bOK := True;
  end

  else if SameText(parts[0], 'TypeText') then
  begin
    if Length(parts) <> 2 then
      raise Exception.CreateFmt
        ('Error on line %d. TypeText usage: TypeText "some text"',
        [lineNumber + 1]);

    TypeText(parts[1]);
    bOK := True;
  end

  else if SameText(parts[0], 'TypePassword') then
  begin
    if ((Length(parts) <> 2) and (Length(parts) <> 4)) then
      raise Exception.CreateFmt
        ('Error on line %d. TypePassword usage: TypePassword "some encrypted text" | TypePassword "form|dialog" "control" "some encrypted text"',
        [lineNumber + 1]);

    if length(parts) = 2 then
    begin
      TypeText(DoCryptXOR('D', parts[1]));
      bOK := True;
    end
    else if length(parts) = 4 then
    begin
      var WindowToken := ResolveAlias(parts[1]);
      var FieldToken := ResolveAlias(parts[2]);
      var W := RequireTopWindowFlexible(WindowToken);
      var E := ResolveEditHandle(W, FieldToken);

      if E = 0 then
      begin
        ShowTextDialog('Error',
          Format('Error on line %d. No Edit control matched "%s" in dialog "%s".' + CRLF + CRLF + '%s',
          [lineNumber + 1, FieldToken, WindowToken, FormatEditsSummary(W)]), 500, 200);
      end
      else
      begin
        // rebuild text from tail (preserve spaces)
        var Line := String.Join(' ', Parts);
        var ArgStart := Pos(FieldToken, Line) + Length(FieldToken) + 1;
        var Value := Trim(Copy(Line, ArgStart, MaxInt));

        if SetEditText(E, DoCryptXOR('D', parts[3])) then
          bOK := True;
      end;
    end;
  end

  else if SameText(parts[0], 'PressKey') then
  begin
    // PressKey <key-or-chord>
    // Examples:
    // PressKey A
    // PressKey 7
    // PressKey F5
    // PressKey Ctrl+Alt+F4
    // PressKey Shift+Tab
    // PressKey "Ctrl+Shift+ ="
    if Length(parts) <> 2 then
      raise Exception.CreateFmt
        ('Error on line %d. PressKey usage: PressKey <key-or-chord>. e.g. PressKey A, PressKey Ctrl+Alt+F4, etc',
        [lineNumber + 1]);

    try
      SendChord(parts[1]);
      bOK := True;
    except
      on E: Exception do
        raise Exception.CreateFmt('Error on line %d. PressKey failed: %s',
          [lineNumber + 1, E.Message]);
    end;
  end

  else if SameText(parts[0], 'DumpHere') then
  begin
    // Finds the deepest child under the cursor and shows full DumpWindow for its root window.
    var pt: TPoint;
    GetCursorPos(pt);

    var child := DeepChildWindowFromPoint(pt);
    if (child = 0) then
    begin
      ShowTextDialog('Error', 'DumpHere: No window under cursor.', 500, 200);
      Exit;
    end;

    var Root := GetAncestor(child, GA_ROOT);
    if Root = 0 then
      Root := child;

    var Msg := Format('Under cursor: %s' + CRLF + CRLF, [DescribeAtPoint(pt)]);
    Msg := Msg + 'Immediate children:' + CRLF + FormatWindowChildren(Root) + CRLF + CRLF +
      'Descendant Edits:' + CRLF + FormatEditsSummary(Root) + CRLF + CRLF +
      'Descendant Buttons:' + CRLF + FormatButtonsSummary(Root);
    ShowTextDialog('Error', Msg);
    bOK := True;
  end

  else if SameText(parts[0], 'SetPause') then
  begin
    if Length(parts) = 2 then
    begin
      edtPauseTime.Text := parts[1];
      Application.ProcessMessages;
    end;

    bOK := True;
  end

  else if SameText(parts[0], 'Sleep') then
  begin
    if Length(parts) <> 2 then
      Sleep(1000)
    else
      Sleep(StrToInt(parts[1]));
    bOK := True;
  end

  else if SameText(parts[0], 'LaneTool') then
  begin
    var FileName := 'C:\Apps\Inca\Bin\LaneTool.exe';
    if FileExists(FileName) then
      ShellExecute(0, 'open', PChar(FileName), nil, nil, SW_SHOWNORMAL)
    else
      ShowTextDialog('Error', Format('File %s was not found.', [FileName]), 500, 200);
  end

  else if SameText(parts[0], 'Load') then
  begin
    if Length(parts) <> 2 then
      raise Exception.CreateFmt('%s:%d Load <scriptName>',
        [SourceName, lineNumber + 1]);

    ScriptName := parts[1];
    ScriptPath := Format('C:\Scripts\%s.script', [ScriptName]);

    RunScriptFile(ScriptPath);  // RECURSION
    Exit;
  end

  else if SameText(parts[0], 'If') then
  begin
    // Usage:
    // If Button <token> "expected"
    // If Edit   <token> "expected"
    // If Button "Window Name" <token> "expected"
    // If Edit   "Window Name" <token> "expected"

    var Kind, WindowName, Token, Expected: string;

    if Length(parts) = 4 then
    begin
      // If Button <token> "expected"
      Kind       := parts[1];
      WindowName := defaultWindowName.Text;
      Token      := ResolveAlias(parts[2]);
      Expected   := parts[3];
    end
    else if Length(parts) = 5 then
    begin
      // If Button "Window Name" <token> "expected"
      Kind       := parts[1];
      WindowName := ResolveAlias(parts[2]);
      Token      := ResolveAlias(parts[3]);
      Expected   := parts[4];
    end
    else
      raise Exception.CreateFmt(
        '%s:%d If usage:' + CRLF +
        '  If <Button|Edit> <token> "expected"' + CRLF +
        '  If <Button|Edit> "Window Name" <token> "expected"',
        [SourceName, lineNumber + 1]);

    var W := RequireDialogFlexible(WindowName);

    if SameText(Kind, 'Button') then
    begin
      var Btn := ResolveControl(W, Token, BUTTON_CLASS_NAMES);
      if Btn = 0 then
        raise Exception.CreateFmt(
          '%s:%d Button "%s" not found in window "%s"',
          [SourceName, lineNumber + 1, Token, WindowName]);

      var Actual := GetWindowTextSafe(Btn);
      if not SameText(Actual, Expected) then
        raise Exception.CreateFmt(
          '%s:%d Button "%s" text mismatch. Expected "%s", got "%s"',
          [SourceName, lineNumber + 1, Token, Expected, Actual]);

      bOK := True;
    end
    else if SameText(Kind, 'Edit') then
    begin
      var Edit := ResolveControl(W, Token, EDIT_CLASS_NAMES);
      if Edit = 0 then
        raise Exception.CreateFmt(
          '%s:%d Edit "%s" not found in window "%s"',
          [SourceName, lineNumber + 1, Token, WindowName]);

      var Actual := GetEditText(Edit);
      if not SameText(Actual, Expected) then
        raise Exception.CreateFmt(
          '%s:%d Edit "%s" text mismatch. Expected "%s", got "%s"',
          [SourceName, lineNumber + 1, Token, Expected, Actual]);

      bOK := True;
    end
    else
      raise Exception.CreateFmt(
        '%s:%d Unknown If target "%s". Use "Button" or "Edit"',
        [SourceName, lineNumber + 1, Kind]);
  end

  else if SameText(parts[0], 'Alias') then
  begin
    // Usage:
    // Alias <name> <value>

    if Length(parts) <> 3 then
      raise Exception.CreateFmt(
        '%s:%d Alias usage: Alias <name> <value>',
        [SourceName, lineNumber + 1]);

    var AliasName := parts[1];
    var AliasValue := parts[2];

    // Prevent accidental overwrite
    if FAliases.IndexOfName(AliasName) >= 0 then
      raise Exception.CreateFmt(
        '%s:%d Alias "%s" already defined',
        [SourceName, lineNumber + 1, AliasName]);

    FAliases.Values[AliasName] := AliasValue;
    bOK := True;
  end

  else
  begin
    raise Exception.CreateFmt('%s:%d Unknown command "%s"',
       [SourceName, lineNumber + 1, parts[0]]);
  end;

  Result := bOK;

end;

procedure TForm1.RunScriptFile(FileName: string);
var
  Lines: TStringList;
begin
  if not FileName.Contains('C:\Scripts') then
    FileName := Format('C:\Scripts\%s.script', [FileName]);

  if not FileExists(FileName) then
    raise Exception.CreateFmt('Script not found: %s', [FileName]);

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName, TEncoding.UTF8);
    RunScriptLines(Lines, FileName);
  finally
    Lines.Free;
  end;
end;

{ =================== Script Runner =================== }

procedure TForm1.btnGoClick(Sender: TObject);
var
  Script: TStringList;
begin
  btnGo.Enabled := False; //stop infinite loop and "PressKey Enter" from clicking this button because it is enabled and active
  FAliases.Clear;
  Script := TStringList.Create;
  try
    Script.Text := mmoScript.Text;

    // Expand all Load commands first
    ExpandLoadCommands(Script);

    // Optional: reflect expansion back into editor
    mmoScript.Text := Script.Text;

    // Now execute
    RunScriptLines(Script, 'MainScript');
  finally
    Script.Free;
    btnGo.Enabled := True;
  end;
end;

end.
