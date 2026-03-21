unit GhiAiSQLExplainer;

{
  TGhiAiSQLExplainer - Componente Delphi para explicar como cada coluna de uma
  query SQL foi obtida, usando a API OpenAI. Parte do pacote GhiAI.

  Resolve o problema de clientes acionando suporte perguntando "como o sistema
  chegou no valor desta coluna?" - a IA analisa o SQL e retorna explicacao
  detalhada de cada coluna do resultado.

  Uso:
  1. Vincule Query (TFDQuery com SQL definido)
  2. Opcional: vincule Connection (TFDConnection) para contexto do schema
  3. Defina ApiUrl e ApiKey
  4. Chame ExplainColumns - retorna texto explicando cada coluna
}

interface

uses
  System.Classes, System.SysUtils, System.JSON, System.Generics.Collections, Data.DB,
  IdHTTP, IdSSLOpenSSL, FireDAC.Comp.Client;

type
  TGhiAiDatabaseType = (dbSQLServer, dbMySQL, dbPostgreSQL, dbFirebird);

  TGhiAiSQLExplainer = class(TComponent)
  private
    FQuery: TFDQuery;
    FConnection: TCustomConnection;
    FApiUrl: string;
    FApiKey: string;
    FModel: string;
    FLastError: string;
    FTimeout: Integer;
    FDatabaseType: TGhiAiDatabaseType;
    procedure SetQuery(const Value: TFDQuery);
    procedure SetConnection(const Value: TCustomConnection);
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function GetDatabaseTypeHint: string;
    function ExtractTableNamesFromSQL(const ASQL: string): TArray<string>;
    function GetTableColumns(const ATableName: string; out AColumns: TArray<string>): Boolean;
    function BuildSchemaContext(const ATableNames: TArray<string>): string;
    function GetColumnNamesFromQuery: TArray<string>;
    function GetColumnNamesFromSQL(const ASQL: string): TArray<string>;
    function BuildRequestJSON(const ASQL: string; const AColumnNames: TArray<string>;
      const ASchemaContext: string): string;
    function ParseResponseJSON(const AResponse: string): string;
    function DoExplain(const ASQL: string; const AColumnNames: TArray<string>;
      const ASchemaContext: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// Explica como cada coluna do resultado da Query foi obtida.
    /// Usa Query.SQL.Text e envia para a IA retornar explicacao detalhada.
    /// </summary>
    /// <returns>Texto explicando cada coluna ou vazio em caso de erro</returns>
    function ExplainColumns: string;
    /// <summary>
    /// Explica como cada coluna do SQL foi obtida (sem vincular Query).
    /// </summary>
    /// <param name="ASQL">SQL a ser explicado</param>
    /// <returns>Texto explicando cada coluna ou vazio em caso de erro</returns>
    function ExplainSQL(const ASQL: string): string;
    property LastError: string read FLastError;
  published
    /// <summary>Query (TFDQuery) com o SQL a ser explicado. O SQL e obtido de Query.SQL.Text</summary>
    property Query: TFDQuery read FQuery write SetQuery;
    /// <summary>Conexao (TFDConnection) opcional - fornece schema das tabelas para melhor contexto</summary>
    property Connection: TCustomConnection read FConnection write SetConnection;
    /// <summary>URL da API OpenAI (ex: https://api.openai.com/v1/chat/completions)</summary>
    property ApiUrl: string read FApiUrl write FApiUrl;
    /// <summary>Chave de API da OpenAI</summary>
    property ApiKey: string read FApiKey write FApiKey;
    /// <summary>Modelo a usar (ex: gpt-4o-mini, gpt-4, gpt-3.5-turbo)</summary>
    property Model: string read FModel write FModel;
    /// <summary>Timeout da requisicao em milissegundos</summary>
    property Timeout: Integer read FTimeout write FTimeout default 60000;
    /// <summary>Banco de dados (SQL Server, MySQL, PostgreSQL, Firebird)</summary>
    property DatabaseType: TGhiAiDatabaseType read FDatabaseType write FDatabaseType default dbSQLServer;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Ghi AI', [TGhiAiSQLExplainer]);
end;

{ TGhiAiSQLExplainer }

constructor TGhiAiSQLExplainer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FQuery := nil;
  FConnection := nil;
  FApiUrl := 'https://api.openai.com/v1/chat/completions';
  FApiKey := '';
  FModel := 'gpt-4o-mini';
  FTimeout := 60000;
  FDatabaseType := dbSQLServer;
  FLastError := '';
end;

destructor TGhiAiSQLExplainer.Destroy;
begin
  SetQuery(nil);
  inherited;
end;

procedure TGhiAiSQLExplainer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FQuery then FQuery := nil;
    if AComponent = FConnection then FConnection := nil;
  end;
end;

procedure TGhiAiSQLExplainer.SetQuery(const Value: TFDQuery);
begin
  if FQuery <> Value then
  begin
    if FQuery <> nil then FQuery.RemoveFreeNotification(Self);
    FQuery := Value;
    if FQuery <> nil then FQuery.FreeNotification(Self);
  end;
end;

procedure TGhiAiSQLExplainer.SetConnection(const Value: TCustomConnection);
begin
  if FConnection <> Value then
  begin
    if FConnection <> nil then FConnection.RemoveFreeNotification(Self);
    FConnection := Value;
    if FConnection <> nil then FConnection.FreeNotification(Self);
  end;
end;

function TGhiAiSQLExplainer.GetDatabaseTypeHint: string;
begin
  case FDatabaseType of
    dbSQLServer:   Result := 'SQL Server (T-SQL)';
    dbMySQL:       Result := 'MySQL';
    dbPostgreSQL: Result := 'PostgreSQL';
    dbFirebird:    Result := 'Firebird';
  else
    Result := 'SQL padrao';
  end;
end;

function TGhiAiSQLExplainer.ExtractTableNamesFromSQL(const ASQL: string): TArray<string>;
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

function TGhiAiSQLExplainer.GetTableColumns(const ATableName: string; out AColumns: TArray<string>): Boolean;
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

function TGhiAiSQLExplainer.BuildSchemaContext(const ATableNames: TArray<string>): string;
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

function TGhiAiSQLExplainer.GetColumnNamesFromQuery: TArray<string>;
var
  LList: TList<string>;
  I: Integer;
  LWasPrepared: Boolean;
begin
  Result := nil;
  if FQuery = nil then Exit;

  if FQuery.Active then
  begin
    SetLength(Result, FQuery.FieldCount);
    for I := 0 to FQuery.FieldCount - 1 do
      Result[I] := FQuery.Fields[I].FieldName;
    Exit;
  end;

  if (FQuery.Connection <> nil) and FQuery.Connection.Connected and
     (Trim(FQuery.SQL.Text) <> '') then
  begin
    LWasPrepared := FQuery.Prepared;
    try
      if not LWasPrepared then FQuery.Prepare;
      SetLength(Result, FQuery.FieldDefs.Count);
      for I := 0 to FQuery.FieldDefs.Count - 1 do
        Result[I] := FQuery.FieldDefs[I].Name;
      if not LWasPrepared and FQuery.Prepared then
        FQuery.UnPrepare;
    except
      Result := GetColumnNamesFromSQL(FQuery.SQL.Text);
    end;
    Exit;
  end;

  Result := GetColumnNamesFromSQL(FQuery.SQL.Text);
end;

function TGhiAiSQLExplainer.GetColumnNamesFromSQL(const ASQL: string): TArray<string>;
var
  LList: TList<string>;
  LSql, LSelect, S: string;
  P: Integer;
  LParts: TArray<string>;
  LCol: string;
begin
  Result := nil;
  LSql := Trim(ASQL);
  if (LSql = '') or not LSql.StartsWith('SELECT', True) then Exit;
  P := Pos(' ', LSql);
  Delete(LSql, 1, P);
  P := Pos(' FROM ', UpperCase(LSql));
  if P <= 0 then Exit;
  LSelect := Trim(Copy(LSql, 1, P - 1));
  if LSelect = '' then Exit;
  LList := TList<string>.Create;
  try
    LParts := LSelect.Split([',']);
    for LCol in LParts do
    begin
      S := Trim(LCol);
      if S <> '' then
      begin
        P := Pos(' AS ', UpperCase(S));
        if P > 0 then
          S := Trim(Copy(S, P + 4, MaxInt));
        if (S <> '') and not S.StartsWith('*') then
          LList.Add(S);
      end;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TGhiAiSQLExplainer.BuildRequestJSON(const ASQL: string; const AColumnNames: TArray<string>;
  const ASchemaContext: string): string;
var
  LRoot, LMsgSystem, LMsgUser: TJSONObject;
  LMessages: TJSONArray;
  LContent, LColList: string;
  I: Integer;
begin
  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('model', FModel);
    LRoot.AddPair('temperature', TJSONNumber.Create(0.2));
    LRoot.AddPair('max_tokens', TJSONNumber.Create(4000));

    LMessages := TJSONArray.Create;

    LContent := 'Voce e um especialista em SQL e documentacao tecnica. Sua tarefa e explicar, de forma ' +
      'clara e objetiva, COMO cada coluna do resultado da query foi obtida. ' +
      'Para cada coluna, explique: de qual tabela/campo vem, se e resultado de funcao (SUM, COUNT, etc.), ' +
      'se envolve JOIN, subquery, expressao calculada, ou alias. ' +
      'Use linguagem acessivel para que um usuario leigo ou suporte consiga entender. ' +
      'Formato: para cada coluna, use um titulo como "**NomeDaColuna**:" seguido da explicacao em 1-3 frases. ' +
      'Banco: ' + GetDatabaseTypeHint + '. ' +
      'Retorne APENAS o texto explicativo, sem markdown extra, sem blocos de codigo.';

    if ASchemaContext <> '' then
      LContent := LContent + sLineBreak + sLineBreak +
        'Contexto do schema (tabelas e colunas existentes):' + sLineBreak + ASchemaContext;

    LMsgSystem := TJSONObject.Create;
    LMsgSystem.AddPair('role', 'system');
    LMsgSystem.AddPair('content', LContent);
    LMessages.AddElement(LMsgSystem);

    LColList := '';
    if Length(AColumnNames) > 0 then
    begin
      for I := 0 to High(AColumnNames) do
      begin
        if LColList <> '' then LColList := LColList + ', ';
        LColList := LColList + AColumnNames[I];
      end;
      LContent := Format('SQL da query:' + sLineBreak + '%s' + sLineBreak + sLineBreak +
        'Colunas do resultado (na ordem): %s' + sLineBreak + sLineBreak +
        'Explique como cada uma dessas colunas foi obtida.',
        [ASQL.Trim, LColList]);
    end
    else
      LContent := Format('SQL da query:' + sLineBreak + '%s' + sLineBreak + sLineBreak +
        'Explique como cada coluna do resultado foi obtida.',
        [ASQL.Trim]);

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

function TGhiAiSQLExplainer.ParseResponseJSON(const AResponse: string): string;
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
      FLastError := 'Resposta invalida da API';
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

function TGhiAiSQLExplainer.ExplainColumns: string;
var
  LSQL: string;
  LColumnNames: TArray<string>;
  LSchemaContext: string;
  LTableNames: TArray<string>;
begin
  Result := '';
  FLastError := '';

  if FQuery = nil then
  begin
    FLastError := 'Query nao vinculada';
    Exit;
  end;

  LSQL := Trim(FQuery.SQL.Text);
  if LSQL = '' then
  begin
    FLastError := 'Query nao possui SQL definido';
    Exit;
  end;

  if Trim(FApiUrl) = '' then
  begin
    FLastError := 'ApiUrl nao configurada';
    Exit;
  end;

  if Trim(FApiKey) = '' then
  begin
    FLastError := 'ApiKey nao configurada';
    Exit;
  end;

  LColumnNames := GetColumnNamesFromQuery;
  LTableNames := ExtractTableNamesFromSQL(LSQL);
  LSchemaContext := BuildSchemaContext(LTableNames);

  Result := DoExplain(LSQL, LColumnNames, LSchemaContext);
end;

function TGhiAiSQLExplainer.ExplainSQL(const ASQL: string): string;
var
  LSQL: string;
  LColumnNames: TArray<string>;
  LSchemaContext: string;
  LTableNames: TArray<string>;
begin
  Result := '';
  FLastError := '';

  LSQL := Trim(ASQL);
  if LSQL = '' then
  begin
    FLastError := 'SQL nao informado';
    Exit;
  end;

  if Trim(FApiUrl) = '' then
  begin
    FLastError := 'ApiUrl nao configurada';
    Exit;
  end;

  if Trim(FApiKey) = '' then
  begin
    FLastError := 'ApiKey nao configurada';
    Exit;
  end;

  LColumnNames := GetColumnNamesFromSQL(LSQL);
  LTableNames := ExtractTableNamesFromSQL(LSQL);
  LSchemaContext := BuildSchemaContext(LTableNames);

  Result := DoExplain(LSQL, LColumnNames, LSchemaContext);
end;

function TGhiAiSQLExplainer.DoExplain(const ASQL: string; const AColumnNames: TArray<string>;
  const ASchemaContext: string): string;
var
  LHTTP: TIdHTTP;
  LIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LRequestStream: TStringStream;
  LResponse: string;
  LRequestJSON: string;
  LEnc: TEncoding;
begin
  Result := '';
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

    LRequestJSON := BuildRequestJSON(ASQL, AColumnNames, ASchemaContext);
    LEnc := TEncoding.UTF8;
    LRequestStream := TStringStream.Create(LRequestJSON, LEnc);
    try
      try
        LResponse := LHTTP.Post(FApiUrl, LRequestStream);
        Result := ParseResponseJSON(LResponse);
      except
        on E: Exception do
        begin
          FLastError := 'Erro na requisicao: ' + E.Message;
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
