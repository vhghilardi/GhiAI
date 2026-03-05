unit GhiAIDataJud;

{
  TGhiAIDataJud - Componente Delphi para consultar processos no DataJud (CNJ)
  e gerar resumo explicativo via IA. Parte do pacote GhiAI.

  Uso:
  1. Defina DataJudApiUrl (ex: https://api-publica.datajud.cnj.jus.br/api_publica_tjrs/_search)
  2. Defina DataJudApiKey (chave da API pública DataJud)
  3. Defina OpenAIApiUrl, OpenAIApiKey para o resumo pela IA
  4. Defina QuantidadeMovimentos (X últimas movimentações)
  5. Chame ConsultarProcesso('50038262720238210019')
}

interface

uses
  System.Classes, System.SysUtils, System.JSON,
  IdHTTP, IdSSLOpenSSL;

type
  TGhiAIDataJudResult = record
    Sucesso: Boolean;
    TextoCompleto: string;
    NomeClasse: string;
    Sistema: string;
    Formato: string;
    Tribunal: string;
    OrgaoJulgador: string;
    DataHoraUltimaAtualizacao: string;
    Assuntos: string;
    Movimentos: string;
    ResumoIA: string;
    MensagemErro: string;
  end;

  TGhiAIDataJud = class(TComponent)
  private
    FDataJudApiUrl: string;
    FDataJudApiKey: string;
    FOpenAIApiUrl: string;
    FOpenAIApiKey: string;
    FOpenAIModel: string;
    FQuantidadeMovimentos: Integer;
    FTimeout: Integer;
    FLastError: string;
    function ConsultarDataJud(const AIdProcesso: string; out AJsonResponse: string): Boolean;
    function GerarResumoIA(const AMovimentos, AAssuntos: string): string;
    function ParseDataJudResponse(const AJsonResponse: string; out AResult: TGhiAIDataJudResult): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// Consulta processo no DataJud e retorna X movimentações + resumo pela IA.
    /// </summary>
    /// <param name="AIdProcesso">Número do processo (com ou sem formatação)</param>
    /// <returns>Record com dados do processo, movimentações e resumo IA</returns>
    function ConsultarProcesso(const AIdProcesso: string): TGhiAIDataJudResult;
    /// <summary>
    /// Versão simplificada - retorna apenas o texto completo formatado.</summary>
    function ConsultarProcessoTexto(const AIdProcesso: string): string;
    property LastError: string read FLastError;
  published
    /// <summary>URL da API DataJud (ex: .../api_publica_tjrs/_search)</summary>
    property DataJudApiUrl: string read FDataJudApiUrl write FDataJudApiUrl;
    /// <summary>Chave API do DataJud (formato: APIKey xxx)</summary>
    property DataJudApiKey: string read FDataJudApiKey write FDataJudApiKey;
    /// <summary>URL da API OpenAI para o resumo</summary>
    property OpenAIApiUrl: string read FOpenAIApiUrl write FOpenAIApiUrl;
    /// <summary>Chave API da OpenAI</summary>
    property OpenAIApiKey: string read FOpenAIApiKey write FOpenAIApiKey;
    /// <summary>Modelo OpenAI (ex: gpt-4o-mini)</summary>
    property OpenAIModel: string read FOpenAIModel write FOpenAIModel;
    /// <summary>Quantidade de movimentações a retornar (últimas X)</summary>
    property QuantidadeMovimentos: Integer read FQuantidadeMovimentos write FQuantidadeMovimentos default 5;
    /// <summary>Timeout em milissegundos</summary>
    property Timeout: Integer read FTimeout write FTimeout default 30000;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Ghi AI', [TGhiAIDataJud]);
end;

function SafeJsonStr(AObj: TJSONObject; const AKey: string): string;
var
  LVal: TJSONValue;
begin
  Result := '';
  if (AObj = nil) or (AKey = '') then Exit;
  LVal := AObj.GetValue(AKey);
  if (LVal <> nil) and (LVal is TJSONString) then
    Result := (LVal as TJSONString).Value;
end;

{ TGhiAIDataJud }

constructor TGhiAIDataJud.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDataJudApiUrl := 'https://api-publica.datajud.cnj.jus.br/api_publica_tjrs/_search';
  FDataJudApiKey := '';
  FOpenAIApiUrl := 'https://api.openai.com/v1/chat/completions';
  FOpenAIApiKey := '';
  FOpenAIModel := 'gpt-4o-mini';
  FQuantidadeMovimentos := 5;
  FTimeout := 30000;
  FLastError := '';
end;

destructor TGhiAIDataJud.Destroy;
begin
  inherited;
end;

function TGhiAIDataJud.ConsultarDataJud(const AIdProcesso: string; out AJsonResponse: string): Boolean;
var
  LHTTP: TIdHTTP;
  LIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LRequestStream: TStringStream;
  LResponseStream: TMemoryStream;
  LRequestJSON: string;
  LEnc: TEncoding;
  LAuthValue: string;
  LBytes: TBytes;
begin
  Result := False;
  AJsonResponse := '';
  FLastError := '';

  LRequestJSON := '{"query":{"match":{"numeroProcesso":"' + AIdProcesso + '"}}}';
  LEnc := TEncoding.UTF8;
  LRequestStream := TStringStream.Create(LRequestJSON, LEnc);
  LResponseStream := TMemoryStream.Create;
  LHTTP := TIdHTTP.Create(nil);
  LIOHandler := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  try
    LIOHandler.SSLOptions.Method := sslvTLSv1_2;
    LIOHandler.SSLOptions.SSLVersions := [sslvTLSv1_2];
    LHTTP.IOHandler := LIOHandler;
    LHTTP.Request.ContentType := 'application/json';
    LHTTP.Request.CharSet := 'utf-8';
    LHTTP.ConnectTimeout := FTimeout;
    LHTTP.ReadTimeout := FTimeout;

    LAuthValue := Trim(FDataJudApiKey);
    if (LAuthValue <> '') and ((Length(LAuthValue) < 7) or (Copy(LAuthValue, 1, 7) <> 'APIKey ')) then
      LAuthValue := 'APIKey ' + LAuthValue;
    LHTTP.Request.CustomHeaders.AddValue('Authorization', LAuthValue);

    try
      LHTTP.Post(FDataJudApiUrl, LRequestStream, LResponseStream);
      LResponseStream.Position := 0;
      SetLength(LBytes, LResponseStream.Size);
      LResponseStream.ReadBuffer(LBytes[0], Length(LBytes));
      AJsonResponse := TEncoding.UTF8.GetString(LBytes);
      Result := True;
    except
      on E: Exception do
      begin
        FLastError := 'DataJud: ' + E.Message;
        Result := False;
      end;
    end;
  finally
    LResponseStream.Free;
    LRequestStream.Free;
    LIOHandler.Free;
    LHTTP.Free;
  end;
end;

function TGhiAIDataJud.ParseDataJudResponse(const AJsonResponse: string; out AResult: TGhiAIDataJudResult): Boolean;
var
  LRoot, LHits, LHit, LSource, LClasse, LSistema, LFormato, LOrgao, LItem, LComp: TJSONObject;
  LMovimentos, LAssuntos, LCompArr: TJSONArray;
  I, J, LCount: Integer;
  LStr: string;
begin
  Result := False;
  AResult.Sucesso := False;
  AResult.TextoCompleto := '';
  AResult.MensagemErro := '';

  try
    LRoot := TJSONObject.ParseJSONValue(AJsonResponse) as TJSONObject;
    if LRoot = nil then
    begin
      AResult.MensagemErro := 'Resposta inválida do DataJud';
      Exit;
    end;
    try
      LHits := LRoot.GetValue('hits') as TJSONObject;
      if LHits = nil then
      begin
        AResult.MensagemErro := 'Desculpe, não encontrei nenhuma informação para o número informado.';
        Exit;
      end;

      LMovimentos := LHits.GetValue('hits') as TJSONArray;
      if (LMovimentos = nil) or (LMovimentos.Count = 0) then
      begin
        AResult.MensagemErro := 'Desculpe, não encontrei nenhuma informação para o número informado.';
        Exit;
      end;

      LHit := LMovimentos.Items[0] as TJSONObject;
      LSource := LHit.GetValue('_source') as TJSONObject;
      if LSource = nil then
      begin
        AResult.MensagemErro := 'Desculpe, não encontrei nenhuma informação para o número informado.';
        Exit;
      end;

      // Classe, Sistema, Formato, Tribunal, DataHora, OrgaoJulgador
      LClasse := LSource.GetValue('classe') as TJSONObject;
      AResult.NomeClasse := SafeJsonStr(LClasse, 'nome');
      LSistema := LSource.GetValue('sistema') as TJSONObject;
      AResult.Sistema := SafeJsonStr(LSistema, 'nome');
      LFormato := LSource.GetValue('formato') as TJSONObject;
      AResult.Formato := SafeJsonStr(LFormato, 'nome');
      AResult.Tribunal := SafeJsonStr(LSource, 'tribunal');
      AResult.DataHoraUltimaAtualizacao := SafeJsonStr(LSource, 'dataHoraUltimaAtualizacao');
      LOrgao := LSource.GetValue('orgaoJulgador') as TJSONObject;
      AResult.OrgaoJulgador := SafeJsonStr(LOrgao, 'nome');

      // Assuntos
      LAssuntos := LSource.GetValue('assuntos') as TJSONArray;
      AResult.Assuntos := '';
      if LAssuntos <> nil then
        for I := 0 to LAssuntos.Count - 1 do
        begin
          LItem := LAssuntos.Items[I] as TJSONObject;
          if LItem <> nil then
            AResult.Assuntos := AResult.Assuntos + ' - ' + SafeJsonStr(LItem, 'nome') + sLineBreak;
        end;

      // Movimentos (limitado a QuantidadeMovimentos)
      LMovimentos := LSource.GetValue('movimentos') as TJSONArray;
      AResult.Movimentos := '';
      if LMovimentos <> nil then
      begin
        LCount := 0;
        for I := 0 to LMovimentos.Count - 1 do
        begin
          if LCount >= FQuantidadeMovimentos then Break;
          LItem := LMovimentos.Items[I] as TJSONObject;
          if LItem = nil then Continue;
          LStr := SafeJsonStr(LItem, 'nome');
          if SafeJsonStr(LItem, 'dataHora') <> '' then
            LStr := LStr + ' (' + SafeJsonStr(LItem, 'dataHora') + ')';
          LCompArr := LItem.GetValue('complementosTabelados') as TJSONArray;
          if (LCompArr <> nil) and (LCompArr.Count > 0) then
            for J := 0 to LCompArr.Count - 1 do
            begin
              LComp := LCompArr.Items[J] as TJSONObject;
              if LComp <> nil then
                LStr := LStr + ' - ' + SafeJsonStr(LComp, 'nome');
            end;
          AResult.Movimentos := AResult.Movimentos + ' - ' + LStr + sLineBreak;
          Inc(LCount);
        end;
      end;

      AResult.Sucesso := True;
      Result := True;
    finally
      LRoot.Free;
    end;
  except
    on E: Exception do
    begin
      AResult.MensagemErro := 'Erro ao processar resposta: ' + E.Message;
      FLastError := AResult.MensagemErro;
    end;
  end;
end;

function TGhiAIDataJud.GerarResumoIA(const AMovimentos, AAssuntos: string): string;
var
  LHTTP: TIdHTTP;
  LIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LRequestStream: TStringStream;
  LResponseStream: TMemoryStream;
  LResponse: string;
  LRoot, LMsgSystem, LMsgUser: TJSONObject;
  LMessages: TJSONArray;
  LContent, LRequestJSON: string;
  LChoices: TJSONArray;
  LChoice, LMessage: TJSONObject;
  LContentVal: TJSONValue;
  LEnc: TEncoding;
  LBytes: TBytes;
begin
  Result := '';
  FLastError := '';

  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('model', FOpenAIModel);
    LRoot.AddPair('temperature', TJSONNumber.Create(0.8));
    LRoot.AddPair('max_tokens', TJSONNumber.Create(1500));

    LMessages := TJSONArray.Create;
    LContent := 'Voc'#$00EA' '#$00E9' uma assistente jur'#$00ED'dica virtual. Com base nas movimenta'#$00E7#$00F5'es e assuntos de um processo judicial, ' +
      'explique de forma clara e objetiva o momento atual do processo para um cidad'#$00E3'o leigo. ' +
      'Seja conciso (2-4 par'#$00E1'grafos). N'#$00E3'o invente informa'#$00E7#$00F5'es. Use linguagem acess'#$00ED'vel.';
    LMsgSystem := TJSONObject.Create;
    LMsgSystem.AddPair('role', 'system');
    LMsgSystem.AddPair('content', LContent);
    LMessages.AddElement(LMsgSystem);

    LContent := 'Assuntos do processo:' + sLineBreak + AAssuntos + sLineBreak +
      'Movimentações recentes:' + sLineBreak + AMovimentos + sLineBreak +
      'Explique o momento atual deste processo de forma clara.';
    LMsgUser := TJSONObject.Create;
    LMsgUser.AddPair('role', 'user');
    LMsgUser.AddPair('content', LContent);
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
    LHTTP.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FOpenAIApiKey.Trim);
    LHTTP.ConnectTimeout := FTimeout;
    LHTTP.ReadTimeout := FTimeout;

    LEnc := TEncoding.UTF8;
    LRequestStream := TStringStream.Create(LRequestJSON, LEnc);
    LResponseStream := TMemoryStream.Create;
    try
      try
        LHTTP.Post(FOpenAIApiUrl, LRequestStream, LResponseStream);
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
          FLastError := 'OpenAI: ' + E.Message;
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

