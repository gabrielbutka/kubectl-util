unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, StdCtrls, LCLType, StrUtils, RegExpr, Process;

type

  { TfrmPrincipal }

  TfrmPrincipal = class(TForm)
    btnVisualizarLog: TButton;
    btnSalvarLog: TButton;
    btnDescribe: TButton;
    btnConectarBash: TButton;
    btnConectarDB: TButton;
    cbxContext: TComboBox;
    cbxNameSpace: TComboBox;
    cbxPod: TComboBox;
    cbxLog: TComboBox;
    lblLog: TLabel;
    lblPod: TLabel;
    lblNameSpace: TLabel;
    lblContext: TLabel;
    SaveDialog: TSaveDialog;
    procedure btnConectarBashClick(Sender: TObject);
    procedure btnConectarDBClick(Sender: TObject);
    procedure btnDescribeClick(Sender: TObject);
    procedure btnSalvarLogClick(Sender: TObject);
    procedure btnVisualizarLogClick(Sender: TObject);
    procedure cbxContextChange(Sender: TObject);
    procedure cbxLogChange(Sender: TObject);
    procedure cbxNameSpaceChange(Sender: TObject);
    procedure cbxPodChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    function ExecutarComando(Comando: string): TStringList;
    procedure ExecutarComandoSemRetorno(Comando: string; Keep: boolean = False);
  end;

var
  frmPrincipal: TfrmPrincipal;

const
  CMD_GET_CONTEXTS = 'kubectl config get-contexts -o=name';
  CMD_CURRENT_CONTEXT = 'kubectl config current-context';
  CMD_USE_CONTEXT = 'kubectl config use-context %s';
  CMD_GET_NAMESPACES = 'kubectl get namespaces -o=custom-columns=:metadata.name,:status.phase';
  CMD_GET_PODS = 'kubectl get pods --namespace %s -o=custom-columns=:metadata.name,:status.phase';
  CMD_GET_LOGS = 'kubectl exec --namespace %s %s -- find -name *.log';
  CMD_DESCRIBE_SIMPLE = 'kubectl get pod --namespace %s %s';
  CMD_DESCRIBE_COMPLETE = 'kubectl describe pods --namespace %s %s';
  CMD_LOG_VIEW = 'kubectl exec --namespace %s %s -- tail -f --bytes=1G %s';
  CMD_LOG_SAVE = 'kubectl exec --namespace %s %s -- tail --bytes=1G %s';
  CMD_CONECT_DB = 'kubectl port-forward --namespace %s %s %d:5432';
  CMD_CONECT_BASH = 'kubectl exec --namespace %s -it %s bash';

  BUFFER_SIZE = 4096;

  {$IFDEF Windows}
    CONECT_DB_DEFAULT_PORT = '666';
  {$ENDIF Windows}

  {$IFDEF Unix}
    CONECT_DB_DEFAULT_PORT = '6666';
  {$ENDIF Unix}

implementation

{$R *.lfm}

{ TfrmPrincipal }

procedure TfrmPrincipal.FormCreate(Sender: TObject);
var
  Resultado: TStringList;
begin
  Resultado := ExecutarComando(CMD_GET_CONTEXTS);
  cbxContext.Items.AddStrings(Resultado);
  FreeAndNil(Resultado);

  Resultado := ExecutarComando(CMD_CURRENT_CONTEXT);
  cbxContext.ItemIndex := cbxContext.Items.IndexOf(Trim(Resultado.Text));
  cbxContextChange(Sender);

  {$IFDEF Windows}
    cbxNameSpace.AutoDropDown := True;
  {$ENDIF Windows}

  {$IFDEF Unix}
    cbxNameSpace.AutoDropDown := False;
  {$ENDIF Unix}
end;

procedure TfrmPrincipal.cbxContextChange(Sender: TObject);
var
  Resultado: TStringList;
  Context, NameSpace: string;
  i: integer;
