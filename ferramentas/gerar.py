#!/usr/bin/env python3
"""Gera o site da Eleva a partir das pastas imoveis/<Bairro>/<Empreendimento>/.

Cada pasta de empreendimento tem um arquivo de texto (descricao.txt) e as fotos.
Uso:  python3 ferramentas/gerar.py [pasta_de_saida]     (padrao: _site)
Nunca falha por causa de conteudo: pasta com problema e avisada e pulada.
"""
import html, json, os, re, shutil, sys, unicodedata
from datetime import date
from pathlib import Path
from PIL import Image, ImageOps

RAIZ = Path(__file__).resolve().parent.parent
FONTE = RAIZ / "imoveis"
SITE = RAIZ / "site"
SAIDA = Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / "_site"
CFG = json.loads((SITE / "config.json").read_text(encoding="utf-8"))
URL = CFG["url"].rstrip("/") + "/"
WA = CFG["whatsapp"]
EXT_FOTO = {".jpg", ".jpeg", ".png", ".webp", ".jfif", ".bmp"}
AVISOS = []

# Preposicao certa para os bairros de Maceio ("na Jatiuca", "no Farol"...).
PREP = {"jatiuca": "na", "pajucara": "na", "ponta-verde": "na", "mangabeiras": "em", "poco": "no",
        "farol": "no", "tabuleiro-do-martins": "no", "centro": "no", "pinheiro": "no", "prado": "no",
        "barro-duro": "no", "feitosa": "no", "jacintinho": "no", "trapiche-da-barra": "no",
        "benedito-bentes": "no", "antares": "em", "serraria": "na", "gruta-de-lourdes": "na",
        "garca-torta": "na", "santa-amelia": "na", "cidade-universitaria": "na", "ponta-da-terra": "na",
        "pitanguinha": "na", "santa-lucia": "na", "clima-bom": "no", "jardim-petropolis": "no",
        "sao-jorge": "no", "petropolis": "em"}


def e(t):
    return html.escape(str(t), quote=True)


def slug(t):
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-") or "imovel"


def sem_acento(t):
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower().strip()


