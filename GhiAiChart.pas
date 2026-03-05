unit GhiAiChart;

{
  TGhiAiChart - Componente Delphi para exibir gráfico a partir de TFDQuery
  com análise via IA (OpenAI). Parte do pacote GhiAI.

  Uso:
  1. Vincule Query (TFDQuery com dados)
  2. Defina EixoX e EixoY (nomes das colunas)
  3. Vincule Panel (onde o gráfico será renderizado)
  4. Defina ApiUrl e ApiKey para análise IA
  5. Chame Executar - exibe o gráfico e botão "Analisar com IA"
}

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.Math,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  Data.DB, FireDAC.Comp.Client, VclTee.TeEngine, VclTee.TeeProcs, VclTee.Chart, VclTee.Series;

type
  /// <summary>Tipo de gráfico a exibir</summary>
  TGhiAiChartTipo = (
    ctBarras,
    ctLinhas,
    ctPizza
  );

  /// <summary>Modo de cores do grafico</summary>
  TGhiAiChartCores = (
    ccSortidas,  /// Cores variadas (vibrantes)
    ccSuaves,    /// Cores variadas (suaves/pastel)
    ccSolida     /// Cor unica para toda a serie
  );

  TGhiAiChart = class(TComponent)
  private
    FQuery: TFDQuery;
    FEixoX: string;
    FEixoY: string;
    FTipoGrafico: TGhiAiChartTipo;
    FCores: TGhiAiChartCores;
    FCorSerie: TColor;
    FPanel: TPanel;
    FApiUrl: string;
    FApiKey: string;
    FModel: string;
    FTimeout: Integer;
    FLastError: string;
    FChartPanel: TPanel;
    FChart: TChart;
    FBtnAnalisar: TButton;
    procedure SetQuery(const Value: TFDQuery);
    procedure SetPanel(const Value: TPanel);
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoBtnAnalisarClick(Sender: TObject);
    procedure ExecutarAnaliseIA(const APrompt: string);
    procedure PopularChart(const AData: TList<TPair<string, Double>>);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Obtém dados da query, monta o gráfico e renderiza no Panel</summary>
    procedure Executar;
    /// <summary>Retorna as colunas disponíveis na Query (para popular combos)</summary>
    function GetColunasDisponiveis: TArray<string>;
    /// <summary>Exibe diálogo para selecionar EixoX e EixoY em combos</summary>
    function ConfigurarEixos: Boolean;
    property LastError: string read FLastError;
  published
    /// <summary>Query com os dados (TFDQuery)</summary>
    property Query: TFDQuery read FQuery write SetQuery;
    /// <summary>Nome da coluna para eixo X (labels)</summary>
    property EixoX: string read FEixoX write FEixoX;
    /// <summary>Nome da coluna para eixo Y (valores)</summary>
    property EixoY: string read FEixoY write FEixoY;
    /// <summary>Tipo de grafico: Barras, Linhas ou Pizza</summary>
    property TipoGrafico: TGhiAiChartTipo read FTipoGrafico write FTipoGrafico default ctBarras;
    /// <summary>Cores: Sortidas (vibrantes), Suaves (pastel) ou Solida</summary>
    property Cores: TGhiAiChartCores read FCores write FCores default ccSortidas;
    /// <summary>Cor unica quando Cores = ccSolida</summary>
    property CorSerie: TColor read FCorSerie write FCorSerie default clNavy;
    /// <summary>Panel onde o grafico sera renderizado</summary>
    property Panel: TPanel read FPanel write SetPanel;
    /// <summary>URL da API OpenAI</summary>
    property ApiUrl: string read FApiUrl write FApiUrl;
    /// <summary>Chave da API OpenAI</summary>
    property ApiKey: string read FApiKey write FApiKey;
    /// <summary>Modelo OpenAI (ex: gpt-4o-mini)</summary>
    property Model: string read FModel write FModel;
    /// <summary>Timeout em ms</summary>
    property Timeout: Integer read FTimeout write FTimeout default 60000;
  end;

procedure Register;

implementation

uses
  IdHTTP, IdSSLOpenSSL, System.JSON;

