{
  Exemplo simples de uso do TGhiAiSQLBuilder - sem formulário
  Execute em um botão ou console para testar

  uses: GhiAiSQLBuilder, Vcl.Dialogs;
}
procedure TestarAiSQLBuilder;
var
  AiBuilder: TGhiAiSQLBuilder;
  SQLCompleto: string;
begin
  AiBuilder := TGhiAiSQLBuilder.Create(nil);
  try
    AiBuilder.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    AiBuilder.ApiKey := 'sua-api-key-aqui';  // Substitua!
    AiBuilder.Model := 'gpt-4o-mini';

    SQLCompleto := AiBuilder.BuildSQL(
      'select * from vendas',
      'me retorne a soma das vendas por semana no mês'
    );

    if SQLCompleto <> '' then
      ShowMessage('SQL gerado:' + sLineBreak + SQLCompleto)
    else
      ShowMessage('Erro: ' + AiBuilder.LastError);
  finally
    AiBuilder.Free;
  end;
end;