def ordem_natural(p):
    return [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", p.name.lower())]


def ler_texto(p):
    b = p.read_bytes()
    for enc in ("utf-8-sig", "utf-16", "cp1252"):
        try:
            return b.decode(enc)
        except (UnicodeDecodeError, UnicodeError):
            pass
    return b.decode("utf-8", "replace")


def ler_preco(v):
    """'390.425,75' -> 390425.75 ; '390 mil' -> 390000 ; texto sem numero -> None."""
    t = sem_acento(v).replace("r$", "")
    m = re.search(r"\d[\d.,]*", t)
    if not m:
        return None
    n = m.group().rstrip(".,")
    if "," in n:
        n = n.replace(".", "").replace(",", ".")
    elif re.fullmatch(r"\d{1,3}(\.\d{3})+", n):
        n = n.replace(".", "")
    try:
        x = float(n)
    except ValueError:
        return None
    resto = t[m.end():]
    if re.match(r"\s*(mi\b|milh)", resto):
        x *= 1_000_000
    elif re.match(r"\s*mil\b", resto):
        x *= 1_000
    return x if x >= 1000 else None


def brl(x):
    return "R$ " + f"{round(x):,}".replace(",", ".")


CHAVES = {"nome": "nome", "empreendimento": "nome", "titulo": "nome",
          "construtora": "construtora", "incorporadora": "construtora",
          "preco": "preco", "valor": "preco", "a partir de": "preco",
          "selo": "selo", "etiqueta": "selo", "tag": "selo", "status": "selo",
          "endereco": "endereco", "localizacao": "endereco",
          "quartos": "quartos", "dormitorios": "quartos", "suites": "suites",
          "area": "area", "metragem": "area", "tamanho": "area",
          "vagas": "vagas", "garagem": "vagas", "entrega": "entrega", "previsao de entrega": "entrega",
          "destaque": "destaque", "resumo": "resumo", "chamada": "resumo"}
ROTULOS = [("quartos", "Quartos"), ("suites", "Suítes"), ("area", "Área"), ("vagas", "Vagas"),
           ("entrega", "Entrega"), ("endereco", "Endereço"), ("construtora", "Construtora")]


def ler_imovel(pasta, bairro):
    txts = sorted([p for p in pasta.iterdir() if p.is_file() and p.suffix.lower() in (".txt", ".md")],
                  key=lambda p: (not p.stem.lower().startswith("descri"), p.name.lower()))
    campos, extras, corpo = {}, [], []
    if txts:
        linhas = ler_texto(txts[0]).replace("\r", "").split("\n")
        i = 0
        while i < len(linhas):
            l = linhas[i].strip()
            m = re.match(r"^([^:]{2,28}):\s*(.*)$", l)
            if not l and not corpo:
                i += 1
                continue
            if m and not corpo:
                k, v = sem_acento(m.group(1)), m.group(2).strip()
                if k in CHAVES:
                    if v:
                        campos[CHAVES[k]] = v
                elif v and len(v) <= 60 and len(extras) < 8 and not l.lower().startswith("http"):
                    extras.append((m.group(1).strip(), v))
                else:
                    corpo.append(l)
                i += 1
                continue
            corpo = [x.rstrip() for x in linhas[i:]]
            break
    fotos = sorted([p for p in pasta.rglob("*") if p.is_file() and p.suffix.lower() in EXT_FOTO
                    and not any(x.startswith(("_", ".")) for x in p.relative_to(pasta).parts)], key=ordem_natural)
    fotos.sort(key=lambda p: not p.stem.lower().startswith("capa"))
    if not fotos:
        AVISOS.append(f"{bairro} / {pasta.name}: sem fotos, ficou fora do site.")
        return None
    nome = campos.get("nome") or pasta.name.strip()
    paragrafos, bloco = [], []
    for l in corpo + [""]:
        if l.strip():
            bloco.append(l.strip())
        elif bloco:
            paragrafos.append(bloco)
            bloco = []
    preco = ler_preco(campos["preco"]) if "preco" in campos else None
    resumo = campos.get("resumo") or (" ".join(paragrafos[0]) if paragrafos else "")
    resumo = re.sub(r"^[-•*]\s*", "", resumo)
    if len(resumo) > 150:
        resumo = resumo[:147].rsplit(" ", 1)[0].rstrip(",.;") + "…"
    return {"nome": nome, "bairro": bairro, "pasta": pasta, "fotos": fotos, "campos": campos, "extras": extras,
            "paragrafos": paragrafos, "preco": preco, "resumo": resumo, "selo": campos.get("selo"),
            "destaque": sem_acento(campos.get("destaque", "")) in ("sim", "s", "x", "1", "true"),
            "mtime": max(p.stat().st_mtime for p in fotos)}


def carregar():
    imoveis = []
    if not FONTE.is_dir():
        return imoveis
    for b in sorted(FONTE.iterdir(), key=lambda p: sem_acento(p.name)):
        if not b.is_dir() or b.name.startswith(("_", ".")):
            continue
        for p in sorted(b.iterdir(), key=lambda p: sem_acento(p.name)):
            if not p.is_dir() or p.name.startswith(("_", ".")):
                continue
            try:
                im = ler_imovel(p, b.name.strip())
            except Exception as ex:  # conteudo nunca derruba a publicacao
                AVISOS.append(f"{b.name} / {p.name}: nao foi possivel ler ({ex}).")
                im = None
            if im:
                imoveis.append(im)
    usados = {}
    for im in imoveis:
        s = slug(im["nome"])
        if s in usados:
            s = f"{s}-{slug(im['bairro'])}"
        while s in usados:
            s += "-2"
        usados[s] = 1
        im["slug"] = s
        im["bslug"] = slug(im["bairro"])
    return imoveis


def gravar_fotos(im):
    """Grava cada foto em dois tamanhos: grande (1800px) e pequena (800px)."""
    dst = SAIDA / "imoveis" / im["slug"] / "f"
    dst.mkdir(parents=True, exist_ok=True)
    saida = []
    for p in im["fotos"]:
        try:
            img = ImageOps.exif_transpose(Image.open(p))
            if img.mode in ("RGBA", "LA", "P"):
                img = img.convert("RGBA")
                fundo = Image.new("RGB", img.size, "#ffffff")
                fundo.paste(img, mask=img.split()[-1])
                img = fundo
            else:
                img = img.convert("RGB")
            if min(img.size) < 200:
                continue
            n = f"{len(saida) + 1:02d}"
            g = img.copy(); g.thumbnail((1800, 1800), Image.LANCZOS)
            g.save(dst / f"{n}.jpg", "JPEG", quality=84, optimize=True, progressive=True)
            s = img.copy(); s.thumbnail((800, 800), Image.LANCZOS)
            s.save(dst / f"{n}-p.jpg", "JPEG", quality=80, optimize=True, progressive=True)
            saida.append({"g": f"f/{n}.jpg", "p": f"f/{n}-p.jpg", "w": g.width, "h": g.height})
        except Exception as ex:
            AVISOS.append(f"{im['bairro']} / {im['nome']}: foto {p.name} ignorada ({ex}).")
    im["img"] = saida
    return bool(saida)


def prep(b):
    return PREP.get(slug(b), "em")


def wa(txt):
    from urllib.parse import quote
    return f"https://wa.me/{WA}?text={quote(txt)}"


def fone():
    return f"({WA[2:4]}) {WA[4:9]}-{WA[9:]}"


def pagina(r, titulo, desc, corpo, caminho="", og=None, extra_head=""):
    """r = prefixo relativo ate a raiz ('' ou '../../')."""
    ogimg = URL + (og or "img/mcz.jpg")
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(titulo)}</title>
<meta name="description" content="{e(desc)}">
<link rel="canonical" href="{URL}{caminho}">
<meta property="og:type" content="website">
<meta property="og:locale" content="pt_BR">
<meta property="og:site_name" content="{e(CFG['nome'])}">
<meta property="og:title" content="{e(titulo)}">
<meta property="og:description" content="{e(desc)}">
<meta property="og:url" content="{URL}{caminho}">
<meta property="og:image" content="{ogimg}">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#2B3578">
<link rel="icon" href="{r}img/favicon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,300..700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="{r}estilo.css?v={VERSAO}">
{extra_head}</head>
<body>
<a class="pular" href="#conteudo">Ir para o conteúdo</a>
<header class="topo">
  <div class="faixa topo-in">
    <a class="marca" href="{r or './'}" aria-label="{e(CFG['nome'])}, página inicial"><img src="{r}img/logo.png" alt="{e(CFG['nome'])}" width="170" height="42"></a>
    <button class="menu-btn" aria-expanded="false" aria-controls="menu">Menu</button>
    <nav id="menu" class="menu" aria-label="Principal">
      <div class="sub"><button type="button" class="sub-btn" aria-expanded="false">Imóveis</button>
        <ul class="sub-lista">{RODAPE_BAIRROS.replace('{r}', r)}<li class="sub-todos"><a href="{r}#imoveis">Ver todos os imóveis</a></li></ul></div>
      <a href="{r}#eleva">A Eleva</a>
      <a href="{r}#depoimentos">Depoimentos</a>
      <a href="{r}#simulacao">Simulação</a>
      <a href="{r}#equipe">Equipe</a>
      <a class="menu-wa" href="{wa('Olá! Vim pelo site da Eleva.')}" target="_blank" rel="noopener">WhatsApp {fone()}</a>
    </nav>
  </div>
