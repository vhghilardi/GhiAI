{
  Exemplo de uso do TGhiAiAnaliser (pacote GhiAI)

  Analisa dados JSON conforme orientação e retorna texto ou JSON.
  uses: GhiAiAnaliser, Vcl.Dialogs;
}
procedure TestarGhiAiAnaliser;
var
  Analiser: TGhiAiAnaliser;
  JsonVendas, Orientacao, Analise: string;
begin
  Analiser := TGhiAiAnaliser.Create(nil);
  try
    Analiser.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Analiser.ApiKey := 'sua-api-key-openai';
    Analiser.RetornoComoJson := False;  // True para retornar JSON estruturado
    Analiser.Timeout := 60000;

    JsonVendas := '{"vendas_2024": [' +
      '{"mes": "Jan", "valor": 15000, "qtd": 120}, ' +
      '{"mes": "Fev", "valor": 18000, "qtd": 145}, ' +
      '{"mes": "Mar", "valor": 16500, "qtd": 132}, ' +
      '{"mes": "Abr", "valor": 22000, "qtd": 178}]}';

    Orientacao := 'Analise as vendas e destaque os principais insights, tendências e recomendações para o próximo trimestre';

    Analise := Analiser.Analisar(JsonVendas, Orientacao);

    if Analise <> '' then
      ShowMessage(Analise)
    else
      ShowMessage('Erro: ' + Analiser.LastError);
  finally
    Analiser.Free;
  end;
end;
