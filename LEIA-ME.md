# Site da Eleva Evolução Imobiliária

- `imoveis/<Bairro>/<Empreendimento>/` — descricao.txt + fotos. **A fonte é a pasta `Área de Trabalho\SITE ELEVA\IMOVEIS` do computador da Eleva**; `pc/sincronizar.ps1` espelha essa pasta para cá a cada 5 minutos. Mudança feita só aqui é desfeita na próxima sincronização: altere na pasta do computador.
- `site/` — estilo.css, app.js, imagens, equipe e `config.json` (WhatsApp, CRECI, equipe).
- `ferramentas/gerar.py` — monta o site (página inicial, uma página por bairro e por empreendimento).
- `.github/workflows/publicar.yml` — a cada envio para o branch `conteudo`, gera o site e publica no branch `main` (GitHub Pages).
- `pc/` — scripts instalados no computador (`instalar.ps1` uma vez; tarefa agendada "Eleva - Publicar site").

Testar localmente: `python3 ferramentas/gerar.py /tmp/site`.