</header>
<main id="conteudo">
{corpo}
</main>
<footer class="rodape">
  <div class="faixa rodape-in">
    <div>
      <img src="{r}img/logo.png" alt="{e(CFG['nome'])}" width="150" height="37" loading="lazy">
      <p>CRECI {e(CFG['creci'])}</p>
    </div>
    <div>
      <h2>Fale conosco</h2>
      <p><a href="{wa('Olá! Vim pelo site da Eleva.')}" target="_blank" rel="noopener">WhatsApp {fone()}</a><br>
      <a href="https://www.instagram.com/{e(CFG['instagram'])}/" target="_blank" rel="noopener">Instagram @{e(CFG['instagram'])}</a></p>
    </div>
    <div>
      <h2>Endereço</h2>
      <p>{'<br>'.join(e(x) for x in CFG['endereco'])}</p>
    </div>
    <div>
      <h2>Atendimento presencial</h2>
      <p>{'<br>'.join(e(x) for x in CFG['horario'])}</p>
    </div>
  </div>
  <div class="faixa rodape-fim">© {date.today().year} {e(CFG['nome'])}. Valores e disponibilidade podem mudar conforme unidade, andar e data.</div>
</footer>
<script src="{r}app.js?v={VERSAO}" defer></script>
</body>
</html>
"""


def cartao(im, r, h="h3"):
    c = im["campos"]
    linha = im["bairro"] + (f", {c['construtora']}" if c.get("construtora") else "")
    preco = (f'<p class="c-preco"><span>A partir de</span> {brl(im["preco"])}</p>' if im["preco"]
             else '<p class="c-preco c-consulta">Valores sob consulta</p>')
    selo = f'<span class="selo">{e(im["selo"])}</span>' if im["selo"] else ""
    capa = im["img"][0]
    return f"""<article class="cartao" data-bairro="{im['bslug']}" data-preco="{round(im['preco']) if im['preco'] else ''}">
  <a href="{r}imoveis/{im['slug']}/" class="c-link">
    <div class="c-foto">{selo}<img src="{r}imoveis/{im['slug']}/{capa['p']}" alt="" width="{capa['w']}" height="{capa['h']}" loading="lazy"></div>
    <p class="c-local">{e(linha)}</p>
    <{h} class="c-nome">{e(im['nome'])}</{h}>
    <p class="c-resumo">{e(im['resumo'])}</p>
    {preco}
  </a>
