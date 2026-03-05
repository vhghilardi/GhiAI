{
  Exemplo de uso do TGhiAiChart (pacote GhiAI)

  Exibe gráfico de barras a partir de TFDQuery com botão para análise via IA.
  uses: GhiAiChart, FireDAC.Comp.Client, FireDAC.Stan.Param, FireDAC.Phys;
}
procedure TestarGhiAiChart;
var
  Chart: TGhiAiChart;
  Query: TFDQuery;
  Conn: TFDConnection;
  Panel: TPanel;
begin
  Conn := TFDConnection.Create(nil);
  Query := TFDQuery.Create(nil);
  Query.Connection := Conn;
  Conn.Params.Values['DriverID'] := 'SQLite';
  Conn.Params.Values['Database'] := 'caminho\para\seu\banco.db';
  Conn.Connected := True;

  Query.SQL.Text := 'SELECT mes, valor FROM vendas ORDER BY mes';
  Query.Open;

  Panel := TPanel.Create(nil);  // Ou use um Panel do formulário
  Panel.Parent := Application.MainForm;
  Panel.Align := alClient;

  Chart := TGhiAiChart.Create(nil);
  try
    Chart.Query := Query;
    Chart.EixoX := 'mes';
    Chart.EixoY := 'valor';
    Chart.Panel := Panel;
    Chart.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Chart.ApiKey := 'sua-api-key-openai';

    Chart.Executar;

    // O gráfico é exibido no Panel. Clique em "Analisar com IA" para
    // abrir o prompt e enviar os dados para análise.
  finally
    Chart.Free;
  end;
end;