procedure Register;
begin
  RegisterComponents('Ghi AI', [TGhiAiChart]);
end;

{ TGhiAiChart }

constructor TGhiAiChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FQuery := nil;
  FPanel := nil;
  FEixoX := '';
  FEixoY := '';
  FTipoGrafico := ctBarras;
  FCores := ccSortidas;
  FCorSerie := clNavy;
  FApiUrl := 'https://api.openai.com/v1/chat/completions';
  FApiKey := '';
  FModel := 'gpt-4o-mini';
  FTimeout := 60000;
  FLastError := '';
  FChartPanel := nil;
  FChart := nil;
  FBtnAnalisar := nil;
end;

destructor TGhiAiChart.Destroy;
begin
  SetPanel(nil);
  inherited;
end;

procedure TGhiAiChart.SetQuery(const Value: TFDQuery);
begin
  if FQuery <> Value then
    FQuery := Value;
end;

const
  CPaletaSortidas: array[0..11] of TColor = (
    $00D77800, $0047AB, $00C853, $E63946, $9B59B6, $F39C12,
    $1ABC9C, $95A5A6, $3498DB, $E74C3C, $2ECC71, $F1C40F
  );
  CPaletaSuaves: array[0..11] of TColor = (
    $98FB98, $E6D8AD, $C4E4FF, $FAE6E6, $B9DAFF, $F0FFF0,
    $DCF5DC, $E1E4FF, $FFE0E0, $F5F0FF, $8CE6F0, $DD9DDD
  );

function ObterCorGrafico(const ACores: TGhiAiChartCores; AIndex: Integer; ACorSerie: TColor): TColor;
begin
  case ACores of
    ccSortidas: Result := CPaletaSortidas[AIndex mod Length(CPaletaSortidas)];
    ccSuaves:   Result := CPaletaSuaves[AIndex mod Length(CPaletaSuaves)];
    else        Result := ACorSerie;
  end;
end;

procedure TGhiAiChart.PopularChart(const AData: TList<TPair<string, Double>>);
var
  LSeries: TChartSeries;
  I: Integer;
  LTotal: Double;
  LCor: TColor;
  LUsarPaleta: Boolean;
begin
  if (FChart = nil) or (AData.Count = 0) then Exit;

  FChart.RemoveAllSeries;
  FChart.Legend.Visible := True;
  LUsarPaleta := (FCores in [ccSortidas, ccSuaves]);

  case FTipoGrafico of
    ctBarras:
    begin
      LSeries := TBarSeries.Create(FChart);
      LSeries.Title := FEixoY;
      LSeries.ColorEachPoint := LUsarPaleta;
      FChart.AddSeries(LSeries);
      for I := 0 to AData.Count - 1 do
      begin
        LCor := ObterCorGrafico(FCores, I, FCorSerie);
        TBarSeries(LSeries).Add(AData[I].Value, Copy(AData[I].Key, 1, 30), LCor);
      end;
      FChart.Axes.Bottom.LabelsAngle := 90;
    end;

    ctLinhas:
    begin
      LSeries := TLineSeries.Create(FChart);
      LSeries.Title := FEixoY;
      LSeries.ColorEachPoint := LUsarPaleta;
      if FCores = ccSolida then
        LSeries.Color := FCorSerie
      else
        LSeries.Color := ObterCorGrafico(FCores, 0, FCorSerie);
      FChart.AddSeries(LSeries);
      for I := 0 to AData.Count - 1 do
      begin
        LCor := ObterCorGrafico(FCores, I, FCorSerie);
        TLineSeries(LSeries).AddXY(I, AData[I].Value, Copy(AData[I].Key, 1, 30), LCor);
      end;
      FChart.Axes.Bottom.LabelsAngle := 90;
      FChart.Axes.Bottom.Items.Clear;
      for I := 0 to AData.Count - 1 do
        FChart.Axes.Bottom.Items.Add(I, Copy(AData[I].Key, 1, 30));
    end;

    ctPizza:
    begin
      LSeries := TPieSeries.Create(FChart);
      LSeries.Title := FEixoY;
      LSeries.ColorEachPoint := LUsarPaleta;
      FChart.AddSeries(LSeries);
      LTotal := 0;
      for I := 0 to AData.Count - 1 do
        LTotal := LTotal + AData[I].Value;
      if LTotal <= 0 then LTotal := 1;
      for I := 0 to AData.Count - 1 do
      begin
        LCor := ObterCorGrafico(FCores, I, FCorSerie);
        TPieSeries(LSeries).Add(AData[I].Value, Copy(AData[I].Key, 1, 30), LCor);
      end;
    end;
  end;