</article>"""


def pag_inicio(imoveis, bairros):
    n = len(imoveis)
    g = CFG["google"]
    # Capa: empreendimentos em destaque primeiro; so fotos deitadas, que preenchem a tela.
    cand = [i for i in imoveis if i["img"][0]["w"] >= i["img"][0]["h"] * 1.2]
    cand.sort(key=lambda i: (not i["destaque"], -i["mtime"]))
    vistos, slides_im = set(), []
    for i in cand:                      # um por bairro primeiro, para variar
        if i["bslug"] not in vistos:
            vistos.add(i["bslug"]); slides_im.append(i)
    slides_im = (slides_im + [i for i in cand if i not in slides_im])[:7] or imoveis[:1]
    slides = "".join(
        f'<a class="slide{" ativo" if k == 0 else ""}" href="imoveis/{i["slug"]}/" aria-label="{e(i["nome"])}, {e(i["bairro"])}">'
        f'<img src="imoveis/{i["slug"]}/{i["img"][0]["g"]}" alt="" width="{i["img"][0]["w"]}" height="{i["img"][0]["h"]}"{" fetchpriority=high" if k == 0 else " loading=lazy"}>'
        f'<span class="slide-nome"><strong>{e(i["nome"])}</strong>{e(i["bairro"])}</span></a>' for k, i in enumerate(slides_im))
    pontos = "".join(f'<button type="button" aria-label="Mostrar {e(i["nome"])}"{" aria-current=true" if k == 0 else ""}></button>'
                     for k, i in enumerate(slides_im))
    atalhos = "".join(f'<li><a href="bairros/{b["slug"]}/"><span>{e(b["nome"])}</span><span class="qt">{len(b["itens"])}</span></a></li>' for b in bairros)
    opcoes = "".join(f'<option value="{b["slug"]}">{e(b["nome"])}</option>' for b in bairros)
    cartoes = "\n".join(cartao(i, "") for i in imoveis)
    deps = "".join(
        f'<figure class="dep{" ativo" if k == 0 else ""}"><blockquote><p>{e(d["texto"])}</p></blockquote>'
        f'<figcaption><span class="dep-letra" aria-hidden="true">{e(d["nome"][0])}</span><span><strong>{e(d["nome"])}</strong>Avaliação no Google</span></figcaption></figure>'
        for k, d in enumerate(CFG["depoimentos"]))
    equipe = "".join(
        f'<li><img src="equipe/{e(m["foto"])}" alt="" width="500" height="500" loading="lazy">'
        f'<h3>{e(m["nome"])}</h3><p>{e(m["cargo"])}</p>'
        f'<a href="https://www.instagram.com/{e(m["instagram"])}/" target="_blank" rel="noopener">@{e(m["instagram"])}</a></li>'
        for m in CFG["equipe"])
    mcmv = [i for i in imoveis if "minha casa" in sem_acento(i["selo"] or "")]
    mcmv_link = (f'<a class="botao botao-contorno" href="imoveis/{mcmv[0]["slug"]}/">Ver {e(mcmv[0]["nome"])}</a>' if len(mcmv) == 1
                 else '')
    nomes = [b["nome"] for b in bairros]
    lista_b = (", ".join(nomes[:-1]) + " e " + nomes[-1]) if len(nomes) > 1 else (nomes[0] if nomes else "")
    corpo = f"""<section class="capa" aria-label="Empreendimentos em destaque">
  <div class="slides" id="slides">{slides}
    <button type="button" class="s-seta s-ant" id="sAnt" aria-label="Empreendimento anterior">&#8249;</button>
    <button type="button" class="s-seta s-prox" id="sProx" aria-label="Próximo empreendimento">&#8250;</button>
  </div>
  <div class="capa-faixa">
    <div class="faixa capa-in">
      <h1>Do primeiro ao próximo imóvel.</h1>
      <div class="capa-acao">
        <p>Lançamentos e imóveis prontos em Maceió, com um corretor ao seu lado antes, durante e depois da compra.</p>
        <a class="botao botao-ouro" href="#imoveis">Veja nossos empreendimentos</a>
      </div>
    </div>
    <div class="faixa"><div class="pontos" id="pontos">{pontos}</div></div>
  </div>
