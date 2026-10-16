unit TClicker;

{
  Author:      Shaun (Bill) Henderson
  Company:     Foodstuffs SI
  Created:     April 2026
  Purpose:     GUI automation and window-inspection utility

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
  updates the form title and displays a click-through overlay with a dotted
  outline and control details beside the mouse cursor.

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
  System.Math,
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
  Vcl.StdCtrls, Vcl.Menus, System.ImageList, Vcl.ImgList; // TButton, TEdit, TLabel, etc

type
  TInspectorOverlay = class(TForm)
  private
    FTargetRect: TRect;
    FInfoRect: TRect;
    FInfoLines: TStringList;
    FInfoVisible: Boolean;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure WMMouseActivate(var Message: TWMMouseActivate);
      message WM_MOUSEACTIVATE;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function ContainsInfoAt(const ScreenPos: TPoint): Boolean;
    procedure HideInfo;
    procedure UpdateInspector(const TargetRect: TRect;
      const CursorPos: TPoint; const Lines: TStrings);
  end;

  TForm1 = class(TForm)
    btnGo: TButton;
    btnRecord: TButton;
    defaultWindowName: TEdit;
    lblDefaultWindowName: TLabel;
    grpTop: TGroupBox;
    grpBottom: TGroupBox;
    Timer1: TTimer; // this is for when the mouse hovers over something
    grpMiddle: TGroupBox;
    lblStatus: TLabel;
    chkHoverText: TCheckBox;
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
    ImageList1: TImageList;

    procedure btnGoClick(Sender: TObject);
    procedure btnRecordClick(Sender: TObject);
    procedure chkHoverTextClick(Sender: TObject);
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
    FStopRequested: Boolean;
    FRecording: Boolean;
    FRecordedText: string;
    FEncryptInput: TEdit;
    FEncryptOutput: TEdit;
    FInspectorOverlay: TInspectorOverlay;
    FLastInspectorPos: TPoint;
    FHasInspectorPos: Boolean;

    procedure EncryptClick(Sender: TObject);
    procedure CloseWindowByCaption(const WindowTitle: string);
    procedure MouseClickAt(ScreenX, ScreenY: Integer; const Button: string);
    procedure ScrollMouseAt(ScreenX, ScreenY, Delta: Integer);
    procedure AppendRecordedCommand(const Command: string);
    procedure SetRecording(Value: Boolean);
    procedure RecordKey(VKCode, ScanCode: UINT);
    procedure FlushRecordedText;
    procedure RecordMouseClick(ScreenX, ScreenY: Integer; const Button: string);
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

  TAppCommand = (
    //order is not important
    CmdLoad,
    CmdDumpWindow,
    CmdClickButton,
    CmdClickElement,
    CmdMouseClick,
    CmdMouseWheel,
    CmdSetText,
    CmdClose,
    CmdTypeText,
    CmdTypePassword,
    CmdPressKey,
    CmdDumpHere,
    CmdSetPause,
    CmdSleep,
    CmdLanetool,
    CmdAssert,
    CmdAlias,
    CmdStop
  );

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
  MOUSE_POINT_ALIAS_PREFIX = '#MousePoint:';
  CLSID_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';
  IID_IUIAutomation: TGUID = '{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}';
  IID_IUIAutomationElement: TGUID = '{D22108AA-8AC5-49A5-837B-37BBB3D7591E}';
  IID_IUIAutomationInvokePattern: TGUID = '{FB377FBE-8EA6-46D5-9C73-6499642D3059}';

  CmdColorMap: array [0 .. 11] of record Cmd: string;
  Color: TColor;
  end = ((Cmd: '#'; Color: clGray), (Cmd: 'DumpWindow'; Color: clRed),
    (Cmd: 'DumpHere'; Color: clRed), (Cmd: 'ClickButton'; Color: clGreen),
    (Cmd: 'ClickElement'; Color: clGreen), (Cmd: 'MouseClick'; Color: clGreen),
    (Cmd: 'PressKey'; Color: clBlue), (Cmd: 'SetText'; Color: clBlue),
    (Cmd: 'TypeText'; Color: clBlue), (Cmd: 'Close'; Color: $0000A5FF), // orange-ish
    (Cmd: 'Sleep'; Color: $00FF00FF), // purple
    (Cmd: 'MouseWheel'; Color: clGreen)
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
  ConsoleMode: Boolean = False;
  ConsoleExitCode: Integer = 0;

procedure InitializeConsoleOutput;
procedure WriteConsoleText(const Text: string);

implementation

{$R *.dfm}
{ ===================== Mouse inspector (unit-scope) ===================== }

procedure InitializeConsoleOutput;
begin
  if not AttachConsole(DWORD(-1)) and (GetConsoleWindow = 0) then
    if not AllocConsole then
      RaiseLastOSError;

  if not SetConsoleOutputCP(65001) then
    RaiseLastOSError;
end;

/// <summary>
/// Writes the specified text to the console, handling both console and redirected output.
/// </summary>
/// <param name="Text" type="string">The text to write to the console.</param>
procedure WriteConsoleText(const Text: string);
var
  StdOut: THandle;
  ConsoleModeValue: DWORD;
  CharsWritten, BytesWritten: DWORD;
  Index, ChunkLength: Integer;
  Utf8Text: TBytes;
begin
  StdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if (StdOut = 0) or (StdOut = INVALID_HANDLE_VALUE) then
    raise Exception.Create('Standard output is not available.');

  if GetConsoleMode(StdOut, ConsoleModeValue) then
  begin
    Index := 1;
    while Index <= Length(Text) do
    begin
      ChunkLength := Min(Length(Text) - Index + 1, 32768);
      if not WriteConsoleW(StdOut, @Text[Index], ChunkLength, CharsWritten, nil) then
        RaiseLastOSError;
      if CharsWritten = 0 then
        raise Exception.Create('Could not write to the console.');
      Inc(Index, CharsWritten);
    end;
  end
  else
  begin
    Utf8Text := TEncoding.UTF8.GetBytes(Text);
    Index := 0;
    while Index < Length(Utf8Text) do
    begin
      ChunkLength := Min(Length(Utf8Text) - Index, 32768);
      if not WriteFile(StdOut, Utf8Text[Index], ChunkLength, BytesWritten, nil) then
        RaiseLastOSError;
      if BytesWritten = 0 then
        raise Exception.Create('Could not write to standard output.');
      Inc(Index, BytesWritten);
    end;
  end;
end;

type
  PMacroKeyboardHookInfo = ^TMacroKeyboardHookInfo;
  TMacroKeyboardHookInfo = record
    vkCode: DWORD;
    scanCode: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: ULONG_PTR;
  end;

  PMacroMouseHookInfo = ^TMacroMouseHookInfo;
  TMacroMouseHookInfo = record
    pt: TPoint;
    mouseData: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: ULONG_PTR;
  end;

const
  LLKHF_INJECTED_FLAG = $00000010;
  LLMHF_INJECTED_FLAG = $00000001;

var
  GMouseHook: HHOOK = 0;
  GLastTick: DWORD = 0;
  GInspectOn: Boolean = False;
  GKeyboardRecordHook: HHOOK = 0;
  GMouseRecordHook: HHOOK = 0;
  GRecorderForm: TForm1 = nil;
  GRecordedKeys: array[0..255] of Boolean;

function LowLevelKeyboardRecordProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; forward;
function LowLevelMouseRecordProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; forward;
function DeepChildWindowFromPoint(const PtScreen: TPoint): HWND; forward;
function DescribeAtPoint(const PtScreen: TPoint): string; forward;

/// <summary>
/// Adds quotes around a string and escapes any internal quotes by doubling them.
/// This is for when a token contains spaces or special characters and needs to be treated as a single argument in a script.
/// </summary>
/// <param name="Value" type="string">String value supplied to this routine.</param>
/// <returns>Same input value, but with quotes added and internal quotes escaped.</returns>
function QuoteScriptToken(const Value: string): string;
begin
  Result := '"' + Value.Replace('"', '""') + '"';
end;

/// <summary>
/// Uses the keyboard to type the specified text into the currently focused window, simulating key presses for each character.
/// Reads the current keyboard layout to determine the correct virtual key codes and modifiers for each character.
/// </summary>
/// <param name="nCode" type="Integer">The action that was performed.</param>
/// <param name="wParam" type="WPARAM">Whether the key was pressed or released.</param>
/// <param name="lParam" type="LPARAM">The keyboard hook information.</param>
/// <returns>The result of the operation.</returns>
function LowLevelKeyboardRecordProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  KeyInfo: PMacroKeyboardHookInfo;
  VKCode: UINT;
  IsKeyUp: Boolean;
  ProcessId: DWORD;
begin
  if (nCode = HC_ACTION) and (GRecorderForm <> nil) and
    GRecorderForm.FRecording and
    ((wParam = WM_KEYDOWN) or (wParam = WM_SYSKEYDOWN) or
     (wParam = WM_KEYUP) or (wParam = WM_SYSKEYUP)) then
  begin
    KeyInfo := PMacroKeyboardHookInfo(lParam);
    VKCode := KeyInfo.vkCode;
    IsKeyUp := (wParam = WM_KEYUP) or (wParam = WM_SYSKEYUP);

    if IsKeyUp then
      GRecordedKeys[VKCode] := False
    else if (KeyInfo.flags and LLKHF_INJECTED_FLAG) = 0 then
    begin
      GetWindowThreadProcessId(GetForegroundWindow(), ProcessId);
      if (ProcessId <> GetCurrentProcessId()) and not GRecordedKeys[VKCode] then
        GRecorderForm.RecordKey(VKCode, KeyInfo.scanCode);
      GRecordedKeys[VKCode] := True;
    end;
  end;

  Result := CallNextHookEx(GKeyboardRecordHook, nCode, wParam, lParam);
end;

{ =================== TInspectorOverlay =================== }

/// <summary>
/// Uses the mouse to click at the specified screen coordinates, simulating a mouse click event.
/// Reads the current mouse state to determine which button was pressed and whether it was a click or release.
/// </summary>
/// <param name="nCode" type="Integer">The action that was performed.</param>
/// <param name="wParam" type="WPARAM">Whether the mouse button was pressed or released.</param>
/// <param name="lParam" type="LPARAM">The mouse hook information.</param>
/// <returns>The result of the operation.</returns>
function LowLevelMouseRecordProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  MouseInfo: PMacroMouseHookInfo;
  WindowHandle: HWND;
  ProcessId: DWORD;
  WheelDelta: SmallInt;
  Button: string;
begin
  if (nCode = HC_ACTION) and (GRecorderForm <> nil) and
    GRecorderForm.FRecording then
  begin
    MouseInfo := PMacroMouseHookInfo(lParam);
    if (MouseInfo.flags and LLMHF_INJECTED_FLAG) = 0 then
    begin
      Button := ''; //keep blank, may be a scroll
      if wParam = WM_LBUTTONDOWN then
        Button := 'Left'
      else if wParam = WM_RBUTTONDOWN then
        Button := 'Right'
      else if wParam = WM_MBUTTONDOWN then
        Button := 'Middle';

      if Button <> '' then
      begin
        WindowHandle := WindowFromPoint(MouseInfo.pt);
        GetWindowThreadProcessId(WindowHandle, ProcessId);

        if ProcessId <> GetCurrentProcessId() then
        begin
          GRecorderForm.FlushRecordedText;
          GRecorderForm.RecordMouseClick(MouseInfo.pt.X, MouseInfo.pt.Y,
            Button);
        end;
      end
      else if wParam = WM_MOUSEWHEEL then
      begin
        WindowHandle := WindowFromPoint(MouseInfo.pt);
        GetWindowThreadProcessId(WindowHandle, ProcessId);
        WheelDelta := SmallInt((MouseInfo.mouseData shr 16) and $FFFF);

        if ProcessId <> GetCurrentProcessId() then
        begin
          GRecorderForm.FlushRecordedText;
          GRecorderForm.AppendRecordedCommand(Format('MouseWheel %d %d %d',
            [MouseInfo.pt.X, MouseInfo.pt.Y, WheelDelta]));
        end;
      end;
    end;
  end;

  Result := CallNextHookEx(GMouseRecordHook, nCode, wParam, lParam);
end;

/// <summary>
/// Creates a new instance of the TInspectorOverlay form, which is a transparent overlay used to display information about UI elements under the mouse cursor.
/// The overlay is configured to be borderless, stay on top of other windows, and use a specific font for displaying text.
/// </summary>
/// <param name="AOwner" type="TComponent">The parent component.</param>
constructor TInspectorOverlay.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FInfoLines := TStringList.Create;
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  Position := poDesigned;
  Color := clFuchsia;
  TransparentColor := True;
  TransparentColorValue := clFuchsia;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
end;

/// <summary>
/// Destroys the TInspectorOverlay instance, freeing any allocated resources such as the FInfoLines string list.
/// </summary>
destructor TInspectorOverlay.Destroy;
begin
  FInfoLines.Free;
  inherited;
end;

/// <summary>
/// Creates the window parameters for the TInspectorOverlay form, setting it to be transparent, a tool window, and not to activate when shown.
/// This allows the overlay to display information without interfering with user interaction with other windows.
/// </summary>
/// <param name="Params" type="TCreateParams">The parameters for the window creation.</param>
procedure TInspectorOverlay.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.ExStyle := Params.ExStyle or WS_EX_TRANSPARENT or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
end;

/// <summary>
/// Activates the TInspectorOverlay form in response to a mouse activation message,
/// ensuring that it does not take focus away from other windows when the user interacts with it.
/// </summary>
/// <param name="Message" type="TWMMouseActivate">The mouse activation message.</param>
procedure TInspectorOverlay.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

/// <summary>
/// Checks whether the specified screen position is within the bounds of the information rectangle displayed by the TInspectorOverlay.
/// </summary>
/// <param name="ScreenPos" type="TPoint">The screen position to check.</param>
/// <returns>True if the position is within the information rectangle; otherwise, False.</returns>
function TInspectorOverlay.ContainsInfoAt(const ScreenPos: TPoint): Boolean;
var
  ScreenInfoRect: TRect;
begin
  ScreenInfoRect := FInfoRect;
  OffsetRect(ScreenInfoRect, Left, Top);
  Result := PtInRect(ScreenInfoRect, ScreenPos);
end;

/// <summary>
/// Hides the information displayed by the TInspectorOverlay.
/// </summary>
procedure TInspectorOverlay.HideInfo;
begin
  if FInfoVisible then
  begin
    FInfoVisible := False;
    Invalidate;
  end;
end;

/// <summary>
/// Refreshes the display of the TInspectorOverlay, drawing a fuchsia background,
/// a dotted red rectangle around the target area, and any informational text lines.
/// </summary>
procedure TInspectorOverlay.Paint;
var
  I, TextY, XOffset, YOffset: Integer;
  LocalTarget: TRect;
begin
  Canvas.Brush.Color := clFuchsia;
  Canvas.FillRect(ClientRect);

  if (FTargetRect.Right > FTargetRect.Left) and
    (FTargetRect.Bottom > FTargetRect.Top) then
  begin
    LocalTarget := FTargetRect;
    OffsetRect(LocalTarget, -Left, -Top);
    Canvas.Pen.Color := clRed;
    Canvas.Pen.Style := psDot;
    Canvas.Pen.Width := 2;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(LocalTarget);
  end;

  if FInfoVisible then
  begin
    TextY := FInfoRect.Top + 3;
    Canvas.Font.Color := clBlack;
    for I := 0 to FInfoLines.Count - 1 do
    begin
      for YOffset := -1 to 1 do
        for XOffset := -1 to 1 do
          if (XOffset <> 0) or (YOffset <> 0) then
            Canvas.TextOut(FInfoRect.Left + 4 + XOffset,
              TextY + YOffset, FInfoLines[I]);

      Canvas.Font.Color := clWhite;
      Canvas.TextOut(FInfoRect.Left + 4, TextY, FInfoLines[I]);
      Canvas.Font.Color := clBlack;
      Inc(TextY, 18);
    end;
  end;
end;

/// <summary>
/// Updates the TInspectorOverlay with new target rectangle, cursor position, and informational lines.
/// </summary>
/// <param name="TargetRect" type="TRect">The new target rectangle.</param>
/// <param name="CursorPos" type="TPoint">The new cursor position.</param>
/// <param name="Lines" type="TStrings">The new informational lines.</param>
procedure TInspectorOverlay.UpdateInspector(const TargetRect: TRect; const CursorPos: TPoint; const Lines: TStrings);
var
  I, InfoWidth, InfoHeight, InfoLeft, InfoTop: Integer;
  VirtualLeft, VirtualTop, VirtualRight, VirtualBottom: Integer;
  Bounds: TRect;
begin
  FInfoLines.Assign(Lines);
  FTargetRect := TargetRect;
  FInfoVisible := True;

  Canvas.Font.Assign(Font);
  InfoWidth := 0;
  for I := 0 to FInfoLines.Count - 1 do
    InfoWidth := Max(InfoWidth, Canvas.TextWidth(FInfoLines[I]));

  InfoWidth := Min(InfoWidth + 12, 500);
  InfoHeight := FInfoLines.Count * 18 + 8;

  VirtualLeft := GetSystemMetrics(SM_XVIRTUALSCREEN);
  VirtualTop := GetSystemMetrics(SM_YVIRTUALSCREEN);
  VirtualRight := VirtualLeft + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  VirtualBottom := VirtualTop + GetSystemMetrics(SM_CYVIRTUALSCREEN);
  InfoLeft := CursorPos.X + 20;
  InfoTop := CursorPos.Y + 20;

  if InfoLeft + InfoWidth > VirtualRight then
    InfoLeft := VirtualRight - InfoWidth;

  if InfoTop + InfoHeight > VirtualBottom then
    InfoTop := VirtualBottom - InfoHeight;

  InfoLeft := Max(InfoLeft, VirtualLeft);
  InfoTop := Max(InfoTop, VirtualTop);

  Bounds := TargetRect;
  if (Bounds.Right <= Bounds.Left) or (Bounds.Bottom <= Bounds.Top) then
    Bounds := Rect(InfoLeft, InfoTop, InfoLeft + InfoWidth,
      InfoTop + InfoHeight)
  else
  begin
    Bounds.Left := Min(Bounds.Left, InfoLeft);
    Bounds.Top := Min(Bounds.Top, InfoTop);
    Bounds.Right := Max(Bounds.Right, InfoLeft + InfoWidth);
    Bounds.Bottom := Max(Bounds.Bottom, InfoTop + InfoHeight);
  end;

  SetBounds(Bounds.Left, Bounds.Top, Max(1, Bounds.Right - Bounds.Left), Max(1, Bounds.Bottom - Bounds.Top));
  FInfoRect := Rect(InfoLeft - Left, InfoTop - Top, InfoLeft - Left + InfoWidth, InfoTop - Top + InfoHeight);
  SetWindowPos(Handle, HWND_TOPMOST, Left, Top, Width, Height, SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
end;

{ =================== Unit-scope helpers =================== }
/// <summary>
/// Finds the top-level window with the specified title or class name.
/// </summary>
/// <param name="TitleOrClass" type="string">The title or class name to search for.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
function FindTopWindowByTitleOrClass(const TitleOrClass: string): HWND;
begin
  // Try caption first
  Result := FindWindow(nil, PChar(TitleOrClass));
  if Result <> 0 then
    Exit;

  // Try as exact class name
  Result := FindWindow(PChar(TitleOrClass), nil);
end;

/// <summary>
/// Displays a modal dialog box with the specified title and text.
/// </summary>
/// <param name="Title" type="string">The title of the dialog box.</param>
/// <param name="Text" type="string">The text to display in the dialog box.</param>
/// <param name="Width" type="Integer">The width of the dialog box, default is 800.</param>
/// <param name="Height" type="Integer">The height of the dialog box, default is 600.</param>
/// <param name="ShowScrollbars" type="Boolean">Indicates whether to show scrollbars in the text area, default is True.</param>
procedure ShowTextDialog(const Title, Text: string; Width: Integer = 800; Height: Integer = 600; ShowScrollbars: Boolean = True);
var
  F: TForm;
  M: TMemo;
  B: TButton;
  OutputText: string;
begin
  if ConsoleMode then
  begin
    OutputText := Text;
    if OutputText = '' then
      OutputText := sLineBreak
    else if OutputText[Length(OutputText)] <> #10 then
      OutputText := OutputText + sLineBreak;
    WriteConsoleText(OutputText);
    Exit;
  end;

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

/// <summary>
/// Converts a rectangle to a string representation.
/// </summary>
/// <param name="R" type="TRect">The rectangle to convert.</param>
/// <returns>The string representation of the rectangle.</returns>
function RectToStr(const R: TRect): string;
begin
  Result := Format(
    '[%d %d]',
    [Round((R.Left + R.Right) / 2), Round((R.Top + R.Bottom) / 2)]);
end;

/// <summary>
/// Formats the children of a window into a string representation.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <returns>A string containing information about the child windows.</returns>
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

        S.AppendLine(Format(
          'Child ID=%d Text="%s" HWND=%p Pos=%s Class=%s',
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

/// <summary>
/// Checks if the class name of a window matches any of the specified class names.
/// </summary>
/// <param name="AWnd" type="HWND">The window handle to check.</param>
/// <param name="ClassNames" type="array of PChar">The array of class names to compare against.</param>
/// <returns>True if the window's class name matches any of the specified names; otherwise, False.</returns>
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

/// <summary>
/// Enumerates child windows of a given parent window, collecting those that match "edit-like" classes into a list.
/// </summary>
/// <param name="HWND" type="HWND">The child window handle.</param>
/// <param name="lParam" type="lParam">The context information.</param>
/// <returns>True to continue enumeration; otherwise, False.</returns>
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

/// <summary>
/// Enumerates all descendant windows of a given parent window, collecting those that match "edit-like" classes into an array.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <returns>An array of handles to the matching descendant windows.</returns>
function GetAllDescendantEdits(Parent: HWND): TArray<HWND>;
var
  ctx: TEnumEditsCtx;
begin
  SetLength(ctx.List, 0);
  ctx.Parent := Parent;
  EnumChildWindows(Parent, @EnumChildProc, lParam(@ctx));
  Result := ctx.List;
end;

/// <summary>
/// Retrieves the text of a control.
/// </summary>
/// <param name="h" type="HWND">The handle of the control.</param>
/// <returns>The text of the control.</returns>
function GetControlWindowText(h: HWND): string;
var
  Txt: array[0..1023] of Char;
  TextLength: Integer;
  MessageResult: DWORD_PTR;
begin
  Result := '';
  if h = 0 then
    Exit;

  TextLength := GetWindowText(h, Txt, Length(Txt));
  if TextLength = 0 then
  begin
    ZeroMemory(@Txt, SizeOf(Txt));
    MessageResult := 0;
    if SendMessageTimeout(h, WM_GETTEXT, Length(Txt), LPARAM(@Txt[0]), SMTO_ABORTIFHUNG, 200, @MessageResult) = 0 then
      Exit;

    TextLength := Integer(MessageResult);
  end;

  if TextLength > 0 then
    SetString(Result, Txt, Min(TextLength, Length(Txt) - 1));
end;

/// <summary>
/// Retrieves the class name of a window.
/// </summary>
/// <param name="HWND" type="HWND">The window handle.</param>
/// <returns>The class name of the window.</returns>
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

/// <summary>
/// Formats a summary of all descendant edit controls.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <returns>A string containing the summary of the edit controls.</returns>
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
        S.AppendLine(Format(
          '#%d ID=%d HWND=%p Class=%s Text="%s" Rect=%s',
          [j, ID, Pointer(Edits[i]), cls, t, RectToStr(R)]));
      end;
    end;

    Result := S.ToString;
  finally
    S.Free;
  end;
end;

/// <summary>
/// Formats a summary of all descendant button-like controls.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <returns>A string containing the summary of the button controls.</returns>
function FormatButtonsSummary(Parent: HWND): string;
var
  Btns: TArray<HWND>;
  S: TStringBuilder;
  R: TRect;
  t: string;
  cls: string;
  ID, j: Integer;

  function GetAllDescendantButtons(Parent: HWND): TArray<HWND>;
  var
    ctx: TEnumListCtx;

  function EnumCollectButtonsProc(HWND: HWND; lParam: lParam): BOOL; stdcall;
  var
    ctx: PEnumListCtx;
  begin
    ctx := PEnumListCtx(lParam);

    if IsClassIn(HWND, BUTTON_CLASS_NAMES) or (GetControlWindowText(HWND) <> '') then
    begin
      SetLength(ctx^.List, Length(ctx^.List) + 1);
      ctx^.List[High(ctx^.List)] := HWND;
    end;

    Result := True;
  end;

  begin
    SetLength(ctx.List, 0);
    EnumChildWindows(Parent, @EnumCollectButtonsProc, lParam(@ctx));
    Result := ctx.List;
  end;

begin
  S := TStringBuilder.Create;
  try
    Btns := GetAllDescendantButtons(Parent);
    if Length(Btns) = 0 then
      Exit('No descendant Button-like controls found. (Classes checked: Button, TAKPButton, TFSTouchButton)');

    j := 0;
    for var i := 0 to High(Btns) do
    begin
      t := GetControlWindowText(Btns[i]);
      GetWindowRect(Btns[i], R);
      cls := GetWndClassName(Btns[i]);

      ID := GetWindowLong(Btns[i], GWL_ID);

      if not TArray.Contains<Integer>(IDs, ID) then
      begin
        Inc(j);
        IDs := IDs + [ID];

        S.AppendLine(Format(
          '#%d ID=%d HWND=%p Class=%s Text="%s" Rect=%s',
          [j, ID, Pointer(Btns[i]), cls, t, RectToStr(R)]));
      end;
    end;

    Result := S.ToString;
  finally
    S.Free;
  end;
end;

/// <summary>
/// Shows a dialog with information about the immediate children and descendant edit/button controls of a specified window.
/// </summary>
/// <param name="TitleOrClass" type="string">The title or class name of the window to inspect.</param>
/// <param name="ContextMsg" type="string">The context message for the dialog.</param>
/// <returns>True if the window was found and information was displayed; otherwise, False.</returns>
function ShowEditsOrChildrenFor(const TitleOrClass, ContextMsg: string): Boolean;
var
  W: HWND;
  Msg: string;
begin
  Result := False;
  W := FindTopWindowByTitleOrClass(TitleOrClass);
  if W = 0 then
  begin
    ShowTextDialog('Error', Format(
      '%s' + CRLF + 'Window "%s" NOT FOUND (by caption or class).',
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

/// <summary>
/// Splits a string into tokens, respecting quoted substrings and ignoring inline comments.
/// </summary>
/// <param name="S" type="string">The string to tokenize.</param>
/// <returns>An array of tokens.</returns>
function Tokenize(const S: string): TArray<string>;
var
  lineNoComment: string;
  SL: TStringList;

  /// <summary>
/// Strips inline comments from a string. Comment markers inside "quoted text" are ignored,
/// and a valid Assert Color hex value is not treated as a comment.
/// Comments can begin with ';', '#', or '//'.
/// </summary>
/// <param name="S" type="string">String to process</param>
/// <returns>The result of S, with inline comments stripped out.</returns>
function StripInlineComment(const S: string): string;
var
  i: Integer;
  inQuote: Boolean;
  ch: Char;
  IsHexColor: Boolean;
  HexColorConsumed: Boolean;

  function IsAssertColorValuePosition(const Prefix: string): Boolean;
    var
      PrefixTokens: TStringList;
      ScreenX, ScreenY: Integer;
    begin
      PrefixTokens := TStringList.Create;
      try
        PrefixTokens.StrictDelimiter := True;
        PrefixTokens.Delimiter := ' ';
        PrefixTokens.QuoteChar := '"';
        PrefixTokens.DelimitedText := Trim(Prefix);
        for var TokenIndex := PrefixTokens.Count - 1 downto 0 do
          if PrefixTokens[TokenIndex] = '' then
            PrefixTokens.Delete(TokenIndex);

        Result := False;
        if PrefixTokens.Count <> 4 then
          Exit;
        if not SameText(PrefixTokens[0], 'Assert') then
          Exit;
        if not SameText(PrefixTokens[1], 'Color') then
          Exit;

        if not TryStrToInt(PrefixTokens[2], ScreenX) then
          Exit;
        Result := TryStrToInt(PrefixTokens[3], ScreenY);
      finally
        PrefixTokens.Free;
      end;
    end;

  begin
    Result := Trim(S);
    inQuote := False;
    HexColorConsumed := False;
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
      else if (ch = ';') and not inQuote then
      begin
        // comment begins here; truncate
        Result := Trim(Copy(S, 1, i - 1));
        Exit;
      end;
      if (ch = '#') and not inQuote then
      begin
        IsHexColor := not HexColorConsumed and
          IsAssertColorValuePosition(Copy(S, 1, i - 1)) and
          (i + 6 <= Length(S));
        if IsHexColor then
          for var HexIndex := i + 1 to i + 6 do
            if not CharInSet(S[HexIndex], ['0'..'9', 'a'..'f', 'A'..'F']) then
              IsHexColor := False;

        if IsHexColor and
          ((i + 6 = Length(S)) or CharInSet(S[i + 7], [#9, ' '])) then
        begin
          HexColorConsumed := True;
          Inc(i, 7);
          Continue;
        end;

        // A hash not followed by a complete color token starts a comment.
        Result := Trim(Copy(S, 1, i - 1));
        Exit;
      end;

      if (ch = '/') and (i < Length(S)) and (S[i + 1] = '/') and not inQuote then
      begin
        Result := Trim(Copy(S, 1, i - 1));
        Exit;
      end;

      Inc(i);
    end;

    Result := Trim(S);
  end;


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

/// <summary>
/// Simulates a key press or release event for a specified virtual key code, optionally marking it as an extended key.
/// </summary>
/// <param name="VK">The virtual key code.</param>
/// <param name="KeyDown">True to simulate a key press, False to simulate a key release.</param>
/// <param name="Extended">True to mark the key as an extended key.</param>
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

/// <summary>
/// Determines whether a virtual key code represents an extended key.
/// </summary>
/// <param name="VK">The virtual key code.</param>
/// <returns>True if the key is an extended key; otherwise, False.</returns>
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

/// <summary>
/// Types a string of text by simulating key presses for each character, handling shift states as necessary.
/// </summary>
/// <param name="S">The string to type.</param>
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

/// <summary>
/// Finds a child window by its caption, optionally filtering by allowed class names.
/// </summary>
/// <param name="h" type="HWND">The window handle.</param>
/// <param name="lParam" type="LPARAM">The context information.</param>
/// <returns>True to continue enumeration; otherwise, False.</returns>
function EnumFindByCaption(h: HWND; lParam: LPARAM): BOOL; stdcall;
var
  Ctx: PFindCaptionCtx;
  Txt: string;

  /// <summary>
  /// Determines whether a window's class is in a list of allowed classes.
  /// </summary>
  /// <param name="h" type="HWND">The window handle.</param>
  /// <param name="Classes" type="PPointer">An array of allowed class names.</param>
  /// <param name="Count" type="Integer">The number of allowed classes.</param>
  /// <returns>True if the window's class is in the list; otherwise, False.</returns>
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

begin
  Ctx := PFindCaptionCtx(lParam);

  if not ClassAllowed(h, Ctx^.Classes, Ctx^.ClassCount) then
    Exit(True);

  Txt := GetControlWindowText(h);
  if (Txt <> '') and SameText(Txt, Ctx^.Wanted) then
  begin
    Inc(Ctx^.Count);
    Ctx^.Found := h;
  end;

  Result := True;
end;

/// <summary>
/// Finds a child window by its caption, optionally filtering by allowed class names.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <param name="Caption" type="string">The caption to search for.</param>
/// <param name="AcceptedClasses" type="array of PChar">An array of allowed class names.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
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

/// <summary>
/// Attempts to parse a control ID token from a string.
/// </summary>
/// <param name="S" type="string">The string to parse.</param>
/// <param name="ID" type="Integer">The parsed control ID.</param>
/// <returns>True if the string was successfully parsed; otherwise, False.</returns>
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

/// <summary>
/// Finds a descendant window by its control ID.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <param name="CtrlId" type="Integer">The control ID to search for.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
function FindDescendantByControlId(Parent: HWND; CtrlId: Integer): HWND;
var
  ctx: TFindByIdCtx;

  /// <summary>
  /// Finds a child window by its control ID.
  /// </summary>
  /// <param name="h" type="HWND">The window handle.</param>
  /// <param name="lParam" type="LPARAM">The context information.</param>
  /// <returns>True to continue enumeration; otherwise, False.</returns>
  function EnumFindByIdProc(h: HWND; lParam: LPARAM): BOOL; stdcall;
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

begin
  Result := 0;
  if (Parent = 0) then
    Exit;
  ctx.TargetId := CtrlId;
  ctx.Found := 0;
  EnumChildWindows(Parent, @EnumFindByIdProc, lParam(@ctx));
  Result := ctx.Found;
end;

/// <summary>
/// Finds a descendant window by its control ID.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <param name="ID" type="Integer">The control ID to search for.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
function FindById(Parent: HWND; ID: Integer): HWND;
begin
  Result := FindDescendantByControlId(Parent, ID);
end;

/// <summary>
/// Tries to parse a string token representing a window handle (HWND) in various formats, such as "HWND:001A1CE4", "001A1CE4", "0x001A1CE4", or "$001A1CE4".
/// It validates the format and checks if the resulting handle corresponds to an existing window.
/// </summary>
/// <param name="S" type="string">The string to parse.</param>
/// <param name="h" type="HWND">The parsed window handle.</param>
/// <returns>True if the string was successfully parsed; otherwise, False.</returns>
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

/// <summary>
/// Resolves a control within a parent window based on a token that can represent the control's caption, ID, or HWND.
/// It searches for the control in the following order: by caption, by ID (if the token is in the form "ID:xxx" or a numeric value),
/// and finally by HWND (if the token is in the form "HWND:xxxx" or similar). If the control is found, its handle is returned;
/// otherwise, an exception is raised indicating that the control was not found.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <param name="Token" type="string">The token to resolve.</param>
/// <param name="AcceptedClasses" type="array of PChar">The accepted window classes.</param>
/// <returns>The handle of the resolved control, or 0 if not found.</returns>
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

  raise Exception.CreateFmt('Control "%s" not found (by name, ID, or HWND)', [Token]);
end;

/// <summary>
/// Resolves an alias token to its corresponding value, if it exists in the alias list; otherwise, returns the original token.
/// </summary>
/// <param name="Token" type="string">The alias token to resolve.</param>
/// <returns>The resolved value or the original token if the alias is not found.</returns>
function ResolveAlias(const Token: string): string;
begin
  if FAliases.IndexOfName(Token) >= 0 then
    Result := FAliases.Values[Token]
  else
    Result := Token;
end;

/// <summary>
/// Tries to resolve a mouse point alias (e.g., "MousePoint:100,200") to its corresponding screen coordinates.
/// </summary>
/// <param name="Token" type="string">The alias token to resolve.</param>
/// <param name="ScreenX" type="Integer">The resulting screen X coordinate.</param>
/// <param name="ScreenY" type="Integer">The resulting screen Y coordinate.</param>
/// <returns>True if the alias was resolved successfully, false otherwise.</returns>
function TryResolveMousePointAlias(const Token: string;
  out ScreenX, ScreenY: Integer): Boolean;
var
  AliasValue, Coordinates: string;
  Parts: TArray<string>;
begin
  Result := False;
  if FAliases.IndexOfName(Token) < 0 then
    Exit;

  AliasValue := FAliases.Values[Token];
  if not AliasValue.StartsWith(MOUSE_POINT_ALIAS_PREFIX) then
    Exit;

  Coordinates := Copy(AliasValue, Length(MOUSE_POINT_ALIAS_PREFIX) + 1, MaxInt);
  Parts := Coordinates.Split([',']);
  if Length(Parts) <> 2 then
    Exit;

  Result := TryStrToInt(Parts[0], ScreenX) and
    TryStrToInt(Parts[1], ScreenY);
end;

/// <summary>
/// Determines whether a window is edit-like.
/// </summary>
/// <param name="h">The window handle.</param>
/// <returns>True if the window is edit-like, false otherwise.</returns>
function IsEditLike(h: HWND): Boolean;
begin
  // Reuse edit-like classes
  Result := IsClassIn(h, EDIT_CLASS_NAMES);
end;

/// <summary>
/// Gets the top-level window for a given window handle, considering both parent and owner relationships.
/// </summary>
/// <param name="h">The window handle.</param>
/// <returns>The top-level window handle.</returns>
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

/// <summary>
/// Gets the class name of a window given its handle.
/// </summary>
/// <param name="h">The window handle.</param>
/// <returns>The window class name.</returns>
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

/// <summary>
/// Gets the text of a window given its handle.
/// </summary>
/// <param name="h" type="HWND">The window handle.</param>
/// <returns>The window text.</returns>
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

/// <summary>
/// Finds a top-level window by its caption or class name, optionally considering extra class names.
/// </summary>
/// <param name="HWND" type="HWND">The window handle to evaluate.</param>
/// <param name="lParam" type="lParam">The context information for the search.</param>
/// <returns>True to continue enumeration, false if the window is found.</returns>
function EnumWinFindProc(HWND: HWND; lParam: lParam): BOOL; stdcall;
var
  ctx: PFindWinCtx;
  cls, txt: string;

  /// <summary>
  /// Checks if a given string matches any string in an array, ignoring case.
  /// </summary>
  /// <param name="S">The string to search for.</param>
  /// <param name="Arr">The array of strings to search in.</param>
  /// <returns>True if a match is found, false otherwise.</returns>
  function SameTextArray(const S: string; const Arr: TArray<string>): Boolean;
  begin
    for var i := 0 to High(Arr) do
      if SameText(S, Arr[i]) then
        Exit(True);
    Result := False;
  end;

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

/// <summary>
/// Searches for the deepest child window at a given screen coordinate, traversing through child windows while skipping
/// invisible, disabled, or transparent windows.
/// </summary>
/// <param name="PtScreen" type="TPoint">The screen coordinates.</param>
/// <returns>The handle of the deepest child window at the specified location.</returns>
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

/// <summary>
/// Gets the text of a window in a safe manner, using the GetControlWindowText function to handle potential issues with certain window types.
/// </summary>
/// <param name="h" type="HWND">The window handle.</param>
/// <returns>The window text.</returns>
function GetWindowTextSafe(h: HWND): string;
begin
  Result := GetControlWindowText(h);
end;

/// <summary>
/// Gets the caption of the control at the specified screen coordinates.
/// </summary>
/// <param name="pt" type="TPoint">The screen coordinates.</param>
/// <returns>The caption of the control at the specified location.</returns>
function GetCaptionAtPoint(const pt: TPoint): string;

  /// <summary>
  /// Gets the caption of a control by checking for 'Caption' or 'CaptionValue' properties using RTTI.
  /// </summary>
  /// <param name="Control" type="TObject">The control for which to get the caption.</param>
  /// <returns>The result of the operation.</returns>
  function GetControlCaption(Control: TObject): string;
  var
    PropInfo: PPropInfo;
  begin
    Result := '';

    PropInfo := GetPropInfo(Control, 'Caption');
    if PropInfo <> nil then
      Result := GetStrProp(Control, PropInfo);

    if Result = '' then
    begin
      PropInfo := GetPropInfo(Control, 'CaptionValue');
      if PropInfo <> nil then
        Result := GetStrProp(Control, PropInfo);
    end;
  end;

var
  h: HWND;
  ctrl: TWinControl;
  child: TControl;
  i: Integer;
  localPt: TPoint;
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
      Result := GetControlCaption(child);
      if Result <> '' then
        Exit;
    end;
  end;

  // Only use the container's caption when its HWND is the actual hit target.
  if ctrl.Handle = h then
    Result := GetControlCaption(ctrl);
end;

/// <summary>
/// Gets the caption of a window or its control ID if the caption is empty.
/// </summary>
/// <param name="h" type="HWND">The window handle.</param>
/// <returns>The window caption or ID.</returns>
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

/// <summary>
/// Describes a window by providing its ID, text, parent, handle, position, class, and mouse coordinates.
/// </summary>
/// <param name="h" type="HWND">The window handle.</param>
/// <returns>The description of the window.</returns>
function DescribeWindow(h: HWND): string;

  /// <summary>
  /// Gets the first line of a string, stopping at the first carriage return or line feed character.
  /// </summary>
  /// <param name="S" type="string">The string to process.</param>
  /// <returns>The first line of the string.</returns>
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

  Result := Format(
    'ID=%d Text="%s" Parent="%s" HWND=%p Pos=%s Class=%s Mouse=[%d %d]',
    [ID, sTxt, parentTxt, Pointer(h), RectToStr(R), cls, pt.X, pt.Y]);
end;

/// <summary>
/// Describes the window at the specified screen coordinates.
/// </summary>
/// <param name="PtScreen" type="TPoint">The screen coordinates.</param>
/// <returns>The description of the window.</returns>
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

  Result := Format(
    'ID=%d Text="%s" HWND=%p Pos=%s Class=%s',
    [ID, txt, Pointer(h), RectToStr(R), cls]);
end;

{ ---- Misc helpers ---- }
/// <summary>
/// Encrypts or decrypts a string using a simple XOR-based algorithm with a predefined key.
/// </summary>
/// <param name="Action" type="string">The action to perform ('E' for encrypt, 'D' for decrypt).</param>
/// <param name="Src" type="string">The string to encrypt or decrypt.</param>
/// <returns>The result of the operation.</returns>
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

/// <summary>
/// Finds a top-level window by its caption or class name, with the ability to specify additional class names to consider during the search.
/// </summary>
/// <param name="TitleOrClass" type="string">The caption or class name to search for.</param>
/// <param name="ExtraClasses" type="TArray<string>">An array of additional class names to consider during the search.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
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

/// <summary>
/// Normalizes a label string by trimming whitespace and removing a trailing colon if present.
/// </summary>
/// <param name="S" type="string">The string to normalize.</param>
/// <returns>The normalized string.</returns>
function NormalizeLabel(const S: string): string;
var
  t: string;
begin
  t := Trim(S);
  if (t <> '') and (t[Length(t)] = ':') then
    Delete(t, Length(t), 1);
  Result := Trim(t);
end;

/// <summary>
/// Requires a dialog window by its title or class name, with the ability to specify additional class names to consider during the search.
/// If the window is not found, an exception is raised.
/// </summary>
/// <param name="TitleOrClass" type="string">The title or class name to search for.</param>
/// <returns>The handle of the found window.</returns>
function RequireDialogFlexible(const TitleOrClass: string): HWND;
var
  h: HWND;

  /// <summary>
  /// Finds a dialog window by its title.
  /// </summary>
  /// <param name="Title" type="string">The title of the dialog to find.</param>
  /// <returns>The handle of the found dialog, or 0 if not found.</returns>
  function FindDialogByTitle(const Title: string): HWND;
  begin
    Result := FindWindow(PChar(DIALOG_CLASS), PChar(Title));
  end;

begin
  h := FindDialogByTitle(TitleOrClass);
  if h <> 0 then
    Exit(h);

  h := FindTopWindowByTitleOrClass(TitleOrClass);
  if h <> 0 then
    Exit(h);

  raise Exception.CreateFmt('Window not found (dialog/top/class): "%s"', [TitleOrClass]);
end;

/// <summary>
/// Finds a descendant window by its text or class name.
/// </summary>
/// <param name="Parent" type="HWND">The parent window handle.</param>
/// <param name="Token" type="string">The text or class name to search for.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
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

/// <summary>
/// Resolves a root window based on a token, which can be a dialog title, top-level window title/class, or an HWND token.
/// </summary>
/// <param name="Token" type="string">The token to search for.</param>
/// <returns>The handle of the found window, or 0 if not found.</returns>
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

/// <summary>
/// Brings a window to the foreground.
/// </summary>
/// <param name="hWnd" type="HWND">The handle of the window to bring to the foreground.</param>
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

/// <summary>
/// Clicks a control by simulating a mouse click at its center, bringing the parent window to the foreground first.
/// </summary>
/// <param name="h" type="HWND">The handle of the control to click.</param>
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
/// <summary>
/// TForm1.FormCreate is called when the form is created (i.e. the program is first run).
/// It initializes various components, sets up the inspector overlay, and handles command-line parameters for loading a script file.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.FormCreate(Sender: TObject);
var
  RunScriptProc: TThreadProcedure;
begin
  FInspectorOverlay := TInspectorOverlay.Create(nil);
  FHasInspectorPos := False;
  FStopRequested := False;
  FRecording := False;
  FScriptFilename := '';
  GRecorderForm := Self;
  FAliases := TStringList.Create;
  FAliases.CaseSensitive := False;
  FAliases.StrictDelimiter := True;
  FAliases.Delimiter := '=';

  if ConsoleMode then
  begin
    if ParamCount <> 2 then
      raise Exception.Create('Usage: Clicker.exe --console <script-file>');
    FScriptFilename := ParamStr(2);
  end
  else if ParamCount >= 1 then
    FScriptFilename := ParamStr(1);

  if FScriptFilename <> '' then
  begin
    if FileExists(FScriptFilename) then
    begin
      mmoScript.Lines.LoadFromFile(FScriptFilename);

      if ConsoleMode then
        btnGoClick(Self)
      else
      begin
        RunScriptProc :=
          procedure
          begin
            btnGo.Click;
          end;
        TThread.Queue(nil, RunScriptProc);
      end;
    end
    else
      raise Exception.CreateFmt('Script file not found: %s', [FScriptFilename]);
  end;
end;

/// <summary>
/// TForm1.FormDestroy is called when the form is destroyed (i.e. the program is closing).
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.FormDestroy(Sender: TObject);
begin
  if FRecording then
    SetRecording(False);

  GRecorderForm := nil;
  FInspectorOverlay.Free;
  FAliases.Free;
end;

/// <summary>
/// TForm1.CloseWindowByCaption is called to close a window by its caption.
/// </summary>
/// <param name="WindowTitle" type="string">The caption of the window to close.</param>
procedure TForm1.CloseWindowByCaption(const WindowTitle: string);
var
  W: HWND;
begin
  W := FindWindow(nil, PChar(WindowTitle));
  if W <> 0 then
    PostMessage(W, WM_CLOSE, 0, 0);
end;

/// <summary>
/// TForm1.EncryptClick is called when the encrypt button is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.EncryptClick(Sender: TObject);
begin
  FEncryptOutput.Text := DoCryptXOR('E', FEncryptInput.Text);
end;

/// <summary>
/// TForm1.Encryption1Click is called when the encryption button is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
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

/// <summary>
/// TForm1.tmrInspectorTimer is called on a timer event to inspect the window under the mouse cursor.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.tmrInspectorTimer(Sender: TObject);
var
  pt: TPoint;
  h: HWND;
  S: string;
  R: TRect;
  Details: TStringList;

  /// <summary>
  /// Describes a window in detail, including its class, ID, parent, position, size, and caption, based on the provided window handle and screen coordinates.
  /// </summary>
  /// <param name="h" type="HWND">The window handle.</param>
  /// <param name="Pt" type="TPoint">The screen coordinates.</param>
  /// <returns>The description of the window.</returns>
  function DescribeWindowDetails(h: HWND; const Pt: TPoint): TStringList;
  var
    ClassNameBuffer, TextBuffer: array [0 .. 255] of Char;
    CaptionText, ParentText: string;
    ParentH: HWND;
    R: TRect;
    ID: LongInt;
  begin
    Result := TStringList.Create;
    Result.Add(Format('Mouse: X=%d  Y=%d', [Pt.X, Pt.Y]));
    if h = 0 then
    begin
      Result.Add('No object under cursor');
      Exit;
    end;

    GetClassName(h, ClassNameBuffer, Length(ClassNameBuffer));
    GetWindowText(h, TextBuffer, Length(TextBuffer));
    CaptionText := TextBuffer;

    if CaptionText = '' then
      CaptionText := GetCaptionAtPoint(Pt);

    CaptionText := StringReplace(CaptionText, #13, ' ', [rfReplaceAll]);
    CaptionText := StringReplace(CaptionText, #10, ' ', [rfReplaceAll]);

    if Length(CaptionText) > 100 then
      CaptionText := Copy(CaptionText, 1, 97) + '...';

    if CaptionText = '' then
      CaptionText := '(none)';

    ParentH := GetParent(h);
    if ParentH <> 0 then
      ParentText := GetWindowCaptionOrID(ParentH)
    else
      ParentText := '(none)';

    if Length(ParentText) > 50 then
      ParentText := Copy(ParentText, 1, 47) + '...';

    if not GetWindowRect(h, R) then
      R := Rect(0, 0, 0, 0);

    ID := GetWindowLong(h, GWL_ID);
    Result.Add('Object class: ' + string(ClassNameBuffer));
    Result.Add(Format('ID: %d  HWND: %p', [ID, Pointer(h)]));
    Result.Add('Parent: ' + ParentText);
    Result.Add('Pos: ' + RectToStr(R));
    Result.Add(Format('Left: %d  Top: %d', [R.Left, R.Top]));
    Result.Add(Format('Width: %d  Height: %d', [R.Right - R.Left, R.Bottom - R.Top]));
    Result.Add('Caption: ' + CaptionText);
  end;

begin
  GetCursorPos(pt);
  if not chkHoverText.Checked then
  begin
    FHasInspectorPos := False;
    FInspectorOverlay.HideInfo;
    Exit;
  end;

  if FHasInspectorPos and (pt.X = FLastInspectorPos.X) and (pt.Y = FLastInspectorPos.Y) then
    Exit;

  FLastInspectorPos := pt;
  FHasInspectorPos := True;

  if FInspectorOverlay.ContainsInfoAt(pt) then
  begin
    FInspectorOverlay.HideInfo;
    Exit;
  end;

  h := DeepChildWindowFromPoint(pt);
  if (h = Handle) or IsChild(Handle, h) then
  begin
    FInspectorOverlay.HideInfo;
    Exit;
  end;

  S := DescribeWindow(h);

  // Show live info
  Caption := 'Clicker - ' + S;
  if GetWindowRect(h, R) = False then
    R := Rect(0, 0, 0, 0);

  Details := DescribeWindowDetails(h, pt);
  try
    FInspectorOverlay.UpdateInspector(R, pt, Details);
  finally
    Details.Free;
  end;
end;

/// <summary>
/// TForm1.chkHoverTextClick is called when the hover text checkbox is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.chkHoverTextClick(Sender: TObject);
begin
  FHasInspectorPos := False;
  if not chkHoverText.Checked then
  begin
    FInspectorOverlay.HideInfo;
    //Caption := 'Clicker';
  end;
end;

/// <summary>
/// TForm1.btnLoadClick is called when the load button is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
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

/// <summary>
/// TForm1.btnSaveClick is called when the save button is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.btnSaveClick(Sender: TObject);
var
  SL: TStringList;
  dlg: TSaveDialog;
begin
  if FScriptFilename = '' then
  begin
    dlg := TSaveDialog.Create(Self);
    try
      dlg.Filter := 'Script files (*.script)|*.script|All files (*.*)|*.*';
      dlg.DefaultExt := 'script';
      dlg.Options := [ofPathMustExist, ofOverwritePrompt];
      if not dlg.Execute then
        Exit;
      FScriptFilename := ChangeFileExt(dlg.FileName, '.script');
    finally
      dlg.Free;
    end;
  end;

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

/// <summary>
/// TForm1.MouseClickAt is called to simulate a mouse click at a specific screen location.
/// </summary>
/// <param name="ScreenX">The x-coordinate of the screen location.</param>
/// <param name="ScreenY">The y-coordinate of the screen location.</param>
/// <param name="Button">The mouse button to click ('Left', 'Right', or 'Middle').</param>
procedure TForm1.MouseClickAt(ScreenX, ScreenY: Integer;
  const Button: string);
var
  DownFlag, UpFlag: DWORD;
begin
  SetCursorPos(ScreenX, ScreenY);

  if SameText(Button, 'Right') then
  begin
    DownFlag := MOUSEEVENTF_RIGHTDOWN;
    UpFlag := MOUSEEVENTF_RIGHTUP;
  end
  else if SameText(Button, 'Middle') then
  begin
    DownFlag := MOUSEEVENTF_MIDDLEDOWN;
    UpFlag := MOUSEEVENTF_MIDDLEUP;
  end
  else
  begin
    DownFlag := MOUSEEVENTF_LEFTDOWN;
    UpFlag := MOUSEEVENTF_LEFTUP;
  end;

  mouse_event(DownFlag, 0, 0, 0, 0);
  mouse_event(UpFlag, 0, 0, 0, 0);
end;

/// <summary>
/// TForm1.ScrollMouseAt is called to simulate a mouse scroll at a specific screen location.
/// </summary>
/// <param name="ScreenX">The x-coordinate of the screen location.</param>
/// <param name="ScreenY">The y-coordinate of the screen location.</param>
/// <param name="Delta">The amount to scroll.</param>
procedure TForm1.ScrollMouseAt(ScreenX, ScreenY, Delta: Integer);
begin
  SetCursorPos(ScreenX, ScreenY);
  mouse_event(MOUSEEVENTF_WHEEL, 0, 0, DWORD(Delta), 0);
end;

/// <summary>
/// TForm1.AppendRecordedCommand is called to append a recorded command to the script.
/// </summary>
/// <param name="Command">The command to append.</param>
procedure TForm1.AppendRecordedCommand(const Command: string);
begin
  mmoScript.Lines.Add(Command);
  lblStatus.Caption := 'Recording macro...';
end;

/// <summary>
/// TForm1.FlushRecordedText is called to flush the recorded text to the script.
/// </summary>
procedure TForm1.FlushRecordedText;
begin
  if FRecordedText = '' then
    Exit;

  AppendRecordedCommand('TypeText ' + QuoteScriptToken(FRecordedText));
  FRecordedText := '';
end;

/// <summary>
/// TForm1.RecordMouseClick is called to record a mouse click at a specific screen location.
/// </summary>
/// <param name="ScreenX" type="Integer">The x-coordinate of the screen location.</param>
/// <param name="ScreenY" type="Integer">The y-coordinate of the screen location.</param>
/// <param name="Button" type="string">The mouse button to click ('Left', 'Right', or 'Middle').</param>
procedure TForm1.RecordMouseClick(ScreenX, ScreenY: Integer; const Button: string);
var
  Control, Root: HWND;
  WindowName, ButtonName: string;
  ScreenPoint: TPoint;
  ControlRect: TRect;
begin
  ScreenPoint.X := ScreenX;
  ScreenPoint.Y := ScreenY;
  Control := DeepChildWindowFromPoint(ScreenPoint);
  ButtonName := GetWindowTextSafe(Control);
  Root := GetTopLevelWindow(Control);
  WindowName := GetWindowTextSafe(Root);

  if SameText(Button, 'Left') and IsClassIn(Control, BUTTON_CLASS_NAMES) and (ButtonName <> '') and (WindowName <> '') then
    AppendRecordedCommand('ClickButton ' + QuoteScriptToken(WindowName) + ' ' + QuoteScriptToken(ButtonName))
  else
  begin
    if (Control <> 0) and GetWindowRect(Control, ControlRect) and
      (ControlRect.Right > ControlRect.Left) and
      (ControlRect.Bottom > ControlRect.Top) then
    begin
      ScreenX := (ControlRect.Left + ControlRect.Right) div 2;
      ScreenY := (ControlRect.Top + ControlRect.Bottom) div 2;
    end;

    AppendRecordedCommand(Format(
      'MouseClick %d %d %s',
      [ScreenX, ScreenY, Button]));
  end;
end;

/// <summary>
/// TForm1.SetRecording is called to set the recording state.
/// </summary>
/// <param name="Value" type="Boolean">The recording state to set.</param>
procedure TForm1.SetRecording(Value: Boolean);
var
  UnhookFailed: Boolean;
  ErrorCode: DWORD;
begin
  if Value = FRecording then
    Exit;

  if Value then
  begin
    FillChar(GRecordedKeys, SizeOf(GRecordedKeys), 0);
    FRecordedText := '';
    GKeyboardRecordHook := SetWindowsHookEx(WH_KEYBOARD_LL,
      @LowLevelKeyboardRecordProc, HInstance, 0);
    if GKeyboardRecordHook = 0 then
      RaiseLastOSError;

    GMouseRecordHook := SetWindowsHookEx(WH_MOUSE_LL,
      @LowLevelMouseRecordProc, HInstance, 0);
    if GMouseRecordHook = 0 then
    begin
      ErrorCode := GetLastError;
      UnhookWindowsHookEx(GKeyboardRecordHook);
      GKeyboardRecordHook := 0;
      raise Exception.CreateFmt(
        'Could not install the mouse recording hook: %s',
        [SysErrorMessage(ErrorCode)]);
    end;

    FRecording := True;
    btnRecord.Caption := 'Stop';
    lblStatus.Caption := 'Recording macro...';
    mmoScript.Lines.Add('; Recorded macro');
  end
  else
  begin
    FlushRecordedText;
    FRecording := False;
    UnhookFailed := False;
    ErrorCode := 0;
    if (GKeyboardRecordHook <> 0) and
      not UnhookWindowsHookEx(GKeyboardRecordHook) then
    begin
      UnhookFailed := True;
      ErrorCode := GetLastError;
    end;
    GKeyboardRecordHook := 0;
    if (GMouseRecordHook <> 0) and
      not UnhookWindowsHookEx(GMouseRecordHook) then
    begin
      if not UnhookFailed then
        ErrorCode := GetLastError;
      UnhookFailed := True;
    end;
    GMouseRecordHook := 0;
    FillChar(GRecordedKeys, SizeOf(GRecordedKeys), 0);
    btnRecord.Caption := 'Record';
    lblStatus.Caption := 'Recording stopped';
    Save1.Enabled := True;
    if UnhookFailed then
      raise Exception.CreateFmt(
        'Could not remove an input recording hook: %s',
        [SysErrorMessage(ErrorCode)]);
  end;
end;

/// <summary>
/// TForm1.btnRecordClick is called when the record button is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.btnRecordClick(Sender: TObject);
begin
  SetRecording(not FRecording);
end;

/// <summary>
/// TForm1.RecordKey is called to record a key press.
/// </summary>
/// <param name="VKCode" type="UINT">The virtual key code.</param>
/// <param name="ScanCode" type="UINT">The scan code.</param>
procedure TForm1.RecordKey(VKCode, ScanCode: UINT);
var
  KeyName, Chord: string;
  KeyChar: Char;
  KeyboardState: TKeyboardState;
  TextBuffer: array[0..1] of Char;
  CharacterCount: Integer;
  KeyboardLayout: HKL;
begin
  if (GetAsyncKeyState(VK_CONTROL) >= 0) and
    (GetAsyncKeyState(VK_MENU) >= 0) and
    (GetAsyncKeyState(VK_LWIN) >= 0) and
    (GetAsyncKeyState(VK_RWIN) >= 0) and
    GetKeyboardState(KeyboardState) then
  begin
    if GetAsyncKeyState(VK_SHIFT) < 0 then
      KeyboardState[VK_SHIFT] := KeyboardState[VK_SHIFT] or $80
    else
      KeyboardState[VK_SHIFT] := KeyboardState[VK_SHIFT] and $7F;
    if VKCode <= High(KeyboardState) then
      KeyboardState[VKCode] := KeyboardState[VKCode] or $80;

    KeyboardLayout := GetKeyboardLayout(0);
    CharacterCount := ToUnicodeEx(VKCode, ScanCode, @KeyboardState[0], PWideChar(@TextBuffer[0]), Length(TextBuffer), 0, KeyboardLayout);
    if (CharacterCount = 1) and (Ord(TextBuffer[0]) >= 32) then
    begin
      FRecordedText := FRecordedText + TextBuffer[0];
      Exit;
    end;
  end;

  FlushRecordedText;
  KeyName := '';
  if (VKCode >= Ord('A')) and (VKCode <= Ord('Z')) then
    KeyName := Char(VKCode)
  else if (VKCode >= Ord('0')) and (VKCode <= Ord('9')) then
    KeyName := Char(VKCode)
  else if (VKCode >= VK_F1) and (VKCode <= VK_F24) then
    KeyName := 'F' + IntToStr(VKCode - VK_F1 + 1)
  else
  begin
    KeyChar := #0;
    case VKCode of
      VK_RETURN: KeyName := 'Enter';
      VK_ESCAPE: KeyName := 'Esc';
      VK_TAB: KeyName := 'Tab';
      VK_BACK: KeyName := 'Backspace';
      VK_SPACE: KeyName := 'Space';
      VK_LEFT: KeyName := 'Left';
      VK_RIGHT: KeyName := 'Right';
      VK_UP: KeyName := 'Up';
      VK_DOWN: KeyName := 'Down';
      VK_INSERT: KeyName := 'Insert';
      VK_DELETE: KeyName := 'Delete';
      VK_HOME: KeyName := 'Home';
      VK_END: KeyName := 'End';
      VK_PRIOR: KeyName := 'PageUp';
      VK_NEXT: KeyName := 'PageDown';
      VK_SNAPSHOT: KeyName := 'PrintScreen';
      VK_NUMLOCK: KeyName := 'NumLock';
      VK_CAPITAL: KeyName := 'CapsLock';
      VK_SCROLL: KeyName := 'ScrollLock';
      VK_APPS: KeyName := 'Apps';
      VK_NUMPAD0..VK_NUMPAD9: KeyName := 'Numpad' + IntToStr(VKCode - VK_NUMPAD0);
      VK_ADD: KeyName := 'NumpadAdd';
      VK_SUBTRACT: KeyName := 'NumpadSub';
      VK_MULTIPLY: KeyName := 'NumpadMul';
      VK_DIVIDE: KeyName := 'NumpadDiv';
      VK_DECIMAL: KeyName := 'NumpadDec';
      VK_OEM_1: KeyChar := ';';
      VK_OEM_PLUS: KeyChar := '=';
      VK_OEM_COMMA: KeyChar := ',';
      VK_OEM_MINUS: KeyChar := '-';
      VK_OEM_PERIOD: KeyChar := '.';
      VK_OEM_2: KeyChar := '/';
      VK_OEM_3: KeyChar := '`';
      VK_OEM_4: KeyChar := '[';
      VK_OEM_5, VK_OEM_102: KeyChar := '\';
      VK_OEM_6: KeyChar := ']';
      VK_OEM_7: KeyChar := '''';
    end;

    if KeyName = '' then
    begin
      if KeyChar = #0 then
        Exit;
      KeyName := KeyChar;
    end;
  end;

  Chord := '';
  if GetAsyncKeyState(VK_CONTROL) < 0 then
    Chord := 'Ctrl';

  if GetAsyncKeyState(VK_SHIFT) < 0 then
  begin
    if Chord <> '' then Chord := Chord + '+';
    Chord := Chord + 'Shift';
  end;

  if GetAsyncKeyState(VK_MENU) < 0 then
  begin
    if Chord <> '' then Chord := Chord + '+';
    Chord := Chord + 'Alt';
  end;

  if (GetAsyncKeyState(VK_LWIN) < 0) or (GetAsyncKeyState(VK_RWIN) < 0) then
  begin
    if Chord <> '' then Chord := Chord + '+';
    Chord := Chord + 'Win';
  end;

  if Chord <> '' then
    Chord := Chord + '+';

  Chord := Chord + KeyName;

  if KeyName.Contains(';') or KeyName.Contains('#') then
    AppendRecordedCommand('PressKey "' + Chord + '"')
  else
    AppendRecordedCommand('PressKey ' + Chord);
end;

/// <summary>
/// TForm1.mmoScriptChange is called when the script memo changes, updating line numbers and enabling the save button.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.mmoScriptChange(Sender: TObject);
begin
  // sync mmoLineNumbers so that both have the same number of lines
  mmoLineNumbers.Lines.Clear;

  for var i := 0 to mmoScript.Lines.Count - 1 do
    mmoLineNumbers.Lines.Add(IntToStr(i + 1));

  mmoLineNumbers.ScrollPosition := mmoScript.ScrollPosition;
  Save1.Enabled := True;

  if FRecording then
    lblStatus.Caption := 'Recording macro...'
  else
    lblStatus.Caption := 'Ready';
end;

/// <summary>
/// TForm1.mmoScriptKeyPress is called when a key is pressed while the script memo has focus.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
/// <param name="Key" type="Char">The key that was pressed.</param>
procedure TForm1.mmoScriptKeyPress(Sender: TObject; var Key: Char);
begin
  mmoLineNumbers.ScrollPosition := mmoScript.ScrollPosition;
end;

/// <summary>
/// TForm1.Quit1Click is called when the quit menu item is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.Quit1Click(Sender: TObject);
begin
  Application.Terminate;
end;

/// <summary>
/// TForm1.Reference1Click is called when the reference menu item is clicked.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
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
    SL.Add('  MouseClick <x> <y> [Left|Right|Middle] or MouseClick <coordinateAlias> [Left|Right|Middle]');
    SL.Add('    Clicks the specified mouse button at the screen coordinates. Left is the default.');
    SL.Add('  MouseWheel <x> <y> <delta>');
    SL.Add('    Scrolls the mouse wheel at the screen coordinates by the specified delta.');
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
    SL.Add('    Loads a script relative to the current script folder, the Clicker.exe folder, or C:\Scripts (in that order). The .script extension is optional.');
    SL.Add('');
    SL.Add('  SetPause <time>');
    SL.Add('    Sets the default time (in ms) between commands, the default is 100 ms');
    SL.Add('  Sleep <milliseconds>');
    SL.Add('    Pauses execution for the specified time (default is 1 second). The default pause time is not added after Sleep.');
    SL.Add('  Alias <name> <value> or Alias <name> <x> <y>');
    SL.Add('    Defines a reusable value or screen-coordinate alias, e.g. `Alias zero 839 636` then `MouseClick zero`');
    SL.Add('  Assert <"Button"|"Edit"> <WindowName> <name|id|hwnd> "Expected text"');
    SL.Add('    The script will continue only when the expected text is found');
    SL.Add('    If WindowName is omitted, it will default to what is in the default window box');
    SL.Add('  Assert Color <x> <y> <#RRGGBB|colorName>');
    SL.Add('    Checks the pixel color at the specified screen coordinates, e.g. Assert Color 121 254 #1a2b3c or Assert Color 321 222 red');
    SL.Add('    Samples up to 10 times, 100 ms apart; the expected color must match at least 8 samples.');
    SL.Add('    Custom color: clYellowPNS is RGB 254,216,3 (#FED803)');
    SL.Add('  Close <windowName>');
    SL.Add('    Closes a window or dialog');
    SL.Add('  Stop');
    SL.Add('    Stops the current script immediately; all remaining commands are skipped');
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

/// <summary>
/// TForm1.SetEditText is called to set the text of an edit control.
/// </summary>
/// <param name="Edit" type="HWND">The handle of the edit control.</param>
/// <param name="Value" type="string">The text to set.</param>
/// <returns type="Boolean">True if the operation was successful, false otherwise.</returns>
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

/// <summary>
/// TForm1.RunScriptLines is called to execute a list of script lines.
/// </summary>
/// <param name="Lines" type="TStrings">The list of script lines to execute.</param>
/// <param name="SourceName" type="string">The name of the source containing the script lines.</param>
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

    lblStatus.Caption := Format(
      'Running %s:%d → %s',
      [SourceName, lineNumber + 1, Line]);

    Application.ProcessMessages;

    // ---- COMMAND DISPATCH ----
    mmoLineNumbers.Lines[lineNumber] := Format('%s %d', [RUNNING, lineNumber + 1]);

    if ExecuteCommand(parts, lineNumber, SourceName) then
      mmoLineNumbers.Lines[lineNumber] := Format('%s %d', [COMPLETED, lineNumber + 1])
    else
    begin
      mmoLineNumbers.Lines[lineNumber] := Format('%s %d', [ERROR, lineNumber + 1]);
      lblStatus.Caption := 'Completed with error';
      Application.ProcessMessages;
      if ConsoleMode then
        ConsoleExitCode := 1;
      ShowTextDialog('Error', Format(
        'Error on line %d. Command in %s failed.' + CRLF + '%s',
        [lineNumber, SourceName, Line]));
      Exit;
    end;

    if FStopRequested then
    begin
      lblStatus.Caption := 'Stopped';
      Exit;
    end;

    if not SameText(parts[0], 'Sleep') then
      Sleep(StrToIntDef(edtPauseTime.Text, 100));
  end;

  lblStatus.Caption := 'Completed all tasks';
end;

/// <summary>
/// Resolves an edit control handle based on a token, which can be a window handle, control ID, friendly name, or label text.
/// </summary>
/// <param name="W" type="HWND">The window handle.</param>
/// <param name="Token" type="string">The token to resolve.</param>
/// <returns type="HWND">The result of the operation.</returns>
function ResolveEditHandle(W: HWND; const Token: string): HWND;
var
  Edits: TArray<HWND>;
  Index, CtrlId: Integer;
  h: HWND;

  /// <summary>
  /// Finds an edit control near a label.
  /// </summary>
  /// <param name="Parent" type="HWND">The parent window handle.</param>
  /// <param name="LabelText" type="string">The text of the label to find.</param>
  /// <returns>The handle of the found edit control, or 0 if not found.</returns>
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

/// <summary>
/// Resolves the full path of a script file based on its name and the parent script's path.
/// </summary>
/// <param name="ScriptName" type="string">The name of the script file to resolve.</param>
/// <param name="ParentScriptPath" type="string">The path of the parent script.</param>
/// <returns type="string">The full path of the resolved script file.</returns>
function ResolveScriptPath(const ScriptName, ParentScriptPath: string): string;
var
  FileName: string;
  SearchDirectories: TArray<string>;
  Candidate: string;
begin
  FileName := ScriptName;
  if ExtractFileExt(FileName) = '' then
    FileName := FileName + '.script';

  if (ExtractFileDrive(FileName) <> '') or
    ((FileName <> '') and (FileName[1] = PathDelim)) then
  begin
    if FileExists(FileName) then
      Exit(ExpandFileName(FileName));
    raise Exception.CreateFmt('Script not found: %s', [FileName]);
  end;

  if (ParentScriptPath <> '') and FileExists(ParentScriptPath) then
    SearchDirectories := [ExtractFilePath(ExpandFileName(ParentScriptPath)),
      ExtractFilePath(ParamStr(0)), 'C:\Scripts\']
  else
    SearchDirectories := [ExtractFilePath(ParamStr(0)), 'C:\Scripts\'];

  for var Directory in SearchDirectories do
  begin
    Candidate := IncludeTrailingPathDelimiter(Directory) + FileName;
    if FileExists(Candidate) then
      Exit(ExpandFileName(Candidate));
  end;

  raise Exception.CreateFmt(
    'Script "%s" not found. Searched the script folder, application folder, and C:\Scripts.',
    [ScriptName]);
end;

/// <summary>
/// Expands "Load" commands in a list of script lines by replacing them with the contents of the specified script files.
/// This is analogous to a preprocessor include directive, allowing scripts to be modular and reusable.
/// </summary>
/// <param name="Lines" type="TStrings">The list of script lines to process.</param>
/// <param name="SourceFileName" type="string">The name of the source file containing the script lines.</param>
procedure ExpandLoadCommands(Lines: TStringList; const SourceFileName: string);
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
      LoadFile := ResolveScriptPath(Parts[1], SourceFileName);

      InsertLines := TStringList.Create;
      try
        InsertLines.LoadFromFile(LoadFile, TEncoding.UTF8);
        ExpandLoadCommands(InsertLines, LoadFile);

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

/// <summary>
/// Clicks an element within a specified window, resolving the element by its token (which can be a name, ID, or other identifier).
/// </summary>
/// <param name="WindowName" type="string">The name of the window containing the element.</param>
/// <param name="Token" type="string">The token identifying the element.</param>
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

/// <summary>
/// Runs a command based on the provided parts, line number, and source name. This function interprets the command and executes the corresponding action.
/// This is the main part of the script execution engine, dispatching commands to their respective handlers.
/// </summary>
/// <param name="parts" type="TArray<string>">The list of command parts to execute.</param>
/// <param name="lineNumber" type="Integer">The line number in the source file.</param>
/// <param name="SourceName" type="string">The name of the source file.</param>
/// <returns type="Boolean">The result of the operation.</returns>
function TForm1.ExecuteCommand(const parts: TArray<string>; lineNumber: Integer; const SourceName: string): Boolean;
var
  ScriptName, ScriptPath: string;
  bOK: Boolean;

  function ParseAppCommand(const S: string): TAppCommand;
  begin
    if SameText(S, 'Load') then
      Exit(CmdLoad);
    if SameText(S, 'DumpWindow') then
      Exit(CmdDumpWindow);
    if SameText(S, 'ClickButton') then
      Exit(CmdClickButton);
    if SameText(S, 'ClickElement') then
      Exit(CmdClickElement);
    if SameText(S, 'MouseClick') then
      Exit(CmdMouseClick);
    if SameText(S, 'MouseWheel') then
      Exit(CmdMouseWheel);
    if SameText(S, 'SetText') then
      Exit(CmdSetText);
    if SameText(S, 'Close') then
      Exit(CmdClose);
    if SameText(S, 'TypeText') then
      Exit(CmdTypeText);
    if SameText(S, 'TypePassword') then
      Exit(CmdTypePassword);
    if SameText(S, 'PressKey') then
      Exit(CmdPressKey);
    if SameText(S, 'DumpHere') then
      Exit(CmdDumpHere);
    if SameText(S, 'SetPause') then
      Exit(CmdSetPause);
    if SameText(S, 'Sleep') then
      Exit(CmdSleep);
    if SameText(S, 'LaneTool') then
      Exit(CmdLaneTool);
    if SameText(S, 'Alias') then
      Exit(CmdAlias);
    if SameText(S, 'Stop') then
      Exit(CmdStop);
    if SameText(S, 'Assert') then
      Exit(CmdAssert);

    raise Exception.CreateFmt('Unknown command: %s', [S]);
  end;

  /// <summary>
  /// Simulates the pressing of a key combination (chord) specified as a string, such as "Ctrl+Shift+X".
  /// </summary>
  /// <param name="Chord" type="string">The key combination to simulate.</param>
  procedure SendChord(const Chord: string);
  var
    Token: string;
    mods: TModifiers;
    VK: UINT;
    ext: Boolean;

    /// <summary>
    /// Converts a key name (like "Enter", "Esc", "F1", etc.) to its corresponding virtual key code (VK).
    /// </summary>
    /// <param name="Name" type="string">The name of the key.</param>
    /// <param name="VK" type="UINT">The virtual key code.</param>
    /// <returns>True if the key name was recognized, false otherwise.</returns>
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
          Exit(False);
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

    /// <summary>
    /// Converts a string representing a combination of modifier keys to a set of modifier flags.
    /// </summary>
    /// <param name="Token" type="string">The token representing the key combination.</param>
    /// <returns>The set of modifier flags.</returns>
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
      SendInputKey(VK_MENU, True, False); //Alt
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

  /// <summary>
  /// Requires a top-level window by its caption or class name, with the ability to specify additional class names to consider during the search.
  /// If the window is not found, an exception is raised.
  /// </summary>
  /// <param name="TitleOrClass" type="string">The caption or class name to search for.</param>
  /// <returns>The handle of the found window, or 0 if not found.</returns>
  function RequireTopWindowFlexible(const TitleOrClass: string): HWND;
  begin
    // Default extra classes including the common dialog class and custom one
    Result := FindTopWindowByTitleOrClassFlexible(TitleOrClass, [DIALOG_CLASS, 'TFormPOSOptionsBox']);
    if Result = 0 then
      raise Exception.CreateFmt(
        'Window not found (caption OR class): "%s"',
        [TitleOrClass]);
  end;

  /// <summary>
  /// Gets the text of an edit control.
  /// </summary>
  /// <param name="h" type="HWND">The handle of the edit control.</param>
  /// <returns>The text of the edit control, or an empty string if not found.</returns>
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

begin

  bOK := False;
  Result := bOK;

  case ParseAppCommand(parts[0]) of //TAppCommand

    CmdDumpWindow:
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
        raise Exception.CreateFmt(
          'Error on line %d. DumpWindow usage: DumpWindow <windowCaptionOrClass>',
          [lineNumber + 1]);
    end;

    CmdClickButton:
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
          ShowTextDialog('Error', Format(
            'Error on line %d. Button "%s" not found in "%s".' + CRLF + CRLF + '%s',
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
          ShowTextDialog('Error', Format(
            'Error on line %d. Button "%s" not found in "%s".' + CRLF + CRLF + '%s',
            [lineNumber + 1, Token, defaultWindowName.Text, FormatButtonsSummary(W)]), 500, 200);
        end
        else
        begin
          ClickByMouse(Btn);
          bOK := True;
        end;
      end
      else
        raise Exception.CreateFmt(
          'Error on line %d. ClickButton usage: ClickButton <caption|name>  OR  ClickButton <window> <caption|name>',
          [lineNumber + 1]);
    end;

    CmdClickElement:
    begin
      // On SCO, don't think this can be used as there is only 1 element on the entire screen :-(
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
    end;

    CmdMouseClick:
    begin
      // Default button is Left
      var ScreenX, ScreenY: Integer;
      var Button: string;

      if (Length(parts) = 2) or
        ((Length(parts) = 3) and TryResolveMousePointAlias(parts[1], ScreenX, ScreenY)) then
      begin
        if Length(parts) = 2 then
        begin
          if not TryResolveMousePointAlias(parts[1], ScreenX, ScreenY) then
            raise Exception.CreateFmt(
              'Error on line %d. "%s" is not a coordinate alias. Define it with Alias <name> <x> <y>.',
              [lineNumber + 1, parts[1]]);
          Button := 'Left';
        end
        else
          Button := parts[2];

        if not (SameText(Button, 'Left') or SameText(Button, 'Right') or SameText(Button, 'Middle')) then
          raise Exception.CreateFmt(
            'Error on line %d. Unknown mouse button "%s".',
            [lineNumber + 1, Button]);

        MouseClickAt(ScreenX, ScreenY, Button);
      end
      else if (Length(parts) <> 3) and (Length(parts) <> 4) then
        raise Exception.CreateFmt(
          'Error on line %d. MouseClick usage: MouseClick <x> <y> [Left|Right|Middle] or MouseClick <coordinateAlias> [Left|Right|Middle]',
          [lineNumber + 1])
      else
      begin
        if Length(parts) = 3 then
          MouseClickAt(StrToInt(parts[1]), StrToInt(parts[2]), 'Left')
        else if SameText(parts[3], 'Left') or SameText(parts[3], 'Right') or SameText(parts[3], 'Middle') then
          MouseClickAt(StrToInt(parts[1]), StrToInt(parts[2]), parts[3])
        else
          raise Exception.CreateFmt(
            'Error on line %d. Unknown mouse button "%s".',
            [lineNumber + 1, parts[3]]);
      end;

      bOK := True;
    end;

    CmdMouseWheel:
    begin
      // Only really useful for SL
      if Length(parts) <> 4 then
        raise Exception.CreateFmt(
          'Error on line %d. MouseWheel usage: MouseWheel <x> <y> <delta>',
          [lineNumber + 1]);

      ScrollMouseAt(StrToInt(parts[1]), StrToInt(parts[2]), StrToInt(parts[3]));
      bOK := True;
    end;

    CmdSetText:
    begin
      // Supported:
      // 1) SetText <Name|Index|ID:nnn|HWND:hex> <text>         (uses Default window name)
      // 2) SetText <Window> <Name|Index|ID:nnn|HWND:hex> <text>

      if Length(parts) < 3 then
        raise Exception.CreateFmt(
          'Error on line %d. SetText usage:' + CRLF + '  SetText <Name|Index|ID:nnn|HWND:hex> <text>' + CRLF + '  SetText <window> <Name|Index|ID:nnn|HWND:hex> <text>',
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
    end;

    CmdClose:
    begin
      if Length(parts) <> 2 then
        raise Exception.CreateFmt(
          'Error on line %d. Close usage: Close <window name>',
          [lineNumber + 1]);

      CloseWindowByCaption(ResolveAlias(parts[1]));
      bOK := True;
    end;

    CmdTypeText:
    begin
      if Length(parts) <> 2 then
        raise Exception.CreateFmt(
          'Error on line %d. TypeText usage: TypeText "some text"',
          [lineNumber + 1]);

      TypeText(parts[1]);
      bOK := True;
    end;

    CmdTypePassword:
    begin
      // This is used to type a password into an edit control. The password is encrypted in the script file, and this command decrypts it before typing.
      if ((Length(parts) <> 2) and (Length(parts) <> 4)) then
        raise Exception.CreateFmt(
          'Error on line %d. TypePassword usage: TypePassword "some encrypted text" | TypePassword "form|dialog" "control" "some encrypted text"',
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
          ShowTextDialog('Error', Format(
            'Error on line %d. No Edit control matched "%s" in dialog "%s".' + CRLF + CRLF + '%s',
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
    end;

    CmdPressKey:
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
        raise Exception.CreateFmt(
          'Error on line %d. PressKey usage: PressKey <key-or-chord>. e.g. PressKey A, PressKey Ctrl+Alt+F4, etc',
          [lineNumber + 1]);

      try
        SendChord(parts[1]);
        bOK := True;
      except
        on E: Exception do
          raise Exception.CreateFmt(
            'Error on line %d. PressKey failed: %s',
            [lineNumber + 1, E.Message]);
      end;
    end;

    CmdDumpHere:
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
    end;

    CmdSetPause:
    begin
      // Sets the default pause time between commands. This is a global setting that affects all subsequent commands.
      if Length(parts) = 2 then
      begin
        edtPauseTime.Text := parts[1];
        Application.ProcessMessages;
      end;

      bOK := True;
    end;

    CmdSleep:
    begin
      // Pause execution for a specified number of milliseconds. If no time is specified, defaults to 1000 ms (1 second).
      if Length(parts) <> 2 then
        Sleep(1000)
      else
        Sleep(StrToInt(parts[1]));
      bOK := True;
    end;

    CmdLaneTool:
    begin
      var FileName := 'C:\Apps\Inca\Bin\LaneTool.exe';
      if FileExists(FileName) then
        ShellExecute(0, 'open', PChar(FileName), nil, nil, SW_SHOWNORMAL)
      else
        ShowTextDialog('Error', Format('File %s was not found.', [FileName]), 500, 200);
    end;

    CmdLoad:
    begin
      // Loads a script file relative to the current script folder, the Clicker.exe folder, or C:\Scripts (in that order). The .script extension is optional.
      if Length(parts) <> 2 then
        raise Exception.CreateFmt(
          '%s:%d Load <scriptName>',
          [SourceName, lineNumber + 1]);

      ScriptName := parts[1];
      ScriptPath := ResolveScriptPath(ScriptName, SourceName);

      RunScriptFile(ScriptPath);  // RECURSION
      bOK := True;
    end;

    CmdStop:
    begin
      if Length(parts) <> 1 then
        raise Exception.CreateFmt(
          '%s:%d Stop does not accept arguments',
          [SourceName, lineNumber + 1]);

      FStopRequested := True;
      bOK := True;
    end;

    CmdAssert:
    begin
      // Usage:
      // Assert Button <token> "expected"
      // Assert Edit   <token> "expected"
      // Assert Button "Window Name" <token> "expected"
      // Assert Edit   "Window Name" <token> "expected"
      // Assert Color X Y "named color"
      // Assert Color X Y "#HEX_CODE"

      var Kind, WindowName, Token, Expected: string;

      if (Length(parts) = 5) and SameText(parts[1], 'Color') then
      begin

        const numberOfTimesToLoop = 10; //sometimes SCO uses animations, so we loop around to get a more accurate reading
        const numberOfTimesToMatch = 8; //we need to match at least 8 of the 10 samples (80%)
        const sleepTimeBetweenSamples = 100; //ms 10 * 100 = 1000 (1 second) total

        Kind := parts[1];
        var ScreenX, ScreenY: Integer;
        if not TryStrToInt(parts[2], ScreenX) or not TryStrToInt(parts[3], ScreenY) then
          raise Exception.CreateFmt(
            '%s:%d Assert Color coordinates must be integers',
            [SourceName, lineNumber + 1]);

        var ExpectedColor: TColor;
        if (Length(parts[4]) = 7) and (parts[4][1] = '#') then
        begin
          var HexValue: Integer;
          if not TryStrToInt('$' + Copy(parts[4], 2, 6), HexValue) then
            raise Exception.CreateFmt(
              '%s:%d Invalid Assert Color value "%s". Expected #RRGGBB or a color name',
              [SourceName, lineNumber + 1, parts[4]]);
          ExpectedColor := RGB((HexValue shr 16) and $FF, (HexValue shr 8) and $FF, HexValue and $FF);
        end
        else
        begin
          if SameText(parts[4], 'clYellowPNS') or SameText(parts[4], 'YellowPNS') then
            ExpectedColor := RGB(254, 216, 3)
          else
          begin
            try
              if SameText(Copy(parts[4], 1, 2), 'cl') then
                ExpectedColor := StringToColor(parts[4])
              else
                ExpectedColor := StringToColor('cl' + parts[4]);
            except
              on E: EConvertError do
                raise Exception.CreateFmt(
                  '%s:%d Unknown Assert Color name "%s"',
                  [SourceName, lineNumber + 1, parts[4]]);
            end;
          end;
        end;

        var ScreenDC := GetDC(0);
        if ScreenDC = 0 then
          raise Exception.CreateFmt(
            '%s:%d Unable to access the screen to check pixel color',
            [SourceName, lineNumber + 1]);

        var ActualColor: COLORREF;
        ActualColor := GetPixel(ScreenDC, ScreenX, ScreenY);

        try
          var MatchCount := 0;
          for var Sample := 1 to numberOfTimesToLoop do //loop around due to animations on SCO
          begin
            if ActualColor = CLR_INVALID then
              raise Exception.CreateFmt(
                '%s:%d Unable to read screen pixel at (%d, %d)',
                [SourceName, lineNumber + 1, ScreenX, ScreenY]);

            if ActualColor = COLORREF(ExpectedColor) then
              Inc(MatchCount);

            if MatchCount >= numberOfTimesToMatch then
              Break;

            if Sample < numberOfTimesToLoop then
              Sleep(sleepTimeBetweenSamples);
          end;

          if MatchCount < numberOfTimesToMatch then
            raise Exception.CreateFmt(
              '%s:%d Pixel color mismatch at (%d, %d). Expected %s in at least %d%% of samples; matched %d. Last sample was #%6.6x',
              [SourceName, lineNumber + 1, ScreenX, ScreenY, parts[4], Round(numberOfTimesToMatch / numberOfTimesToLoop * 100), MatchCount, ActualColor]);
        finally
          ReleaseDC(0, ScreenDC);
        end;

        bOK := True;
      end
      else if (Length(parts) = 4) and not SameText(parts[1], 'Color') then
      begin
        // Assert Button <token> "expected"
        Kind       := parts[1];
        WindowName := defaultWindowName.Text;
        Token      := ResolveAlias(parts[2]);
        Expected   := parts[3];
      end
      else if Length(parts) = 5 then
      begin
        // Assert Button "Window Name" <token> "expected"
        Kind       := parts[1];
        WindowName := ResolveAlias(parts[2]);
        Token      := ResolveAlias(parts[3]);
        Expected   := parts[4];
      end
      else
        raise Exception.CreateFmt(
          '%s:%d Assert usage:' + CRLF +
          '  Assert <Button|Edit> <token> "expected"' + CRLF +
          '  Assert <Button|Edit> "Window Name" <token> "expected"' + CRLF +
          '  Assert Color <x> <y> <#RRGGBB|colorName>',
          [SourceName, lineNumber + 1]);

      if not SameText(Kind, 'Color') then
      begin
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
            '%s:%d Unknown Assert target "%s". Use "Button" or "Edit"',
            [SourceName, lineNumber + 1, Kind]);
      end;
    end;

    CmdAlias:
    begin
      // Usage:
      // Alias <name> <value>
      // Alias <name> <x> <y>

      if (Length(parts) <> 3) and (Length(parts) <> 4) then
        raise Exception.CreateFmt(
          '%s:%d Alias usage: Alias <name> <value> or Alias <name> <x> <y>',
          [SourceName, lineNumber + 1]);

      var AliasName := parts[1];
      var AliasValue: string;
      if Length(parts) = 3 then
        AliasValue := parts[2]
      else
      begin
        var ScreenX, ScreenY: Integer;
        if not TryStrToInt(parts[2], ScreenX) or
          not TryStrToInt(parts[3], ScreenY) then
          raise Exception.CreateFmt(
            '%s:%d Coordinate alias "%s" requires integer X and Y coordinates',
            [SourceName, lineNumber + 1, AliasName]);

        AliasValue := Format('%s%d,%d',
          [MOUSE_POINT_ALIAS_PREFIX, ScreenX, ScreenY]);
      end;

      // Prevent accidental overwrite
      if FAliases.IndexOfName(AliasName) >= 0 then
        raise Exception.CreateFmt(
          '%s:%d Alias "%s" already defined',
          [SourceName, lineNumber + 1, AliasName]);

      FAliases.Values[AliasName] := AliasValue;
      bOK := True;
    end;

    else
    begin
      raise Exception.CreateFmt(
        '%s:%d Unknown command "%s"',
        [SourceName, lineNumber + 1, parts[0]]);
    end;
  end;

  Result := bOK;

end;

/// <summary>
/// Runs a script file by loading its contents and executing the commands line by line.
/// This function handles the reading of the script file and delegates the execution to RunScriptLines.
/// </summary>
/// <param name="FileName" type="string">The path to the script file to run.</param>
procedure TForm1.RunScriptFile(FileName: string);
var
  Lines: TStringList;
begin
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
/// <summary>
/// Runs the script currently loaded in the memo editor. This is the main entry point for executing user-defined scripts.
/// </summary>
/// <param name="Sender" type="TObject">The object that triggered the event.</param>
procedure TForm1.btnGoClick(Sender: TObject);
var
  Script: TStringList;
begin
  btnGo.Enabled := False; //stop infinite loop and "PressKey Enter" from clicking this button because it is enabled and active
  FStopRequested := False;
  FAliases.Clear;
  Script := TStringList.Create;
  try
    try
      Script.Text := mmoScript.Text;

      // Expand all Load commands first
      ExpandLoadCommands(Script, FScriptFilename);

      // Optional: reflect expansion back into editor
      mmoScript.Text := Script.Text;

      // Now execute
      RunScriptLines(Script, 'MainScript');
    finally
      Script.Free;
      btnGo.Enabled := True;
    end;
  except
    on E: Exception do
    begin
      if not ConsoleMode then
        raise;
      ConsoleExitCode := 1;
      WriteConsoleText('Fatal error: ' + E.Message + sLineBreak);
    end;
  end;
end;

end.