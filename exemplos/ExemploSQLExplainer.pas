{
  Exemplo de uso do TGhiAiSQLExplainer (pacote GhiAI)

  Explica como cada coluna de uma query foi obtida - útil para suporte/documentação
  quando clientes perguntam "como o sistema chegou neste valor?".

  uses: GhiAiSQLExplainer, Vcl.Dialogs;
}
procedure TestarGhiAiSQLExplainer;
var
  Explainer: TGhiAiSQLExplainer;
  Explicacao: string;
begin
  Explainer := TGhiAiSQLExplainer.Create(nil);
  try
    Explainer.Query := FDQuery1;  // Vincule sua TFDQuery
    Explainer.Connection := FDConnection1;  // Opcional: schema para melhor contexto
    Explainer.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Explainer.ApiKey := 'sua-api-key-openai';
    Explainer.DatabaseType := dbFirebird;

    Explicacao := Explainer.ExplainColumns;

    if Explicacao <> '' then
      ShowMessage(Explicacao)  // ou Memo1.Text := Explicacao
    else
      ShowMessage('Erro: ' + Explainer.LastError);
  finally
    Explainer.Free;
  end;
end;

{
  Uso sem vincular Query - passando SQL diretamente:
}
procedure TestarGhiAiSQLExplainerComSQL;
var
  Explainer: TGhiAiSQLExplainer;
  Explicacao: string;
begin
  Explainer := TGhiAiSQLExplainer.Create(nil);
  try
    Explainer.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Explainer.ApiKey := 'sua-api-key-openai';

    Explicacao := Explainer.ExplainSQL(
      'SELECT c.nome AS cliente, SUM(p.valor) AS total_pedidos ' +
      'FROM clientes c INNER JOIN pedidos p ON p.id_cliente = c.id ' +
      'GROUP BY c.nome ORDER BY total_pedidos DESC');

    if Explicacao <> '' then
      Memo1.Text := Explicacao
    else
      ShowMessage('Erro: ' + Explainer.LastError);
  finally
    Explainer.Free;
  end;
end;