</section>

<section class="bairros" id="bairros">
  <div class="faixa">
    <h2>Escolha pelo bairro</h2>
    <ul class="atalhos">{atalhos}</ul>
  </div>
</section>

<section class="bloco" id="imoveis">
  <div class="faixa">
    <div class="bloco-topo">
      <h2>Empreendimentos</h2>
      <form class="filtros" id="filtros" aria-label="Filtrar empreendimentos">
        <label>Bairro <select name="bairro"><option value="">Todos</option>{opcoes}</select></label>
        <label>Valor <select name="faixa">
          <option value="">Qualquer valor</option>
          <option value="0-400000">Até R$ 400 mil</option>
          <option value="400000-600000">R$ 400 mil a R$ 600 mil</option>
          <option value="600000-">Acima de R$ 600 mil</option>
        </select></label>
      </form>
    </div>
    <p class="contagem" id="contagem" aria-live="polite">{n} empreendimentos</p>
    <div class="grade" id="grade">
{cartoes}
    </div>
    <p class="vazio" id="vazio" hidden>Nenhum empreendimento com esse filtro. <a href="{wa('Olá! Procuro um imóvel em Maceió e não achei no site. Pode me ajudar?')}" target="_blank" rel="noopener">Peça uma busca pelo WhatsApp</a> ou <button type="button" id="limpar">limpe os filtros</button>.</p>
  </div>
</section>

<section class="porque" id="eleva">
  <div class="faixa porque-in">
    <img class="marca-dagua" src="img/icone.png" alt="" aria-hidden="true" loading="lazy">
    <h2>A Eleva continua com você depois da assinatura.</h2>
    <div>
      <p>Nosso trabalho é elevar a sua experiência na conquista do imóvel. Isso começa pela conta que cabe no seu mês e não termina quando o contrato é assinado: o corretor que atendeu você segue disponível até as chaves e depois delas.</p>
      <a class="botao botao-claro" href="https://www.instagram.com/{e(CFG['instagram'])}/" target="_blank" rel="noopener">Conheça a Eleva no Instagram</a>
    </div>
  </div>
</section>
<section class="numeros" aria-label="A Eleva em números">
  <div class="faixa numeros-in">
    <div><strong>{e(CFG['negocios'])}</strong><span>em negócios gerados</span></div>
    <div><strong>{e(g['nota'])}</strong><span>de nota no Google, em {g['avaliacoes']} avaliações</span></div>
    <div><strong>{n}</strong><span>empreendimentos no site</span></div>
    <div><strong>{len(bairros)}</strong><span>bairros de Maceió</span></div>
  </div>
</section>

<section class="depoimentos" id="depoimentos">
  <div class="faixa">
    <h2>Quem comprou com a Eleva</h2>
    <div class="deps" id="deps">{deps}</div>
    <div class="deps-nav">
      <button type="button" id="dAnt" aria-label="Depoimento anterior">&#8249;</button>
      <button type="button" id="dProx" aria-label="Próximo depoimento">&#8250;</button>
      <a href="{e(g['link'])}" target="_blank" rel="noopener">Ler as {g['avaliacoes']} avaliações no Google</a>
    </div>
  </div>