end;

procedure TGhiAiChart.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FPanel) then
  begin
    FPanel := nil;
    FChart := nil;
    FChartPanel := nil;
    FBtnAnalisar := nil;
  end;
end;

procedure TGhiAiChart.SetPanel(const Value: TPanel);
begin
  if FPanel <> Value then
  begin
    if FPanel <> nil then
      FPanel.RemoveFreeNotification(Self);
    if FChart <> nil then
    begin
      FChart.Parent := nil;
      FChart.Free;
      FChart := nil;
    end;
    if FChartPanel <> nil then
    begin
      FChartPanel.Parent := nil;
      FChartPanel.Free;
      FChartPanel := nil;
    end;
    if FBtnAnalisar <> nil then
    begin
      FBtnAnalisar.Parent := nil;
      FBtnAnalisar.Free;
      FBtnAnalisar := nil;
    end;
    FPanel := Value;
    if FPanel <> nil then
      FPanel.FreeNotification(Self);
  end;
end;

function TGhiAiChart.GetColunasDisponiveis: TArray<string>;
var
  LList: TList<string>;
  I: Integer;
begin
  Result := nil;
  if (FQuery = nil) or not FQuery.Active then Exit;
  LList := TList<string>.Create;
  try
    for I := 0 to FQuery.FieldCount - 1 do
      LList.Add(FQuery.Fields[I].FieldName);
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TGhiAiChart.ConfigurarEixos: Boolean;
var
  LForm: TForm;
  LLabelX, LLabelY: TLabel;
  LComboX, LComboY: TComboBox;
  LBtnOk, LBtnCancel: TButton;
  LCols: TArray<string>;
  I: Integer;
begin
  Result := False;
  if FQuery = nil then
  begin
    ShowMessage('Vincule a Query antes de configurar.');
    Exit;
  end;
  if not FQuery.Active then
  begin
    ShowMessage('Abra a Query antes de configurar os eixos.');
    Exit;
  end;

  LCols := GetColunasDisponiveis;
  if Length(LCols) = 0 then
  begin
    ShowMessage('Nenhuma coluna encontrada na Query.');
    Exit;
  end;

  LForm := TForm.Create(nil);
  try
    LForm.Caption := 'Configurar Eixos do Gráfico';
    LForm.Width := 350;
    LForm.Height := 180;
    LForm.Position := poScreenCenter;
    LForm.BorderStyle := bsDialog;

    LLabelX := TLabel.Create(LForm);
    LLabelX.Parent := LForm;
    LLabelX.Caption := 'Eixo X (labels):';
    LLabelX.Left := 16;
    LLabelX.Top := 20;

    LComboX := TComboBox.Create(LForm);
    LComboX.Parent := LForm;
    LComboX.Left := 16;
    LComboX.Top := 40;
    LComboX.Width := LForm.ClientWidth - 32;
    LComboX.Style := csDropDownList;
    for I := 0 to High(LCols) do
      LComboX.Items.Add(LCols[I]);
    if LComboX.Items.IndexOf(FEixoX) >= 0 then
      LComboX.ItemIndex := LComboX.Items.IndexOf(FEixoX)
    else if LComboX.Items.Count > 0 then
      LComboX.ItemIndex := 0;

    LLabelY := TLabel.Create(LForm);
    LLabelY.Parent := LForm;
    LLabelY.Caption := 'Eixo Y (valores):';
    LLabelY.Left := 16;
    LLabelY.Top := 72;

    LComboY := TComboBox.Create(LForm);
    LComboY.Parent := LForm;
    LComboY.Left := 16;
    LComboY.Top := 92;
    LComboY.Width := LForm.ClientWidth - 32;
    LComboY.Style := csDropDownList;
    for I := 0 to High(LCols) do
      LComboY.Items.Add(LCols[I]);
    if LComboY.Items.IndexOf(FEixoY) >= 0 then
      LComboY.ItemIndex := LComboY.Items.IndexOf(FEixoY)
    else if LComboY.Items.Count > 1 then
      LComboY.ItemIndex := 1
    else if LComboY.Items.Count > 0 then
      LComboY.ItemIndex := 0;

    LBtnOk := TButton.Create(LForm);
    LBtnOk.Parent := LForm;
    LBtnOk.Caption := 'OK';
    LBtnOk.ModalResult := mrOk;
    LBtnOk.Default := True;
    LBtnOk.Left := LForm.ClientWidth - 170;
    LBtnOk.Top := 130;
    LBtnOk.Width := 75;

    LBtnCancel := TButton.Create(LForm);
    LBtnCancel.Parent := LForm;
    LBtnCancel.Caption := 'Cancelar';
    LBtnCancel.ModalResult := mrCancel;
    LBtnCancel.Left := LForm.ClientWidth - 85;
    LBtnCancel.Top := 130;
    LBtnCancel.Width := 75;

    if LForm.ShowModal = mrOk then
    begin
      if LComboX.ItemIndex >= 0 then FEixoX := LComboX.Items[LComboX.ItemIndex];
      if LComboY.ItemIndex >= 0 then FEixoY := LComboY.Items[LComboY.ItemIndex];
      Result := True;
    end;
  finally
    LForm.Free;
  end;
