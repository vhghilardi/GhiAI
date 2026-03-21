# GhiAI - Pacote de Componentes de IA para Delphi

Pacote **GhiAI** com componentes que integram IA (OpenAI) ao Delphi.

**Autor:** Victor Henrique Ghilardi  
**Site:** [ghiweb.com.br](https://ghiweb.com.br)

## Componentes

- **TGhiAiSQLBuilder** — Transforma SQL básico em SQL complexo via IA
- **TGhiAiSQLExplainer** — Explica como cada coluna de uma query foi obtida (para suporte/documentação)
- **TGhiAIDataJud** — Consulta processos no DataJud com resumo via IA
- **TGhiAiAnaliser** — Análise de dados via IA
- **TGhiAiPredictive** — Análise preditiva via IA
- **TGhiAiChart** — Gráfico a partir de TFDQuery com análise via IA

---

## TGhiAiSQLBuilder

Componente que usa a API OpenAI para transformar um SQL básico em um SQL complexo conforme sua instrução.

## Exemplo de Uso

**Entrada:**
- SQL básico: `select * from vendas`
- Instrução: `me retorne a soma das vendas por semana no mês`

**Saída (exemplo):** SQL completo com agrupamento por semana, algo como:
```sql
SELECT 
  DATEPART(WEEK, data_venda) AS semana,
  SUM(valor) AS total_vendas
FROM vendas
WHERE MONTH(data_venda) = MONTH(GETDATE())
  AND YEAR(data_venda) = YEAR(GETDATE())
GROUP BY DATEPART(WEEK, data_venda)
ORDER BY semana
```

## Requisitos

- Delphi XE2 ou superior (para System.JSON)
- Indy (IdHTTP, IdSSLOpenSSL) - incluído no Delphi
- Conta OpenAI com API Key

## Instalação do Pacote GhiAI

1. Abra o arquivo `GhiAI.dpk` no Delphi
2. Compile o pacote (Project → Build GhiAI)
3. Instale o pacote (Component → Install Packages → Add → selecione GhiAI.bpl)
4. Os componentes aparecerão na paleta **Ghi AI**

**Nota:** Se der erro de "Indy" ao compilar, adicione o pacote Indy ao `requires` do GhiAI.dpk (ex: `IndyCore` ou `indy`, conforme sua versão do Delphi).

## Uso Programático

```pascal
var
  AiBuilder: TGhiAiSQLBuilder;
  SQLCompleto: string;
begin
  AiBuilder := TGhiAiSQLBuilder.Create(nil);
  try
    AiBuilder.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    AiBuilder.ApiKey := 'sk-proj-...';  // Sua chave
    AiBuilder.Model := 'gpt-4o-mini';
    AiBuilder.DatabaseType := dbFirebird;  // ou dbSQLServer, dbMySQL, dbPostgreSQL

    SQLCompleto := AiBuilder.BuildSQL(
      'select * from vendas',
      'soma das vendas por semana no mês'
    );

    if SQLCompleto <> '' then
      ShowMessage(SQLCompleto)
    else
      ShowMessage('Erro: ' + AiBuilder.LastError);
  finally
    AiBuilder.Free;
  end;
end;
```

## Propriedades

| Propriedade | Descrição |
|-------------|-----------|
| Connection | Conexão com banco (opcional) - para futuras extensões com schema |
| LastError | Última mensagem de erro (read-only) |
| ApiUrl | URL da API (padrão: https://api.openai.com/v1/chat/completions) |
| ApiKey | Sua chave da OpenAI |
| Model | Modelo a usar (gpt-4o-mini, gpt-4, gpt-3.5-turbo) |
| Timeout | Timeout em ms (padrão: 60000) |
| DatabaseType | Banco de destino: dbSQLServer, dbMySQL, dbPostgreSQL, dbFirebird |

## Métodos

- **BuildSQL(ABasicSQL, AInstruction: string): string** - Retorna o SQL gerado ou vazio em caso de erro

---

## TGhiAIDataJud

Componente para consultar processos no **DataJud** (API pública do CNJ) e gerar um resumo explicativo via IA sobre o momento atual do processo.

### Configuração

| Propriedade | Descrição |
|-------------|-----------|
| DataJudApiUrl | URL da API DataJud (ex: .../api_publica_tjrs/_search para TJRS) |
| DataJudApiKey | Chave da API pública DataJud (formato: APIKey xxx) |
| OpenAIApiUrl | URL da API OpenAI para o resumo |
| OpenAIApiKey | Chave da OpenAI |
| OpenAIModel | Modelo (ex: gpt-4o-mini) |
| QuantidadeMovimentos | Quantidade de movimentações a retornar (padrão: 5) |
| Timeout | Timeout em ms (padrão: 30000) |

### Uso

```pascal
var
  DataJud: TGhiAIDataJud;
  Resultado: TGhiAIDataJudResult;
begin
  DataJud := TGhiAIDataJud.Create(nil);
  try
    DataJud.DataJudApiUrl := 'https://api-publica.datajud.cnj.jus.br/api_publica_tjrs/_search';
    DataJud.DataJudApiKey := 'APIKey sua-chave-datajud';
    DataJud.OpenAIApiUrl := 'https://api.openai.com/v1/chat/completions';
    DataJud.OpenAIApiKey := 'sk-proj-...';
    DataJud.QuantidadeMovimentos := 5;

    Resultado := DataJud.ConsultarProcesso('50038262720238210019');
    // ou: Texto := DataJud.ConsultarProcessoTexto('5003826-27.2023.8.21.0019');

    if Resultado.Sucesso then
      ShowMessage(Resultado.TextoCompleto)
    else
      ShowMessage(Resultado.MensagemErro);
  finally
    DataJud.Free;
  end;
end;
```

### Retorno (TGhiAIDataJudResult)

- **Sucesso** - Indica se a consulta foi bem-sucedida
- **TextoCompleto** - Texto formatado com todos os dados + resumo IA
- **NomeClasse, Sistema, Formato, Tribunal, OrgaoJulgador** - Dados do processo
- **DataHoraUltimaAtualizacao** - Última atualização
- **Assuntos** - Lista de assuntos
- **Movimentos** - X últimas movimentações (conforme QuantidadeMovimentos)
- **ResumoIA** - Explicação gerada pela IA sobre o momento atual do processo
- **MensagemErro** - Mensagem em caso de falha

### Endpoints por Tribunal

Altere a URL conforme o tribunal desejado:
- TJRS: `api_publica_tjrs/_search`
- STJ: `api_publica_stj/_search`
- TRF1 a TRF6: `api_publica_trf1/_search`, etc.

---

## TGhiAiAnaliser

Componente para análise de dados via IA. Recebe um JSON com dados e uma orientação (prompt), retorna a análise em **texto** ou **JSON** (configurável).

### Exemplo

Enviar vendas do ano passado e obter análise conforme o prompt definido.

### Propriedades

| Propriedade | Descrição |
|-------------|-----------|
| ApiUrl | URL da API OpenAI |
| ApiKey | Chave da OpenAI |
| Model | Modelo (ex: gpt-4o-mini) |
| Timeout | Timeout em ms (padrão: 60000) |
| RetornoComoJson | True = retorna JSON estruturado, False = retorna texto livre (padrão) |

### Uso

```pascal
var
  Analiser: TGhiAiAnaliser;
  JsonVendas, Orientacao, Analise: string;
begin
  Analiser := TGhiAiAnaliser.Create(nil);
  try
    Analiser.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Analiser.ApiKey := 'sk-proj-...';
    Analiser.RetornoComoJson := False;  // True para JSON

    JsonVendas := '{"vendas": [{"mes": "Jan", "valor": 15000}, {"mes": "Fev", "valor": 18000}, ...]}';
    Orientacao := 'Analise as vendas do ano e destaque os principais insights, tendências e recomendações';

    Analise := Analiser.Analisar(JsonVendas, Orientacao);

    if Analise <> '' then
      Memo1.Text := Analise
    else
      ShowMessage(Analiser.LastError);
  finally
    Analiser.Free;
  end;
end;
```

### Métodos

- **Analisar(AJsonDados, AOrientacao: string): string** - Retorna análise em texto ou JSON conforme RetornoComoJson

---

## TGhiAiPredictive

Componente para análise preditiva via IA. Recebe dados em JSON, envia para a IA fazer análise preditiva e retorna um **JSON** com previsões, tendências e cenários.

### Propriedades

| Propriedade | Descrição |
|-------------|-----------|
| ApiUrl | URL da API OpenAI |
| ApiKey | Chave da OpenAI |
| Model | Modelo (ex: gpt-4o-mini) |
| Timeout | Timeout em ms (padrão: 60000) |
| FormatoRetorno | preCompleto (previsoes, tendencia, cenários, confianca, observacoes) ou preSimplificado (previsoes, tendencia, observacoes) |
| ContextoAnalise | Tipo/período da análise (ex: "3 meses à frente", "7 dias", "próximos 5 meses") |

### Uso

```pascal
var
  Predictive: TGhiAiPredictive;
  JsonDados, JsonResultado: string;
begin
  Predictive := TGhiAiPredictive.Create(nil);
  try
    Predictive.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Predictive.ApiKey := 'sk-proj-...';
    Predictive.ContextoAnalise := '3 meses à frente';  // Define o período da previsão

    JsonDados := '{"vendas_mensais": [12000, 13500, 14000, 13800, 15500, 16200], "periodo": "2024"}';

    JsonResultado := Predictive.Prever(JsonDados);

    if JsonResultado <> '' then
      // Parse JSON: previsoes, tendencia, cenarioOtimista, cenarioPessimista, confianca, observacoes
      Memo1.Text := JsonResultado
    else
      ShowMessage(Predictive.LastError);
  finally
    Predictive.Free;
  end;
end;
```

### Retorno (JSON)

O JSON retornado inclui tipicamente:
- **previsoes** - Array com valores/tendências projetados
- **tendencia** - alta/estável/baixa
- **cenarioOtimista** - Projeção otimista
- **cenarioPessimista** - Projeção pessimista
- **confianca** - Nível de confiança (0-100)
- **observacoes** - Array de strings com recomendações

### Métodos

- **Prever(AJsonDados: string): string** - Retorna JSON com previsões

---

## TGhiAiChart

Componente para exibir gráfico de barras a partir de TFDQuery, com botão para análise via IA (OpenAI).

### Propriedades

| Propriedade | Descrição |
|-------------|-----------|
| Query | TFDQuery com os dados |
| EixoX | Nome da coluna para eixo X (labels) - dropdown no Object Inspector quando Query está aberta |
| EixoY | Nome da coluna para eixo Y (valores) - dropdown no Object Inspector quando Query está aberta |
| TipoGrafico | ctBarras, ctLinhas ou ctPizza |
| Panel | TPanel onde o gráfico será renderizado |
| ApiUrl | URL da API OpenAI |
| ApiKey | Chave da API OpenAI |
| Model | Modelo (ex: gpt-4o-mini) |
| Timeout | Timeout em ms |

### Uso

```pascal
var
  Chart: TGhiAiChart;
begin
  Chart := TGhiAiChart.Create(nil);
  try
    Chart.Query := FDQuery1;
    Chart.EixoX := 'mes';
    Chart.EixoY := 'valor';
    Chart.Panel := Panel1;
    Chart.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Chart.ApiKey := 'sk-proj-...';

    Chart.Executar;  // Exibe gráfico e botão "Analisar com IA"
  finally
    Chart.Free;
  end;
end;
```

O botão "Analisar com IA" no canto superior direito abre um diálogo para o prompt. Ao enviar, os dados do gráfico são enviados para a OpenAI e a análise é exibida em uma nova janela.

**Seleção de colunas:** No Object Inspector, EixoX e EixoY exibem dropdown com as colunas da Query (quando a Query está aberta/ativa). Em runtime, use `ConfigurarEixos` para exibir um diálogo com combos, ou `GetColunasDisponiveis` para obter a lista e popular seus próprios combos.

---

## TGhiAiSQLExplainer

Componente para **explicar como cada coluna** de uma query SQL foi obtida. Resolve o problema de clientes acionando suporte perguntando "como o sistema chegou no valor desta coluna?" — a IA analisa o SQL e retorna uma explicação detalhada de cada coluna do resultado.

### Propriedades

| Propriedade | Descrição |
|-------------|-----------|
| Query | TFDQuery com o SQL a ser explicado (obtém de Query.SQL.Text) |
| Connection | TFDConnection opcional — fornece schema das tabelas para melhor contexto |
| ApiUrl | URL da API OpenAI |
| ApiKey | Chave da OpenAI |
| Model | Modelo (ex: gpt-4o-mini) |
| Timeout | Timeout em ms (padrão: 60000) |
| DatabaseType | Banco: dbSQLServer, dbMySQL, dbPostgreSQL, dbFirebird |

### Uso

```pascal
var
  Explainer: TGhiAiSQLExplainer;
  Explicacao: string;
begin
  Explainer := TGhiAiSQLExplainer.Create(nil);
  try
    Explainer.Query := FDQuery1;  // Query com o SQL
    Explainer.Connection := FDConnection1;  // Opcional: schema para contexto
    Explainer.ApiUrl := 'https://api.openai.com/v1/chat/completions';
    Explainer.ApiKey := 'sk-proj-...';
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
```

### Uso sem vincular Query (SQL direto)

```pascal
Explicacao := Explainer.ExplainSQL('SELECT c.nome, SUM(p.valor) AS total FROM clientes c JOIN pedidos p ON p.id_cliente = c.id GROUP BY c.nome');
```

### Métodos

- **ExplainColumns: string** — Usa a Query vinculada, retorna explicação de cada coluna
- **ExplainSQL(ASQL: string): string** — Explica um SQL passado diretamente (sem vincular Query)

### Exemplo de saída

Para um SQL como `SELECT mes, SUM(valor) AS total FROM vendas GROUP BY mes`, a IA pode retornar algo como:

> **mes**: Valor obtido diretamente da coluna "mes" da tabela vendas. Representa o mês de cada venda.
>
> **total**: Soma de todos os valores da coluna "valor" da tabela vendas, agrupados por mês. É um valor calculado que representa o total de vendas em cada mês.

---

## Adicionando Novos Componentes ao Pacote

Para adicionar novos componentes ao pacote GhiAI:

1. Crie a nova unit (ex: `GhiAiOutroComponente.pas`) na mesma pasta do pacote
2. Abra `GhiAI.dpk` e adicione a unit na cláusula `contains`:
   ```delphi
   contains
     GhiAiSQLBuilder in 'GhiAiSQLBuilder.pas',
     GhiAIDataJud in 'GhiAIDataJud.pas',
     GhiAiAnaliser in 'GhiAiAnaliser.pas',
     GhiAiPredictive in 'GhiAiPredictive.pas',
     GhiAiOutroComponente in 'GhiAiOutroComponente.pas';
   ```
3. No `Register` da nova unit, use a mesma paleta: `RegisterComponents('Ghi AI', [TSeuComponente]);`
4. Recompile e reinstale o pacote

## Segurança

⚠️ **NUNCA** deixe a ApiKey hardcoded em produção. Use:
- Variáveis de ambiente
- Arquivo de configuração criptografado
- Serviço de secrets