begin
  Context := cbxContext.Text;

  if Context = '' then
    Exit;

  Resultado := ExecutarComando(Format(CMD_USE_CONTEXT, [Context]));
  if Resultado.Count > 0 then
    Application.MessageBox(PChar(Resultado.Text), 'Informação', MB_ICONINFORMATION);
  FreeAndNil(Resultado);

  cbxNameSpace.Clear;
  cbxPod.Clear;

  Resultado := ExecutarComando(CMD_GET_NAMESPACES);

  for i := Resultado.Count - 1 downto 0 do
  begin
    NameSpace := Resultado[i];

    if Trim(NameSpace) = '' then
    begin
      Resultado.Delete(i);
      Continue;
    end;

    if Pos('Active', NameSpace) = 0 then
    begin
      Resultado.Delete(i);
      Continue;
    end;

    Resultado[i] := Trim(ReplaceStr(Resultado[i], 'Active', ''));
  end;

  cbxNameSpace.Items.AddStrings(Resultado);
  cbxNameSpace.Enabled := Resultado.Count > 0;
  FreeAndNil(Resultado);

  cbxNameSpaceChange(Sender);
  cbxPodChange(Sender);
  cbxLogChange(Sender);
end;

procedure TfrmPrincipal.cbxNameSpaceChange(Sender: TObject);
var
  Resultado: TStringList;
  NameSpace, Pod: string;
  i: integer;
begin
  cbxPod.Clear;
  NameSpace := cbxNameSpace.Text;

  if NameSpace <> '' then
    Resultado := ExecutarComando(Format(CMD_GET_PODS, [NameSpace]))
  else
    Resultado := TStringList.Create;

  for i := Resultado.Count - 1 downto 0 do
  begin
    Pod := Resultado[i];

    if Trim(Pod) = '' then
    begin
      Resultado.Delete(i);
      Continue;
    end;

    if Pos('Running', Pod) = 0 then
    begin
      Resultado.Delete(i);
      Continue;
    end;

    Resultado[i] := Trim(ReplaceStr(Resultado[i], 'Running', ''));
  end;

  cbxPod.Items.AddStrings(Resultado);
  cbxPod.Enabled := Resultado.Count > 0;
  FreeAndNil(Resultado);

  cbxPodChange(Sender);
  cbxLogChange(Sender);
end;

procedure TfrmPrincipal.cbxPodChange(Sender: TObject);
var
  Resultado: TStringList;
  NameSpace, Pod, Log: string;
  i: integer;
begin
  cbxLog.Clear;
  NameSpace := cbxNameSpace.Text;
  Pod := cbxPod.Text;

  btnDescribe.Enabled := Pod <> '';
  btnConectarDB.Enabled := Pos('postgres', Pod) > 0;
  btnConectarBash.Enabled := Pod <> '';

  if (NameSpace <> '') and (Pod <> '') then
    Resultado := ExecutarComando(Format(CMD_GET_LOGS, [NameSpace, Pod]))
  else
    Resultado := TStringList.Create;

  for i := Resultado.Count - 1 downto 0 do
  begin
    Log := Resultado[i];
    Log := ReplaceStr(Log, './', '');
    Resultado[i] := Log;
  end;

  cbxLog.Items.AddStrings(Resultado);
  cbxLog.Enabled := Resultado.Count > 0;
  FreeAndNil(Resultado);

  cbxLogChange(Sender);
end;

procedure TfrmPrincipal.cbxLogChange(Sender: TObject);
begin
  btnVisualizarLog.Enabled := cbxLog.ItemIndex > -1;
  btnSalvarLog.Enabled := cbxLog.ItemIndex > -1;
end;

procedure TfrmPrincipal.btnVisualizarLogClick(Sender: TObject);
var
  NameSpace, Pod, Log: string;
begin
  NameSpace := cbxNameSpace.Text;
  Pod := cbxPod.Text;
  Log := cbxLog.Text;
  ExecutarComandoSemRetorno(Format(CMD_LOG_VIEW, [NameSpace, Pod, Log]));
end;

procedure TfrmPrincipal.btnSalvarLogClick(Sender: TObject);
var
  Resultado: TStringList;
  NameSpace, Pod, Log: string;