function TGhiAIDataJud.ConsultarProcesso(const AIdProcesso: string): TGhiAIDataJudResult;
var
  LIdProcesso, LJsonResponse, LTemp: string;
  I: Integer;
begin
  Result.Sucesso := False;
  Result.TextoCompleto := '';
  Result.MensagemErro := '';
  Result.ResumoIA := '';
  FLastError := '';

  LIdProcesso := Trim(AIdProcesso);
  if LIdProcesso = '' then
  begin
    Result.MensagemErro := 'Número do processo não informado.';
    Exit;
  end;

  // Remove formatação (apenas dígitos)
  LTemp := '';
  for I := 1 to Length(LIdProcesso) do
    if CharInSet(LIdProcesso[I], ['0'..'9']) then
      LTemp := LTemp + LIdProcesso[I];
  LIdProcesso := LTemp;

  if Trim(FDataJudApiUrl) = '' then
  begin
    Result.MensagemErro := 'DataJudApiUrl não configurada.';
    Exit;
  end;

  if Trim(FDataJudApiKey) = '' then
  begin
    Result.MensagemErro := 'DataJudApiKey não configurada.';
    Exit;
  end;

  if not ConsultarDataJud(LIdProcesso, LJsonResponse) then
  begin
    Result.MensagemErro := FLastError;
    Exit;
  end;

  if not ParseDataJudResponse(LJsonResponse, Result) then
    Exit;

  // Gerar resumo pela IA (se OpenAI configurada)
  if (Trim(FOpenAIApiUrl) <> '') and (Trim(FOpenAIApiKey) <> '') then
    Result.ResumoIA := GerarResumoIA(Result.Movimentos, Result.Assuntos);

  // Montar texto completo (Unicode explícito para evitar problemas de encoding)
  Result.TextoCompleto := 'Nome: ' + Result.NomeClasse + sLineBreak +
    'Sistema: ' + Result.Sistema + sLineBreak +
    'Formato: ' + Result.Formato + sLineBreak +
    'Tribunal: ' + Result.Tribunal + sLineBreak +
    #$00D3'r'#$67#$00E3'o Julgador: ' + Result.OrgaoJulgador + sLineBreak +
    'Data/Hora ' + #$00DA'ltima Atualiza'#$00E7#$00E3'o: ' + Result.DataHoraUltimaAtualizacao + sLineBreak +
    'Assuntos:' + sLineBreak + Result.Assuntos +
    'Movimentos:' + sLineBreak + Result.Movimentos;

  if Result.ResumoIA <> '' then
    Result.TextoCompleto := Result.TextoCompleto + sLineBreak +
      'Segue uma resposta gerada pela nossa assistente jur'#$00ED'dica virtual:' + sLineBreak +
      Result.ResumoIA + sLineBreak + sLineBreak +
      '*Aten'#$00E7#$00E3'o*: Essa resposta '#$00E9' gerada pela nossa assistente jur'#$00ED'dica virtual, portanto, ' +
      '*n'#$00E3'o '#$00E9' uma resposta oficial do tribunal.*';
end;

function TGhiAIDataJud.ConsultarProcessoTexto(const AIdProcesso: string): string;
var
  LResult: TGhiAIDataJudResult;
begin
  LResult := ConsultarProcesso(AIdProcesso);
  if LResult.Sucesso then
    Result := LResult.TextoCompleto
  else
    Result := LResult.MensagemErro;
end;

end.
