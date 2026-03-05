{
  Exemplo de uso do TGhiAiSQLBuilder (pacote GhiAI)

  Adicione ao seu projeto:
  - GhiAiSQLBuilder na uses (ou instale o pacote GhiAI)
  - IdHTTP, IdSSLOpenSSL (Indy - vem com Delphi)
  - System.JSON (Delphi XE2+)
}

unit ExemploUso;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  GhiAiSQLBuilder;

type
  TFormExemplo = class(TForm)
    MemoSQL: TMemo;
    MemoResultado: TMemo;
    EditInstrucao: TEdit;
    ButtonGerar: TButton;
    GhiAiSQLBuilder1: TGhiAiSQLBuilder;
    procedure ButtonGerarClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  FormExemplo: TFormExemplo;

implementation

{$R *.dfm}

procedure TFormExemplo.FormCreate(Sender: TObject);
begin
  // Configure a API - NUNCA deixe a chave hardcoded em produção!
  // Use variáveis de ambiente ou arquivo de configuração
  GhiAiSQLBuilder1.ApiUrl := 'https://api.openai.com/v1/chat/completions';
  GhiAiSQLBuilder1.ApiKey := 'sua-api-key-aqui';  // Substitua pela sua chave
  GhiAiSQLBuilder1.Model := 'gpt-4o-mini';       // Mais barato e rápido
  GhiAiSQLBuilder1.Timeout := 60000;              // 60 segundos

  MemoSQL.Lines.Text := 'select * from vendas';
  EditInstrucao.Text := 'me retorne a soma das vendas por semana no mês';
end;

procedure TFormExemplo.ButtonGerarClick(Sender: TObject);
var
  LSQLBasico, LInstrucao, LSQLCompleto: string;
begin
  LSQLBasico := MemoSQL.Lines.Text.Trim;
  LInstrucao := EditInstrucao.Text.Trim;

  if LSQLBasico = '' then
  begin
    ShowMessage('Informe o SQL básico');
    Exit;
  end;

  if LInstrucao = '' then
  begin
    ShowMessage('Informe a instrução (ex: soma das vendas por semana no mês)');
    Exit;
  end;

  ButtonGerar.Enabled := False;
  try
    MemoResultado.Lines.Clear;
    MemoResultado.Lines.Add('Gerando SQL... Aguarde.');

    Application.ProcessMessages;

    LSQLCompleto := GhiAiSQLBuilder1.BuildSQL(LSQLBasico, LInstrucao);

    if LSQLCompleto <> '' then
      MemoResultado.Lines.Text := LSQLCompleto
    else
      MemoResultado.Lines.Text := 'Erro: ' + GhiAiSQLBuilder1.LastError;
  finally
    ButtonGerar.Enabled := True;
  end;
end;

end.
