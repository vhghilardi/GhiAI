unit GhiAiPredictive;

{
  TGhiAiPredictive - Componente Delphi para análise preditiva via IA.
  Recebe dados em JSON, envia para a IA fazer análise preditiva e retorna JSON.
  Parte do pacote GhiAI.

  Uso:
  1. Defina ApiUrl, ApiKey
  2. Defina FormatoRetorno (preCompleto ou preSimplificado)
  3. Defina ContextoAnalise (ex: "3 meses à frente", "7 dias", "próximos 5 meses")
  4. Chame Prever(JsonDados) - retorna JSON com previsões
}

interface

uses
  System.Classes, System.SysUtils, System.JSON,
  IdHTTP, IdSSLOpenSSL;

type
  /// <summary>Formato do JSON retornado pela análise preditiva</summary>
  TGhiAiPredictiveFormatoRetorno = (
    /// <summary>Resumo completo: previsoes, tendencia, cenarioOtimista, cenarioPessimista, confianca, observacoes</summary>
    preCompleto,
    /// <summary>Resumo simplificado: previsoes (array), tendencia (alta/estável/baixa), observacoes</summary>
    preSimplificado
  );

  TGhiAiPredictive = class(TComponent)
  private
    FApiUrl: string;
    FApiKey: string;
    FModel: string;
    FTimeout: Integer;
    FFormatoRetorno: TGhiAiPredictiveFormatoRetorno;
    FContextoAnalise: string;
    FLastError: string;
    function ChamarOpenAI(const APrompt: string): string;
    function GetEsquemaParaFormato: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// Envia dados para análise preditiva e retorna JSON com previsões.
    /// </summary>
    /// <param name="AJsonDados">JSON com os dados históricos (ex: vendas mensais)</param>
    /// <returns>JSON com previsões, tendências e cenários</returns>
    function Prever(const AJsonDados: string): string;
    property LastError: string read FLastError;
  published
    property ApiUrl: string read FApiUrl write FApiUrl;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
    property Timeout: Integer read FTimeout write FTimeout default 60000;
    /// <summary>Formato do JSON de retorno: Completo (todos os campos) ou Simplificado</summary>
    property FormatoRetorno: TGhiAiPredictiveFormatoRetorno read FFormatoRetorno write FFormatoRetorno default preCompleto;
    /// <summary>Tipo/período da análise esperada (ex: "3 meses à frente", "7 dias", "próximos 5 meses")</summary>
    property ContextoAnalise: string read FContextoAnalise write FContextoAnalise;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Ghi AI', [TGhiAiPredictive]);
end;

{ TGhiAiPredictive }

constructor TGhiAiPredictive.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FApiUrl := 'https://api.openai.com/v1/chat/completions';
  FApiKey := '';
  FModel := 'gpt-4o-mini';
  FTimeout := 60000;
  FFormatoRetorno := preCompleto;
  FContextoAnalise := '';
  FLastError := '';
end;

function TGhiAiPredictive.GetEsquemaParaFormato: string;
begin
  case FFormatoRetorno of
    preCompleto:
      Result := '{"previsoes": [array de valores], "tendencia": "alta|estável|baixa", ' +
        '"cenarioOtimista": number, "cenarioPessimista": number, "confianca": 0-100, ' +
        '"observacoes": [array de strings]}';
    preSimplificado:
      Result := '{"previsoes": [array de valores], "tendencia": "alta|estável|baixa", ' +
        '"observacoes": [array de strings]}';
  else
    Result := '';
  end;
end;

destructor TGhiAiPredictive.Destroy;
begin
  inherited;
end;

function TGhiAiPredictive.ChamarOpenAI(const APrompt: string): string;
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
    LRoot.AddPair('temperature', TJSONNumber.Create(0.3));
    LRoot.AddPair('max_tokens', TJSONNumber.Create(4000));

    LMessages := TJSONArray.Create;
    LContent := 'Você é um analista preditivo especializado. Com base nos dados históricos fornecidos, ' +
      'faça uma análise preditiva e retorne APENAS um JSON válido, sem explicações ou markdown. ' +
      'Estruture EXATAMENTE conforme: ' + GetEsquemaParaFormato + '. ' +
      'Retorne somente o JSON, sem ``` ou texto adicional.';
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

function TGhiAiPredictive.Prever(const AJsonDados: string): string;
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

  if Trim(FContextoAnalise) <> '' then
    Result := ChamarOpenAI('Tipo de análise esperada: ' + FContextoAnalise.Trim + sLineBreak + sLineBreak +
      'Dados históricos:' + sLineBreak + AJsonDados.Trim)
  else
    Result := ChamarOpenAI('Dados históricos para análise preditiva:' + sLineBreak + AJsonDados.Trim);

  // Remove possíveis marcadores de código
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