</section>

<section class="tema tema-areia">
  <div class="faixa tema-in">
    <div>
      <h2>Comprando o seu primeiro imóvel.</h2>
      <p>Você não precisa chegar sabendo. Conte o bairro, o tamanho e quanto cabe no mês: a gente explica cada etapa e mostra só o que entra na sua conta.</p>
      <a class="botao" href="#imoveis">Veja nossos empreendimentos</a>
    </div>
    <div class="formas formas-a" aria-hidden="true"><i></i><i></i><i></i></div>
  </div>
</section>

<section class="tema tema-ouro">
  <div class="faixa tema-in">
    <div class="formas formas-b" aria-hidden="true"><i></i><i></i><i></i></div>
    <div>
      <h2>Minha Casa Minha Vida.</h2>
      <p>O programa habitacional do Governo Federal reduz a entrada e os juros conforme a renda da família. A Eleva confere em qual faixa você se encaixa e quais empreendimentos entram no programa.</p>
      <a class="botao" href="{wa('Olá! Quero saber se me encaixo no Minha Casa Minha Vida.')}" target="_blank" rel="noopener">Quero saber mais</a>
      {mcmv_link}
    </div>
  </div>
</section>

<section class="tema tema-azul" id="simulacao">
  <div class="faixa tema-in">
    <div>
      <h2>Planeje o seu financiamento.</h2>
      <p>Informe o valor do imóvel, a sua renda e a entrada. Um corretor devolve a simulação com parcelas e prazos pelo WhatsApp.</p>
    </div>
    <form class="simula" id="simula" data-wa="{WA}">
      <label>Valor do imóvel <input name="valor" inputmode="numeric" placeholder="R$ 350.000" autocomplete="off"></label>
      <label>Renda mensal da família <input name="renda" inputmode="numeric" placeholder="R$ 6.000" autocomplete="off"></label>
      <label>Entrada disponível, com FGTS <input name="entrada" inputmode="numeric" placeholder="R$ 40.000" autocomplete="off"></label>
      <button class="botao botao-ouro" type="submit">Pedir simulação no WhatsApp</button>
    </form>
  </div>
</section>

<section class="bloco" id="equipe">
  <div class="faixa">
    <h2>Quem atende você</h2>
    <ul class="equipe">{equipe}</ul>
  </div>
</section>
"""
    ld = json.dumps({"@context": "https://schema.org", "@type": "RealEstateAgent", "name": CFG["nome"], "url": URL,
                     "image": URL + "img/mcz.jpg", "telephone": "+" + WA,
                     "address": {"@type": "PostalAddress", "streetAddress": CFG["endereco"][0], "addressLocality": CFG["cidade"],
                                 "addressRegion": CFG["uf"], "addressCountry": "BR"}}, ensure_ascii=False)
    return pagina("", f"{CFG['nome']} | Imóveis em Maceió",
                  f"Lançamentos e imóveis prontos em Maceió: {lista_b}. Fotos, valores a partir de e atendimento pelo WhatsApp.",
                  corpo, "", extra_head=f'<script type="application/ld+json">{ld}</script>\n')


def chamada(t, s, msg):
    return f"""<section class="chamada">
  <div class="faixa chamada-in">
    <div><h2>{e(t)}</h2><p>{e(s)}</p></div>
    <a class="botao botao-claro" href="{wa(msg)}" target="_blank" rel="noopener">Conversar no WhatsApp</a>
  </div>
</section>"""


def pag_bairro(b):
    r = "../../"
    n = len(b["itens"])
    p = prep(b["nome"])
    cartoes = "\n".join(cartao(i, r, "h2") for i in b["itens"])
    plural = "empreendimento" if n == 1 else "empreendimentos"
    corpo = f"""<section class="bloco cabeca">
  <div class="faixa">
    <nav class="trilha" aria-label="Você está em"><a href="{r}">Início</a> / <a href="{r}#bairros">Bairros</a> / <span>{e(b['nome'])}</span></nav>
    <h1>Imóveis {p} {e(b['nome'])}</h1>
    <p class="contagem">{n} {plural} em Maceió, {e(CFG['uf'])}</p>
    <div class="grade">
{cartoes}
    </div>
  </div>
