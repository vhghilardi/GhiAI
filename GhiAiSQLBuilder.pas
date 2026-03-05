unit GhiAiSQLBuilder;

{
  TGhiAiSQLBuilder - Componente Delphi para transformar SQL básico em SQL complexo
  usando a API OpenAI. Parte do pacote GhiAI.

  Uso:
  1. Defina ApiUrl (ex: https://api.openai.com/v1/chat/completions)
  2. Defina ApiKey (sua chave da OpenAI)
  3. IMPORTANTE: Linke um Connection (TFDConnection) conectado para que o schema
     das tabelas seja analisado - evita colunas inventadas pela IA
  4. Chame BuildSQL('select * from vendas', 'me retorne a soma das vendas por semana no mes')
}

interface

uses
  System.Classes, System.SysUtils, System.JSON, System.Generics.Collections, Data.DB,
  IdHTTP, IdSSLOpenSSL, FireDAC.Comp.Client;

type
  TGhiAiDatabaseType = (dbSQLServer, dbMySQL, dbPostgreSQL, dbFirebird);

  TGhiAiSQLBuilder = class(TComponent)
  private
    FConnection: TCustomConnection;
    FApiUrl: string;
    FApiKey: string;
    FModel: string;
    FLastError: string;
    FTimeout: Integer;
    FDatabaseType: TGhiAiDatabaseType;
    procedure SetConnection(const Value: TCustomConnection);
    function GetDatabaseTypeHint: string;
    function ExtractTableNamesFromSQL(const ASQL: string): TArray<string>;
    function GetTableColumns(const ATableName: string; out AColumns: TArray<string>): Boolean;
    function BuildSchemaContext(const ATableNames: TArray<string>): string;
  protected
    function BuildRequestJSON(const ABasicSQL, AInstruction: string): string;
    function ParseResponseJSON(const AResponse: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// Constrói o SQL complexo a partir do SQL básico e da instrução.
    /// </summary>
    /// <param name="ABasicSQL">SQL básico (ex: select * from vendas)</param>
    /// <param name="AInstruction">Instrução do que deseja (ex: soma das vendas por semana no mês)</param>
    /// <returns>SQL pronto para execução ou string vazia em caso de erro</returns>
    function BuildSQL(const ABasicSQL, AInstruction: string): string;
    property LastError: string read FLastError;
  published
    /// <summary>Conexão com o banco (TFDConnection conectado). Obrigatório para análise do schema - sem ele a IA pode inventar colunas inexistentes</summary>
    property Connection: TCustomConnection read FConnection write SetConnection;
    /// <summary>URL da API OpenAI (ex: https://api.openai.com/v1/chat/completions)</summary>
    property ApiUrl: string read FApiUrl write FApiUrl;
    /// <summary>Chave de API da OpenAI</summary>
    property ApiKey: string read FApiKey write FApiKey;
    /// <summary>Modelo a usar (ex: gpt-4o-mini, gpt-4, gpt-3.5-turbo)</summary>
    property Model: string read FModel write FModel;
    /// <summary>Timeout da requisição em milissegundos</summary>
    property Timeout: Integer read FTimeout write FTimeout default 60000;
    /// <summary>Banco de dados de destino (SQL Server, MySQL, PostgreSQL, Firebird)</summary>
    property DatabaseType: TGhiAiDatabaseType read FDatabaseType write FDatabaseType default dbSQLServer;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Ghi AI', [TGhiAiSQLBuilder]);
end;

{ TGhiAiSQLBuilder }

constructor TGhiAiSQLBuilder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FApiUrl := 'https://api.openai.com/v1/chat/completions';
  FApiKey := '';
  FModel := 'gpt-4o-mini';
  FTimeout := 60000;
  FDatabaseType := dbFirebird;
  FLastError := '';
end;

destructor TGhiAiSQLBuilder.Destroy;
begin
  inherited;
end;

procedure TGhiAiSQLBuilder.SetConnection(const Value: TCustomConnection);
begin
  if FConnection <> Value then
    FConnection := Value;
end;

function TGhiAiSQLBuilder.GetDatabaseTypeHint: string;
begin
  case FDatabaseType of
    dbSQLServer:   Result := 'SQL Server (use T-SQL: DATEPART, GETDATE(), MONTH(), YEAR(), etc.)';
    dbMySQL:       Result := 'MySQL (use funções MySQL: WEEK(), CURDATE(), MONTH(), YEAR(), etc.)';
    dbPostgreSQL: Result := 'PostgreSQL (use EXTRACT, CURRENT_DATE, date_trunc, etc.)';
    dbFirebird:    Result := 'Firebird (use EXTRACT(WEEK FROM campo), CURRENT_DATE, EXTRACT(MONTH FROM campo), etc.)';
  else
    Result := 'SQL padrão';
  end;
end;

function TGhiAiSQLBuilder.ExtractTableNamesFromSQL(const ASQL: string): TArray<string>;
var
  LList: TList<string>;
  LSQL, LUpper, LTable: string;
  I, LSqlPos: Integer;

  function IsWordBoundary(APos: Integer): Boolean;
  begin
    Result := (APos <= 1) or (APos > Length(LUpper)) or
              not CharInSet(LUpper[APos-1], ['A'..'Z', '0'..'9', '_']);
  end;

  function NextToken(var APos: Integer): string;
  var
    K: Integer;
  begin
    Result := '';
    while (APos <= Length(LSQL)) and CharInSet(LSQL[APos], [' ', #9, #10, #13, ',']) do
      Inc(APos);
    if APos > Length(LSQL) then Exit;
    if LSQL[APos] = '(' then
    begin
      Inc(APos);
      Exit;
    end;
    if CharInSet(LSQL[APos], ['"', '''', '[']) then
    begin
      K := APos;
      if LSQL[APos] = '[' then
      begin
        Inc(APos);
        while (APos <= Length(LSQL)) and (LSQL[APos] <> ']') do Inc(APos);
        if APos <= Length(LSQL) then Inc(APos);
      end
      else
      begin
        Inc(APos);
        while (APos <= Length(LSQL)) and (LSQL[APos] <> LSQL[K]) do Inc(APos);
        if APos <= Length(LSQL) then Inc(APos);
      end;
      Result := Copy(LSQL, K, APos - K);
      Exit;
    end;
    K := APos;
    while (APos <= Length(LSQL)) and CharInSet(LSQL[APos], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      Inc(APos);
    Result := Copy(LSQL, K, APos - K);
  end;

  procedure TryAddTable(const AName: string);
  begin
    if (AName <> '') and (LList.IndexOf(AName) < 0) then
      LList.Add(AName);
  end;

begin
  LList := TList<string>.Create;
  try
    LSQL := Trim(ASQL);
    LUpper := ' ' + UpperCase(LSQL) + ' ';
    if Length(LUpper) < 8 then Exit;
    I := 1;
    while I <= Length(LUpper) - 5 do
    begin
      if IsWordBoundary(I) then
      begin
        if Copy(LUpper, I, 5) = ' FROM' then
        begin
          Inc(I, 5);
          LSqlPos := I - 1;
          LTable := NextToken(LSqlPos);
          if (LTable <> '') and (LTable <> '(') then
            TryAddTable(LTable);
          Continue;
        end;
        if (Copy(LUpper, I, 12) = ' OUTER JOIN') or (Copy(LUpper, I, 11) = ' RIGHT JOIN') or
           (Copy(LUpper, I, 11) = ' INNER JOIN') or (Copy(LUpper, I, 10) = ' LEFT JOIN') or
           (Copy(LUpper, I, 7) = ' CROSS') or (Copy(LUpper, I, 5) = ' JOIN') then
        begin
          if Copy(LUpper, I, 12) = ' OUTER JOIN' then Inc(I, 12)
          else if Copy(LUpper, I, 11) = ' RIGHT JOIN' then Inc(I, 11)
          else if Copy(LUpper, I, 11) = ' INNER JOIN' then Inc(I, 11)
          else if Copy(LUpper, I, 10) = ' LEFT JOIN' then Inc(I, 10)
          else if Copy(LUpper, I, 7) = ' CROSS' then Inc(I, 7)
          else Inc(I, 5);
          LSqlPos := I - 1;
          LTable := NextToken(LSqlPos);
          if (LTable <> '') and (LTable <> '(') then
            TryAddTable(LTable);
          Continue;
        end;
      end;
      Inc(I);
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TGhiAiSQLBuilder.GetTableColumns(const ATableName: string; out AColumns: TArray<string>): Boolean;
var
  LList: TStringList;
  LConn: TFDConnection;
  LTable: string;
  I: Integer;
begin
  Result := False;
  AColumns := nil;
  if (FConnection = nil) or not (FConnection is TFDConnection) then Exit;
  LConn := TFDConnection(FConnection);
  if not LConn.Connected then Exit;
  LTable := Trim(ATableName);
  if LTable = '' then Exit;
  if (Length(LTable) > 2) and (LTable[1] = '"') and (LTable[Length(LTable)] = '"') then
    LTable := Copy(LTable, 2, Length(LTable) - 2)
  else if (Length(LTable) > 2) and (LTable[1] = '[') and (LTable[Length(LTable)] = ']') then
    LTable := Copy(LTable, 2, Length(LTable) - 2);
  if Pos('.', LTable) > 0 then
    LTable := Copy(LTable, LastDelimiter('.', LTable) + 1, Length(LTable));
  if FDatabaseType = dbFirebird then
    LTable := UpperCase(LTable);
  LList := TStringList.Create;
  try
    try
      LConn.GetFieldNames('', '', LTable, '', LList);
      SetLength(AColumns, LList.Count);
      for I := 0 to LList.Count - 1 do
        AColumns[I] := LList[I];
      Result := LList.Count > 0;
    except
      Result := False;
    end;
  finally
    LList.Free;
  end;
end;

function TGhiAiSQLBuilder.BuildSchemaContext(const ATableNames: TArray<string>): string;
var
  LCols: TArray<string>;
  LTable, LColList: string;
  I, J: Integer;
begin
  Result := '';
  for LTable in ATableNames do
  begin
    if GetTableColumns(LTable, LCols) then
    begin
      LColList := '';
      for J := 0 to High(LCols) do
      begin
        if LColList <> '' then LColList := LColList + ', ';
        LColList := LColList + LCols[J];
      end;
      if Result <> '' then Result := Result + sLineBreak;
      Result := Result + Format('Tabela %s: colunas [%s]', [LTable, LColList]);
    end;
  end;
end;

function TGhiAiSQLBuilder.BuildRequestJSON(const ABasicSQL, AInstruction: string): string;
var
  LRoot, LMsgSystem, LMsgUser: TJSONObject;
  LMessages: TJSONArray;
  LContent, LSchemaCtx: string;
  LTableNames: TArray<string>;
begin
  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('model', FModel);
    LRoot.AddPair('temperature', TJSONNumber.Create(0.2));
    LRoot.AddPair('max_tokens', TJSONNumber.Create(2000));

    LMessages := TJSONArray.Create;

    // Mensagem do sistema - instruções para o modelo
    LContent := 'Você é um especialista em SQL. Sua tarefa é transformar uma query SQL básica ' +
      'em uma query SQL complexa conforme a instrução do usuário. ' +
      'Retorne APENAS o SQL final, sem explicações, sem markdown, sem ```sql. ' +
      'IMPORTANTE: Use EXCLUSIVAMENTE sintaxe do banco: ' + GetDatabaseTypeHint + '. ' +
      'Se a tabela tiver coluna de data, use funções apropriadas para o banco selecionado.';

    // Análise do schema: se Connection estiver definida, obtém colunas das tabelas
    LTableNames := ExtractTableNamesFromSQL(ABasicSQL);
    if Length(LTableNames) > 0 then
    begin
      LSchemaCtx := BuildSchemaContext(LTableNames);
      if LSchemaCtx <> '' then
        LContent := LContent + sLineBreak + sLineBreak +
          'ESQUEMA OBRIGATÓRIO - USE APENAS ESTAS COLUNAS (não existe outra):' + sLineBreak + LSchemaCtx +
          sLineBreak + sLineBreak +
          'REGRA CRÍTICA: NÃO invente colunas. Se uma coluna não está na lista acima, NÃO use. ' +
          'Ex: se "valor" não está em itens_pedidos, NÃO use i.valor. Use apenas colunas do esquema.';
      if LSchemaCtx = '' then
        LContent := LContent + sLineBreak + sLineBreak +
          'AVISO: Schema não disponível (configure Connection com TFDConnection conectado). ' +
          'NÃO invente colunas como valor, quantidade, preco, etc. Use APENAS colunas que aparecem explicitamente no SQL. ' +
          'Se o SQL usa SELECT *, você NÃO sabe as colunas - NÃO assuma que existem campos comuns.';
    end;
    LMsgSystem := TJSONObject.Create;
    LMsgSystem.AddPair('role', 'system');
    LMsgSystem.AddPair('content', LContent);
    LMessages.AddElement(LMsgSystem);

    // Mensagem do usuário
    LContent := Format('SQL básico: %s' + sLineBreak + sLineBreak +
      'Instrução: %s' + sLineBreak + sLineBreak +
      'Retorne apenas o SQL completo e executável.',
      [ABasicSQL.Trim, AInstruction.Trim]);
    LMsgUser := TJSONObject.Create;
    LMsgUser.AddPair('role', 'user');
    LMsgUser.AddPair('content', LContent);
    LMessages.AddElement(LMsgUser);

    LRoot.AddPair('messages', LMessages);
    Result := LRoot.ToJSON;
  finally
    LRoot.Free;
  end;
end;

function TGhiAiSQLBuilder.ParseResponseJSON(const AResponse: string): string;
var
  LRoot: TJSONObject;
  LChoices: TJSONArray;
  LChoice: TJSONObject;
  LMessage: TJSONObject;
  LContent: TJSONValue;
begin
  Result := '';
  FLastError := '';
  try
    LRoot := TJSONObject.ParseJSONValue(AResponse) as TJSONObject;
    if LRoot = nil then
    begin
      FLastError := 'Resposta inválida da API';
      Exit;
    end;
    try
      if LRoot.GetValue('error') <> nil then
      begin
        LContent := (LRoot.GetValue('error') as TJSONObject).GetValue('message');
        if LContent <> nil then
          FLastError := LContent.Value
        else
          FLastError := 'Erro desconhecido da API';
        Exit;
      end;

      LChoices := LRoot.GetValue('choices') as TJSONArray;
      if (LChoices = nil) or (LChoices.Count = 0) then
      begin
        FLastError := 'Nenhuma resposta retornada pela API';
        Exit;
      end;

      LChoice := LChoices.Items[0] as TJSONObject;
      LMessage := LChoice.GetValue('message') as TJSONObject;
      if LMessage = nil then
      begin
        FLastError := 'Formato de resposta inesperado';
        Exit;
      end;

      LContent := LMessage.GetValue('content');
      if LContent <> nil then
        Result := Trim(LContent.Value);
    finally
      LRoot.Free;
    end;
  except
    on E: Exception do
    begin
      FLastError := 'Erro ao parsear resposta: ' + E.Message;
      Result := '';
    end;
  end;
end;

function TGhiAiSQLBuilder.BuildSQL(const ABasicSQL, AInstruction: string): string;
var
  LHTTP: TIdHTTP;
  LIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LRequestStream: TStringStream;
  LResponse: string;
  LRequestJSON: string;
  LEnc: TEncoding;
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

  if Trim(ABasicSQL) = '' then
  begin
    FLastError := 'SQL básico não informado';
    Exit;
  end;

  if Trim(AInstruction) = '' then
  begin
    FLastError := 'Instrução não informada';
    Exit;
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

    LRequestJSON := BuildRequestJSON(ABasicSQL, AInstruction);
    LEnc := TEncoding.UTF8;
    LRequestStream := TStringStream.Create(LRequestJSON, LEnc);
    try
      try
        LResponse := LHTTP.Post(FApiUrl, LRequestStream);
        Result := ParseResponseJSON(LResponse);
        // Remove possíveis marcadores de código que o modelo possa ter retornado
        Result := Trim(Result);
        if (Length(Result) >= 3) and (Copy(Result, 1, 3) = '```') then
        begin
          Result := Trim(Copy(Result, 4, Length(Result)));
          if (Length(Result) >= 4) and (LowerCase(Copy(Result, 1, 4)) = 'sql') then
            Result := Trim(Copy(Result, 5, Length(Result)));
          if (Length(Result) >= 3) and (Copy(Result, Length(Result) - 2, 3) = '```') then
            Result := Trim(Copy(Result, 1, Length(Result) - 3));
        end;
      except
        on E: Exception do
        begin
          FLastError := 'Erro na requisição: ' + E.Message;
          Result := '';
        end;
      end;
    finally
      LRequestStream.Free;
    end;
  finally
    LIOHandler.Free;
    LHTTP.Free;
  end;
end;

end.
