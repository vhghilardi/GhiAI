unit GhiAiChartEditors;

{
  Property editors para TGhiAiChart - dropdown com colunas da Query no Object Inspector.
}

interface

procedure Register;

implementation

uses
  System.Classes, System.SysUtils, DesignIntf, DesignEditors, GhiAiChart,
  Data.DB, FireDAC.Comp.Client;

type
  TGhiAiChartEixoProperty = class(TStringProperty)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

{ TGhiAiChartEixoProperty }

function TGhiAiChartEixoProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paValueList];
end;

procedure ObterColunasDoSQL(const ASQL: string; Proc: TGetStrProc);
var
  LSql, LSelect, S: string;
  P: Integer;
  LList: TArray<string>;
  LCol: string;
begin
  LSql := Trim(ASQL);
  if (LSql = '') or not LSql.StartsWith('SELECT', True) then Exit;
  P := Pos(' ', LSql);
  Delete(LSql, 1, P);
  P := Pos(' FROM ', UpperCase(LSql));
  if P <= 0 then Exit;
  LSelect := Trim(Copy(LSql, 1, P - 1));
  if LSelect = '' then Exit;
  LList := LSelect.Split([',']);
  for LCol in LList do
  begin
    S := Trim(LCol);
    if S <> '' then
    begin
      P := Pos(' AS ', UpperCase(S));
      if P > 0 then
        S := Trim(Copy(S, P + 4, MaxInt));
      if (S <> '') and not S.StartsWith('*') then
        Proc(S);
    end;
  end;
end;

procedure TGhiAiChartEixoProperty.GetValues(Proc: TGetStrProc);
var
  LChart: TGhiAiChart;
  LQuery: TFDQuery;
  I: Integer;
  LWasPrepared: Boolean;
begin
  Proc('');
  if GetComponent(0) is TGhiAiChart then
  begin
    LChart := TGhiAiChart(GetComponent(0));
    LQuery := LChart.Query;
    if LQuery = nil then Exit;

    if LQuery.Active then
    begin
      for I := 0 to LQuery.FieldCount - 1 do
        Proc(LQuery.Fields[I].FieldName);
      Exit;
    end;

    { Query nao aberta: tenta obter colunas via FieldDefs apos Prepare }
    if (LQuery.Connection <> nil) and LQuery.Connection.Connected and
       (Trim(LQuery.SQL.Text) <> '') then
    begin
      LWasPrepared := LQuery.Prepared;
      try
        if not LWasPrepared then
          LQuery.Prepare;
        for I := 0 to LQuery.FieldDefs.Count - 1 do
          Proc(LQuery.FieldDefs[I].Name);
        Exit;
      except
        { Ignora erro (ex: conexao indisponivel em design-time) }
      end;
      if not LWasPrepared and LQuery.Prepared then
        LQuery.UnPrepare;
    end;

    { Fallback: extrai colunas do texto SQL (SELECT col1, col2 FROM ...) }
    ObterColunasDoSQL(LQuery.SQL.Text, Proc);
  end;
end;

procedure Register;
begin
  RegisterPropertyEditor(TypeInfo(string), TGhiAiChart, 'EixoX', TGhiAiChartEixoProperty);
  RegisterPropertyEditor(TypeInfo(string), TGhiAiChart, 'EixoY', TGhiAiChartEixoProperty);
end;

end.