end;

procedure TGhiAiChart.Executar;
var
  LChartPanel: TPanel;
  LBtn: TButton;
  LData: TList<TPair<string, Double>>;
  LFieldX, LFieldY: TField;
  LMaxVal: Double;
  I: Integer;
  LLabel: string;
  LVal: Double;
begin
  FLastError := '';
  if FPanel = nil then
  begin
    FLastError := 'Panel não vinculado';
    Exit;
  end;
  if FQuery = nil then
  begin
    FLastError := 'Query não vinculada';
    Exit;
  end;
  if Trim(FEixoX) = '' then
  begin
    FLastError := 'EixoX não definido';
    Exit;
  end;
  if Trim(FEixoY) = '' then
  begin
    FLastError := 'EixoY não definido';
    Exit;
  end;

  LFieldX := FQuery.FindField(FEixoX);
  LFieldY := FQuery.FindField(FEixoY);
  if (LFieldX = nil) or (LFieldY = nil) then
  begin
    FLastError := 'Coluna EixoX ou EixoY não encontrada na Query';
    Exit;
  end;

  LData := TList<TPair<string, Double>>.Create;
  try
    FQuery.DisableControls;
    try
      FQuery.First;
      while not FQuery.Eof do
      begin
        LLabel := LFieldX.AsString;
        LVal := 0;
        if LFieldY.IsNull = False then
          LVal := LFieldY.AsFloat;
        LData.Add(TPair<string, Double>.Create(LLabel, LVal));
        FQuery.Next;
      end;
    finally
      FQuery.EnableControls;
    end;

    if LData.Count = 0 then
    begin
      FLastError := 'Nenhum dado na Query';
      Exit;
    end;

    if FChart <> nil then
      FChart.Free;
    if FChartPanel <> nil then
      FChartPanel.Free;
    if FBtnAnalisar <> nil then
      FBtnAnalisar.Free;

    LChartPanel := TPanel.Create(Self);
    LChartPanel.Parent := FPanel;
    LChartPanel.Align := alClient;
    LChartPanel.BevelOuter := bvNone;
    LChartPanel.Color := clWhite;
    FChartPanel := LChartPanel;

    FChart := TChart.Create(Self);
    FChart.Parent := LChartPanel;
    FChart.Align := alClient;
    FChart.Color := clWhite;
    FChart.View3D := False;
    FChart.Legend.Alignment := laBottom;

    LBtn := TButton.Create(Self);
    LBtn.Parent := FPanel;
    LBtn.Caption := 'Analisar com IA';
    LBtn.Left := FPanel.Width - 120;
    LBtn.Top := 8;
    LBtn.Width := 110;
    LBtn.Height := 25;
    LBtn.Anchors := [akTop, akRight];
    LBtn.OnClick := DoBtnAnalisarClick;
    FBtnAnalisar := LBtn;

    PopularChart(LData);
  finally
    LData.Free;
  end;