begin
  NameSpace := cbxNameSpace.Text;
  Pod := cbxPod.Text;
  Log := cbxLog.Text;

  Resultado := ExecutarComando(Format(CMD_LOG_SAVE, [NameSpace, Pod, Log]));
  SaveDialog.FileName := ReplaceStr(Log, '/', '-');
  if (SaveDialog.Execute) and (SaveDialog.FileName <> '') then
    Resultado.SaveToFile(SaveDialog.FileName);
  FreeAndNil(Resultado);
end;

procedure TfrmPrincipal.btnDescribeClick(Sender: TObject);
var
  NameSpace, Pod: string;
begin
  NameSpace := cbxNameSpace.Text;
  Pod := cbxPod.Text;
  ExecutarComandoSemRetorno(Format(CMD_DESCRIBE_COMPLETE, [NameSpace, Pod]), True);
end;

procedure TfrmPrincipal.btnConectarBashClick(Sender: TObject);
var
  NameSpace, Pod: string;
begin
  NameSpace := cbxNameSpace.Text;
  Pod := cbxPod.Text;
  ExecutarComandoSemRetorno(Format(CMD_CONECT_BASH, [NameSpace, Pod]));
end;

procedure TfrmPrincipal.btnConectarDBClick(Sender: TObject);
var
  Porta, NameSpace, Pod: string;
  RegExpr: TRegExpr;
begin
  Porta := CONECT_DB_DEFAULT_PORT;

  if not InputQuery(Caption, 'Informe a porta local: ', Porta) then
    Exit;

  RegExpr := TRegExpr.Create('\d{2,4}');
  if not RegExpr.Exec(Porta) then
  begin
    Application.MessageBox('A porta informada é inválida!', 'Erro', MB_ICONERROR);
    Exit;
  end;
  FreeAndNil(RegExpr);

  NameSpace := cbxNameSpace.Text;
  Pod := cbxPod.Text;
  ExecutarComandoSemRetorno(Format(CMD_CONECT_DB, [NameSpace, Pod, StrToInt(Porta)]));
end;

function TfrmPrincipal.ExecutarComando(Comando: string): TStringList;
var
  Process: TProcess;
  OutputStream: TStream;
  BytesRead: longint;
  Buffer: array[1..BUFFER_SIZE] of byte;
begin
  Process := TProcess.Create(nil);
  {$IFDEF Windows}
    Process.Executable := 'cmd.exe';
    Process.ShowWindow := swoHIDE;
    Process.Parameters.Add('/c');
    Process.Parameters.Add(Comando);
  {$ENDIF Windows}

  {$IFDEF Unix}
    Process.Executable := 'bash';
    Process.Parameters.Add('-c');
    Process.Parameters.Add(Comando);
  {$ENDIF Unix}

  Process.Options := [poUsePipes];
  Process.Execute;

  OutputStream := TMemoryStream.Create;

  repeat
    BytesRead := Process.Output.Read(Buffer, BUFFER_SIZE);
    OutputStream.Write(Buffer, BytesRead)
  until BytesRead = 0;

  Process.Free;

  Result := TStringList.Create;
  OutputStream.Position := 0;
  Result.LoadFromStream(OutputStream);

  OutputStream.Free;
end;

procedure TfrmPrincipal.ExecutarComandoSemRetorno(Comando: string; Keep: boolean);
var
   Process: TProcess;
begin
  Process := TProcess.Create(nil);

  {$IFDEF Windows}
    Process.Executable := 'cmd.exe';
    Process.Parameters.Add(IfThen(Keep, '/k', '/c'));
    Process.Parameters.Add(Comando);
  {$ENDIF Windows}

  {$IFDEF Unix}
    Process.Executable := 'xterm';
    if (Keep) then
       Process.Parameters.Add('-hold');
    Process.Parameters.Add('-e');
    Process.Parameters.Add(Comando);
  {$ENDIF Unix}

  Process.Execute;
  Process.Free;
end;

end.
