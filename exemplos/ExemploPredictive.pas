{
  Exemplo de uso do TGhiAiPredictive (pacote GhiAI)

  Envia dados JSON para análise preditiva e retorna JSON com previsões.
  uses: GhiAiPredictive, System.JSON, Vcl.Dialogs;
}
procedure TestarGhiAiPredictive;
var
  Predictive: TGhiAiPredictive;
  JsonDados, JsonResultado: string;
  LRoot: TJSONObject;
  LTendencia: string;
begin
  Predictive := TGhiAiPredictive.Create(nil);
  try
    Predictive.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Predictive.ApiKey := 'sua-api-key-openai';
    Predictive.Timeout := 60000;

    JsonDados := '{"vendas_mensais": [12000, 13500, 14000, 13800, 15500, 16200, 15800, 17000], ' +
      '"periodo": "2024", "produto": "Eletrônicos"}';

    JsonResultado := Predictive.Prever(JsonDados);

    if JsonResultado <> '' then
    begin
      // Exemplo de parse do JSON retornado
      LRoot := TJSONObject.ParseJSONValue(JsonResultado) as TJSONObject;
      if LRoot <> nil then
      try
        if (LRoot.GetValue('tendencia') <> nil) and (LRoot.GetValue('tendencia') is TJSONString) then
          LTendencia := (LRoot.GetValue('tendencia') as TJSONString).Value
        else
          LTendencia := 'N/A';
        ShowMessage('Tendência: ' + LTendencia + sLineBreak + sLineBreak + JsonResultado);
      finally
        LRoot.Free;
      end
      else
        ShowMessage(JsonResultado);
    end
    else
      ShowMessage('Erro: ' + Predictive.LastError);
  finally
    Predictive.Free;
  end;
end;