</section>
{chamada(f"Procura outra coisa {p} {b['nome']}?", 'Conte o que você precisa e a gente busca.', f"Olá! Procuro um imóvel {p} {b['nome']}. Pode me ajudar?")}
"""
    return pagina(r, f"Imóveis {p} {b['nome']}, Maceió | Eleva",
                  f"{n} {plural} {p} {b['nome']}, em Maceió: " + ", ".join(i["nome"] for i in b["itens"]) + ".",
                  corpo, f"bairros/{b['slug']}/", og=f"imoveis/{b['itens'][0]['slug']}/{b['itens'][0]['img'][0]['g']}")


def pag_imovel(im, vizinhos):
    r = "../../"
    c = im["campos"]
    p = prep(im["bairro"])
    msg = f"Olá! Vi o {im['nome']} ({im['bairro']}) no site da Eleva e quero saber mais."
    fotos = "".join(
        f'<a href="{f["g"]}" class="g-item{" g-capa" if k == 0 else ""}" data-i="{k}">'
        f'<img src="{f["g"] if k == 0 else f["p"]}" alt="{e(im["nome"])}, foto {k + 1} de {len(im["img"])}" width="{f["w"]}" height="{f["h"]}"'
        f'{" fetchpriority=high" if k == 0 else " loading=lazy"}></a>' for k, f in enumerate(im["img"]))
    dados = [(rot, c[k]) for k, rot in ROTULOS if c.get(k)] + im["extras"]
    dl = "".join(f"<div><dt>{e(k)}</dt><dd>{e(v)}</dd></div>" for k, v in [("Bairro", im["bairro"])] + dados)
    texto = ""
    for bloco in im["paragrafos"]:
        if all(re.match(r"^[-•*]\s+", l) for l in bloco):
            texto += "<ul>" + "".join("<li>" + e(re.sub(r"^[-•*]\s+", "", l)) + "</li>" for l in bloco) + "</ul>"
        else:
            texto += "<p>" + "<br>".join(e(l) for l in bloco) + "</p>"
    if im["preco"]:
        preco = (f'<p class="f-rotulo">A partir de</p><p class="f-preco">{brl(im["preco"])}</p>'
                 '<p class="f-nota">Menor valor da tabela vigente. Pode mudar conforme unidade, andar e data.</p>')
    else:
        preco = ('<p class="f-preco f-consulta">Valores sob consulta</p>'
                 '<p class="f-nota">Fale com a Eleva para receber a condição da unidade que interessa a você.</p>')
    selo = f'<span class="selo selo-solto">{e(im["selo"])}</span>' if im["selo"] else ""
    outros = ""
    if vizinhos:
        outros = (f'<section class="bloco areia"><div class="faixa"><h2>Mais {p} {e(im["bairro"])}</h2><div class="grade">'
                  + "\n".join(cartao(v, r) for v in vizinhos[:3]) + "</div></div></section>")
    corpo = f"""<article class="imovel">
  <div class="faixa">
    <nav class="trilha" aria-label="Você está em"><a href="{r}">Início</a> / <a href="{r}bairros/{im['bslug']}/">{e(im['bairro'])}</a> / <span>{e(im['nome'])}</span></nav>
    <header class="im-topo">
      <div>{selo}<h1>{e(im['nome'])}</h1>
      <p class="im-local">{e(im['bairro'])}, Maceió{', ' + e(c['construtora']) if c.get('construtora') else ''}</p></div>
    </header>
    <div class="galeria" id="galeria">{fotos}</div>
    <div class="im-corpo">
      <div class="im-texto">
        <h2>Sobre o empreendimento</h2>
        {texto or '<p>Fale com a Eleva para receber o material completo deste empreendimento.</p>'}
        <dl class="dados">{dl}</dl>
      </div>
      <aside class="ficha">
        {preco}
        <a class="botao" href="{wa(msg)}" target="_blank" rel="noopener">Falar com um corretor no WhatsApp</a>
        <p class="f-nota">Atendimento da {e(CFG['nome'])}, CRECI {e(CFG['creci'])}.</p>
      </aside>
    </div>
  </div>