end;

procedure TGhiAiChart.DoBtnAnalisarClick(Sender: TObject);
var
  LPrompt: string;
  LForm: TForm;
  LEdit: TEdit;
  LBtn: TButton;
  LResult: Boolean;
begin
    LForm := TForm.Create(nil);
  try
    LForm.Caption := 'An'#$00E1'lise com IA';
    LForm.Width := 450;
    LForm.Height := 200;
    LForm.Position := poScreenCenter;
    LForm.BorderStyle := bsDialog;

    LEdit := TEdit.Create(LForm);
    LEdit.Parent := LForm;
    LEdit.Left := 16;
    LEdit.Top := 24;
    LEdit.Width := LForm.ClientWidth - 32;
    LEdit.Text := 'Analise os dados do gr'#$00E1'fico e destaque os principais insights';

    LBtn := TButton.Create(LForm);
    LBtn.Parent := LForm;
    LBtn.Caption := 'Enviar';
    LBtn.Left := LForm.ClientWidth - 100;
    LBtn.Top := 64;
    LBtn.Width := 80;
    LBtn.ModalResult := mrOk;
    LBtn.Default := True;

    LResult := (LForm.ShowModal = mrOk);
    if LResult then
      LPrompt := Trim(LEdit.Text);
  finally
    LForm.Free;
  end;

  if LResult and (LPrompt <> '') then
    ExecutarAnaliseIA(LPrompt);
end;

procedure TGhiAiChart.ExecutarAnaliseIA(const APrompt: string);
var
  LHTTP: TIdHTTP;
  LIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LRequestStream: TStringStream;
  LResponseStream: TMemoryStream;
  LResponse: string;
  LBytes: TBytes;
  LRoot, LMsgSystem, LMsgUser: TJSONObject;
  LMessages: TJSONArray;
  LContent, LRequestJSON, LJsonDados: string;
  LChoices: TJSONArray;
  LChoice, LMessage: TJSONObject;
  LContentVal: TJSONValue;
  LEnc: TEncoding;
  LFieldX, LFieldY: TField;
  LForm: TForm;
  LMemo: TMemo;
  LBtn: TButton;
