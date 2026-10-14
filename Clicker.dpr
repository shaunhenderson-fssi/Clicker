program Clicker;

uses
  System.SysUtils,
  Vcl.Forms,
  TClicker in 'TClicker.pas' {Form1};

{$R *.res}

type
  TExceptionHandler = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;

procedure TExceptionHandler.HandleException(Sender: TObject; E: Exception);
begin
  ConsoleExitCode := 1;
  if ConsoleMode then
    WriteConsoleText('Fatal error: ' + E.Message + sLineBreak)
  else
    Application.ShowException(E);
end;

var
  ExceptionHandler: TExceptionHandler;
begin
  ConsoleMode := (ParamCount >= 1) and SameText(ParamStr(1), '--console');
  ConsoleExitCode := 0;
  ExceptionHandler := TExceptionHandler.Create;
  try
    try
      if ConsoleMode then
      begin
        InitializeConsoleOutput;
        if ParamCount <> 2 then
          raise Exception.Create('Usage: Clicker.exe --console <script-file>');
      end;

      Application.Initialize;
      Application.MainFormOnTaskbar := True;
      Application.ShowMainForm := not ConsoleMode;
      Application.OnException := ExceptionHandler.HandleException;
      Application.CreateForm(TForm1, Form1);
      if not ConsoleMode then
        Application.Run;
    except
      on E: Exception do
      begin
        ConsoleExitCode := 1;
        if ConsoleMode then
          WriteConsoleText('Fatal error: ' + E.Message + sLineBreak)
        else
          Application.ShowException(E);
      end;
    end;
  finally
    ExceptionHandler.Free;
  end;
  System.ExitCode := ConsoleExitCode;
end.
