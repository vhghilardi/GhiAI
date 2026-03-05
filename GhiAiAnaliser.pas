unit GhiAiAnaliser;

{
  TGhiAiAnaliser - Componente Delphi para análise de dados via IA.
  Recebe um JSON com dados e uma orientação, retorna análise da IA.
  Parte do pacote GhiAI.

  Uso:
  1. Defina ApiUrl, ApiKey
  2. Defina RetornoComoJson (True = JSON, False = texto)
  3. Chame Analisar(JsonDados, 'Analise as vendas e destaque os principais insights')
}

interface

uses
  System.Classes, System.SysUtils, System.JSON,
  IdHTTP, IdSSLOpenSSL;

type
  TGhiAiAnaliser = class(TComponent)
  private
    FApiUrl: string;
    FApiKey: string;
    FModel: string;
    FTimeout: Integer;
    FRetornoComoJson: Boolean;
    FLastError: string;
    function ChamarOpenAI(const APrompt: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// Analisa os dados JSON conforme a orientação e retorna a análise da IA.
    /// </summary>
    /// <param name="AJsonDados">JSON com os dados a analisar (ex: vendas do ano)</param>
    /// <param name="AOrientacao">Orientação/prompt para a análise (ex: destaque tendências)</param>
    /// <returns>Análise em texto ou JSON conforme RetornoComoJson</returns>
    function Analisar(const AJsonDados, AOrientacao: string): string;
    property LastError: string read FLastError;
  published
    property ApiUrl: string read FApiUrl write FApiUrl;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    property Timeout: Integer read FTimeout write FTimeout default 60000;
    /// <summary>True = retorna JSON estruturado, False = retorna texto livre</summary>
    property RetornoComoJson: Boolean read FRetornoComoJson write FRetornoComoJson default False;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Ghi AI', [TGhiAiAnaliser]);
end;

{ TGhiAiAnaliser }

constructor TGhiAiAnaliser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FApiUrl := 'https://api.openai.com/v1/chat/completions';
  FApiKey := '';
  FModel := 'gpt-4o-mini';
  FTimeout := 60000;
  FRetornoComoJson := False;
  FLastError := '';
end;

destructor TGhiAiAnaliser.Destroy;
begin
  inherited;
end;

function TGhiAiAnaliser.ChamarOpenAI(const APrompt: string): string;
var
  LHTTP: TIdHTTP;
  LIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LRequestStream: TStringStream;
  LResponseStream: TMemoryStream;
  LResponse: string;
  LBytes: TBytes;
  LRoot, LMsgSystem, LMsgUser: TJSONObject;
  LMessages: TJSONArray;
  LContent: string;
  LRequestJSON: string;
  LChoices: TJSONArray;
  LChoice, LMessage: TJSONObject;
  LContentVal: TJSONValue;
  LEnc: TEncoding;
begin
  Result := '';
  FLastError := '';

  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('model', FModel);
    LRoot.AddPair('temperature', TJSONNumber.Create(0.7));
    LRoot.AddPair('max_tokens', TJSONNumber.Create(4000));

    LMessages := TJSONArray.Create;
    LContent := 'Você é um analista de dados especializado. Analise os dados fornecidos conforme a orientação do usuário. ';
    if FRetornoComoJson then
      LContent := LContent + 'Retorne a análise em formato JSON válido, com estrutura organizada (ex: {"resumo": "...", "insights": [...], "recomendacoes": [...]}). '
    else
      LContent := LContent + 'Retorne a análise em texto corrido, bem formatado e objetivo. ';
    LContent := LContent + 'Não inclua markdown ou blocos de código.';
    LMsgSystem := TJSONObject.Create;
    LMsgSystem.AddPair('role', 'system');
    LMsgSystem.AddPair('content', LContent);
    LMessages.AddElement(LMsgSystem);

    LMsgUser := TJSONObject.Create;
    LMsgUser.AddPair('role', 'user');
    LMsgUser.AddPair('content', APrompt);
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
    LHTTP.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FApiKey.Trim);
    LHTTP.ConnectTimeout := FTimeout;
    LHTTP.ReadTimeout := FTimeout;

    LEnc := TEncoding.UTF8;
    LRequestStream := TStringStream.Create(LRequestJSON, LEnc);
    LResponseStream := TMemoryStream.Create;
    try
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
            Exit;
          end;
          LChoices := LRoot.GetValue('choices') as TJSONArray;
          if (LChoices <> nil) and (LChoices.Count > 0) then
          begin
            LChoice := LChoices.Items[0] as TJSONObject;
            LMessage := LChoice.GetValue('message') as TJSONObject;
            if (LMessage <> nil) and (LMessage.GetValue('content') <> nil) then
              Result := Trim((LMessage.GetValue('content') as TJSONString).Value);
          end;
        finally
          LRoot.Free;
        end;
      except
        on E: Exception do
        begin
          FLastError := E.Message;
          Result := '';
        end;
      end;
    finally
      LResponseStream.Free;
      LRequestStream.Free;
    end;
  finally
    LIOHandler.Free;
    LHTTP.Free;
  end;
end;

function TGhiAiAnaliser.Analisar(const AJsonDados, AOrientacao: string): string;
var
  LPrompt: string;
begin
  Result := '';
  FLastError := '';

  if Trim(FApiUrl) = '' then
  begin
    FLastError := 'ApiUrl não configurada';
    Exit;
  end;

  if Trim(FApiKey) = '' then
  begin
    FLastError := 'ApiKey não configurada';
    Exit;
  end;

  if Trim(AJsonDados) = '' then
  begin
    FLastError := 'Dados JSON não informados';
    Exit;
  end;

  if Trim(AOrientacao) = '' then
  begin
    FLastError := 'Orientação não informada';
    Exit;
  end;

  LPrompt := 'Dados a analisar:' + sLineBreak + AJsonDados.Trim + sLineBreak + sLineBreak +
    'Orientação para a análise: ' + AOrientacao.Trim;

  Result := ChamarOpenAI(LPrompt);

  // Remove possíveis marcadores de código na resposta
  if (Result <> '') and (Length(Result) >= 3) and (Copy(Result, 1, 3) = '```') then
  begin
    Result := Trim(Copy(Result, 4, Length(Result)));
    if (Length(Result) >= 4) and (LowerCase(Copy(Result, 1, 4)) = 'json') then
      Result := Trim(Copy(Result, 5, Length(Result)));
    if (Length(Result) >= 3) and (Copy(Result, Length(Result) - 2, 3) = '```') then
      Result := Trim(Copy(Result, 1, Length(Result) - 3));
  end;
end;

end.
