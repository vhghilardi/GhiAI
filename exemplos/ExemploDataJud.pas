{
  Exemplo de uso do TGhiAIDataJud (pacote GhiAI)

  Consulta processo no DataJud e gera resumo pela IA.
  uses: GhiAIDataJud, Vcl.Dialogs;
}
procedure TestarGhiAIDataJud;
var
  DataJud: TGhiAIDataJud;
  Resultado: TGhiAIDataJudResult;
begin
  DataJud := TGhiAIDataJud.Create(nil);
  try
    DataJud.DataJudApiUrl := 'https://api-publica.datajud.cnj.jus.br/api_publica_tjrs/_search';
    DataJud.DataJudApiKey := 'APIKey sua-chave-datajud';  // Chave do CNJ
    DataJud.OpenAIApiUrl := 'https://api.openai.com/v1/chat/completions';
    DataJud.OpenAIApiKey := 'sua-api-key-openai';
    DataJud.QuantidadeMovimentos := 5;  // Últimas 5 movimentações
    DataJud.Timeout := 30000;

    Resultado := DataJud.ConsultarProcesso('50038262720238210019');
    // Aceita com ou sem formatação: 5003826-27.2023.8.21.0019

    if Resultado.Sucesso then
      ShowMessage(Resultado.TextoCompleto)
    else
      ShowMessage('Erro: ' + Resultado.MensagemErro);

    // Ou use a versão simplificada que retorna apenas o texto:
    // ShowMessage(DataJud.ConsultarProcessoTexto('5003826-27.2023.8.21.0019'));
  finally
    DataJud.Free;
  end;
end;