begin
  FLastError := '';
  if (FQuery = nil) or (Trim(FApiUrl) = '') or (Trim(FApiKey) = '') then
  begin
    FLastError := 'Query, ApiUrl e ApiKey devem estar configurados';
    Exit;
  end;

  LFieldX := FQuery.FindField(FEixoX);
  LFieldY := FQuery.FindField(FEixoY);
  if (LFieldX = nil) or (LFieldY = nil) then Exit;

  LJsonDados := '{"eixoX":"' + FEixoX + '","eixoY":"' + FEixoY + '","dados":[';
  FQuery.DisableControls;
  try
    FQuery.First;
    while not FQuery.Eof do
    begin
      if not FQuery.Bof then LJsonDados := LJsonDados + ',';
      LJsonDados := LJsonDados + '{"' + FEixoX + '":"' +
        StringReplace(StringReplace(LFieldX.AsString, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) +
        '","' + FEixoY + '":' + StringReplace(FormatFloat('0.##', LFieldY.AsFloat), ',', '.', []) + '}';
      FQuery.Next;
    end;
  finally
    FQuery.EnableControls;
  end;
  LJsonDados := LJsonDados + ']}';

  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('model', FModel);
    LRoot.AddPair('temperature', TJSONNumber.Create(0.5));
    LRoot.AddPair('max_tokens', TJSONNumber.Create(2000));

    LMessages := TJSONArray.Create;
    LContent := 'Você é um analista de dados. Analise os dados do gráfico conforme a solicitação do usuário. ' +
      'Retorne a análise em texto objetivo e bem formatado.';
    LMsgSystem := TJSONObject.Create;
    LMsgSystem.AddPair('role', 'system');
    LMsgSystem.AddPair('content', LContent);
    LMessages.AddElement(LMsgSystem);

    LMsgUser := TJSONObject.Create;
    LMsgUser.AddPair('role', 'user');
    LMsgUser.AddPair('content', 'Dados do gráfico:' + sLineBreak + LJsonDados + sLineBreak + sLineBreak +
      'Solicitação: ' + APrompt);
    LMessages.AddElement(LMsgUser);

    LRoot.AddPair('messages', LMessages);
    LRequestJSON := LRoot.ToJSON;
  finally
    LRoot.Free;
  end;

  LHTTP := TIdHTTP.Create(nil);
  LIOHandler := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  try
    LIOHandler.SSLOptions.Method := sslvTLSv1_2;
    LIOHandler.SSLOptions.SSLVersions := [sslvTLSv1_2];
    LHTTP.IOHandler := LIOHandler;
    LHTTP.Request.ContentType := 'application/json';
    LHTTP.Request.CharSet := 'utf-8';
    LHTTP.Request.Accept := 'application/json';
    LHTTP.Request.CustomHeaders.AddValue('Accept-Charset', 'utf-8');
    LHTTP.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FApiKey.Trim);
    LHTTP.ConnectTimeout := FTimeout;
    LHTTP.ReadTimeout := FTimeout;

    LEnc := TEncoding.UTF8;
    LRequestStream := TStringStream.Create(LRequestJSON, LEnc);
    LResponseStream := TMemoryStream.Create;
    try
      LHTTP.Post(FApiUrl, LRequestStream, LResponseStream);
      LResponseStream.Position := 0;
      SetLength(LBytes, LResponseStream.Size);
      LResponseStream.ReadBuffer(LBytes[0], Length(LBytes));
      LResponse := TEncoding.UTF8.GetString(LBytes);
      LRoot := TJSONObject.ParseJSONValue(LResponse) as TJSONObject;
      if LRoot <> nil then
      try
        if LRoot.GetValue('error') <> nil then
        begin
          LContentVal := (LRoot.GetValue('error') as TJSONObject).GetValue('message');
          if LContentVal <> nil then FLastError := LContentVal.Value;
          ShowMessage('Erro: ' + FLastError);
          Exit;
        end;
        LChoices := LRoot.GetValue('choices') as TJSONArray;
        if (LChoices <> nil) and (LChoices.Count > 0) then
        begin
          LChoice := LChoices.Items[0] as TJSONObject;
          LMessage := LChoice.GetValue('message') as TJSONObject;
          if (LMessage <> nil) and (LMessage.GetValue('content') <> nil) then
            LContent := Trim((LMessage.GetValue('content') as TJSONString).Value)
          else
            LContent := '';
        end
        else
          LContent := '';
      finally
        LRoot.Free;
      end
      else
        LContent := 'Resposta inválida da API';
    finally
      LResponseStream.Free;
      LRequestStream.Free;
    end;
  finally
    LIOHandler.Free;
    LHTTP.Free;
  end;

  LForm := TForm.Create(nil);
  try
    LForm.Caption := 'An'#$00E1'lise da IA';
    LForm.Width := 500;
    LForm.Height := 400;
    LForm.Position := poScreenCenter;
    LForm.Font.Charset := 1;  // DEFAULT_CHARSET
    LForm.Font.Name := 'Segoe UI';

    LMemo := TMemo.Create(LForm);
    LMemo.Parent := LForm;
    LMemo.Align := alTop;
    LMemo.Height := LForm.ClientHeight - 50;
    LMemo.ReadOnly := True;
    LMemo.ScrollBars := ssVertical;
    LMemo.Font.Charset := 1;  // DEFAULT_CHARSET
    LMemo.Font.Name := 'Segoe UI';
    LMemo.Text := LContent;

    LBtn := TButton.Create(LForm);
    LBtn.Parent := LForm;
    LBtn.Caption := 'Fechar';
    LBtn.ModalResult := mrOk;
    LBtn.Align := alBottom;
    LBtn.Height := 36;

    LForm.ShowModal;
  finally
    LForm.Free;
  end;
end;

end.