</article>
{outros}
<div class="visor" id="visor" hidden role="dialog" aria-modal="true" aria-label="Fotos de {e(im['nome'])}">
  <button class="v-fechar" id="vFechar">Fechar</button>
  <button class="v-seta v-ant" id="vAnt" aria-label="Foto anterior">&#8249;</button>
  <img id="vImg" alt="">
  <button class="v-seta v-prox" id="vProx" aria-label="Próxima foto">&#8250;</button>
  <p class="v-conta" id="vConta"></p>
</div>
<a class="barra-wa" href="{wa(msg)}" target="_blank" rel="noopener">Falar com um corretor no WhatsApp</a>
"""
    desc = im["resumo"] or f"{im['nome']}, empreendimento {p} {im['bairro']}, Maceió."
    if im["preco"]:
        desc += f" A partir de {brl(im['preco'])}."
    return pagina(r, f"{im['nome']}, {im['bairro']}, Maceió | Eleva", desc, corpo,
                  f"imoveis/{im['slug']}/", og=f"imoveis/{im['slug']}/{im['img'][0]['g']}")


def main():
    global RODAPE_BAIRROS, VERSAO
    imoveis = carregar()
    if SAIDA.exists():
        shutil.rmtree(SAIDA)
    SAIDA.mkdir(parents=True)
    imoveis = [im for im in imoveis if gravar_fotos(im)]
    if not imoveis:
        sys.exit("Nenhum empreendimento com fotos encontrado. O site no ar foi mantido como estava.")
    grupos = {}
    for im in imoveis:
        grupos.setdefault(im["bslug"], {"nome": im["bairro"], "slug": im["bslug"], "itens": []})["itens"].append(im)
    bairros = sorted(grupos.values(), key=lambda b: (-len(b["itens"]), sem_acento(b["nome"])))
    for b in bairros:
        b["itens"].sort(key=lambda i: (not i["destaque"], sem_acento(i["nome"])))
    imoveis = [i for b in bairros for i in b["itens"]]
    RODAPE_BAIRROS = "".join(f'<li><a href="{{r}}bairros/{b["slug"]}/">{e(b["nome"])}</a></li>' for b in bairros)
    VERSAO = str(int(max([p.stat().st_mtime for p in SITE.glob("*.*")] + [0])))

    for f in ("estilo.css", "app.js"):
        shutil.copy2(SITE / f, SAIDA / f)
    shutil.copytree(SITE / "img", SAIDA / "img")
    shutil.copytree(SITE / "equipe", SAIDA / "equipe")
    (SAIDA / ".nojekyll").write_text("")
    (SAIDA / "index.html").write_text(pag_inicio(imoveis, bairros), encoding="utf-8")
    urls = [""]
    for b in bairros:
        d = SAIDA / "bairros" / b["slug"]
        d.mkdir(parents=True)
        (d / "index.html").write_text(pag_bairro(b), encoding="utf-8")
        urls.append(f"bairros/{b['slug']}/")
    for im in imoveis:
        viz = [v for v in grupos[im["bslug"]]["itens"] if v is not im]
        (SAIDA / "imoveis" / im["slug"] / "index.html").write_text(pag_imovel(im, viz), encoding="utf-8")
        urls.append(f"imoveis/{im['slug']}/")
    nf = pagina(URL, "Página não encontrada | Eleva", "Esta página saiu do ar.",
                f'<section class="bloco cabeca"><div class="faixa"><h1>Esta página saiu do ar.</h1>'
                f'<p class="contagem">O imóvel pode ter sido vendido ou o endereço mudou.</p>'
                f'<p><a class="botao" href="{URL}#imoveis">Ver os empreendimentos disponíveis</a></p></div></section>', "404.html")
    (SAIDA / "404.html").write_text(nf, encoding="utf-8")
    (SAIDA / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"<url><loc>{URL}{u}</loc></url>\n" for u in urls) + "</urlset>\n", encoding="utf-8")
    (SAIDA / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {URL}sitemap.xml\n")
    (SAIDA / "publicado.json").write_text(json.dumps(
        {"empreendimentos": len(imoveis), "bairros": len(bairros), "avisos": AVISOS,
         "lista": [f"{i['bairro']} / {i['nome']}" for i in imoveis]}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(imoveis)} empreendimentos em {len(bairros)} bairros -> {SAIDA}")
    for a in AVISOS:
        print("AVISO:", a)


if __name__ == "__main__":
    main()
