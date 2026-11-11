"""Busca as avaliacoes do Google (API oficial Places) e guarda so as de 5 estrelas em site/depoimentos.json.
Roda sozinho todo dia pelo GitHub (.github/workflows/publicar.yml). Sem a chave GOOGLE_PLACES_KEY, nao faz nada
e o site continua com os depoimentos que ja estao no arquivo."""
import json, os, sys, urllib.request, urllib.error
from pathlib import Path

ARQ = Path(__file__).resolve().parent.parent / "site" / "depoimentos.json"
CHAVE = os.environ.get("GOOGLE_PLACES_KEY", "").strip()
PLACE = os.environ.get("GOOGLE_PLACE_ID", "").strip()
BUSCA = os.environ.get("GOOGLE_PLACE_BUSCA", "Eleva Evolução Imobiliária Maceió")


def chamar(url, corpo=None, campos=""):
    h = {"X-Goog-Api-Key": CHAVE, "X-Goog-FieldMask": campos, "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=json.dumps(corpo).encode() if corpo else None, headers=h,
                                 method="POST" if corpo else "GET")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def nome_curto(n):
    p = (n or "").split()
    return f"{p[0]} {p[-1][0]}." if len(p) > 1 else (p[0] if p else "")


def main():
    if not CHAVE:
        print("Sem GOOGLE_PLACES_KEY: depoimentos mantidos como estao.")
        return 0
    try:
        pid = PLACE
        if not pid:
            r = chamar("https://places.googleapis.com/v1/places:searchText", {"textQuery": BUSCA, "languageCode": "pt-BR"},
                       "places.id,places.displayName")
            pid = (r.get("places") or [{}])[0].get("id", "")
            if not pid:
                print("Empresa nao encontrada no Google; depoimentos mantidos.")
                return 0
        r = chamar(f"https://places.googleapis.com/v1/places/{pid}?languageCode=pt-BR", None,
                   "rating,userRatingCount,reviews")
    except (urllib.error.URLError, ValueError) as ex:
        print(f"Google indisponivel ({ex}); depoimentos mantidos.")
        return 0
    atual = json.loads(ARQ.read_text(encoding="utf-8")) if ARQ.is_file() else {"itens": []}
    itens = atual.get("itens", [])
    chaves = {" ".join(x["texto"].split())[:80] for x in itens}
    for rv in r.get("reviews", []):
        txt = ((rv.get("text") or rv.get("originalText") or {}).get("text") or "").strip()
        if rv.get("rating") != 5 or len(txt) < 30:        # so 5 estrelas, com texto de verdade
            continue
        k = " ".join(txt.split())[:80]
        if k in chaves:
            continue
        nome = nome_curto((rv.get("authorAttribution") or {}).get("displayName"))
        if nome:
            itens.insert(0, {"nome": nome, "texto": txt, "nota": 5}); chaves.add(k)
    if r.get("rating"):
        atual["nota"] = f"{float(r['rating']):.1f}".replace(".", ",")
    if r.get("userRatingCount"):
        atual["avaliacoes"] = int(r["userRatingCount"])
    atual["itens"] = itens[:12]
    novo = json.dumps(atual, ensure_ascii=False, indent=2)
    if not ARQ.is_file() or ARQ.read_text(encoding="utf-8") != novo:
        ARQ.write_text(novo, encoding="utf-8")
        print("depoimentos.json atualizado.")
    else:
        print("Sem novidades no Google.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
