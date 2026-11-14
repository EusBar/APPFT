"""Gera as páginas públicas (docs/) a partir dos textos legais do app.

As lojas exigem um endereço público para a política de privacidade. O GitHub
Pages publica a pasta docs/ em https://eusbar.github.io/APPFT/.
Correr sempre que assets/legal/*.md mudar:  python3 tool/build_legal_site.py
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs"

STYLE = """
:root{--bg:#0b0f14;--card:#131a22;--text:#e6edf3;--muted:#9aa7b4;--accent:#5eead4}
@media (prefers-color-scheme: light){:root{--bg:#f6f8fa;--card:#fff;--text:#1f2328;--muted:#59636e;--accent:#0f766e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);
font:16px/1.65 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:32px 16px 64px}
header{display:flex;align-items:center;gap:10px;margin-bottom:24px}
.logo{width:36px;height:36px;border-radius:10px;background:var(--accent);color:#000;
display:grid;place-items:center;font-weight:800}
.brand{font-weight:800;letter-spacing:2px}
article{background:var(--card);border-radius:20px;padding:24px 20px}
h1{font-size:1.7rem;line-height:1.25;margin:0 0 4px}h2{font-size:1.15rem;margin:28px 0 8px}
p,li{color:var(--text)}.muted{color:var(--muted)}a{color:var(--accent)}
ul{padding-left:20px}code{background:rgba(127,127,127,.15);padding:1px 5px;border-radius:5px}
nav{margin-top:20px;display:flex;gap:16px;flex-wrap:wrap}
footer{margin-top:24px;font-size:.9rem;color:var(--muted)}
"""


def inline(text: str) -> str:
    t = html.escape(text)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    t = re.sub(r"([\w.+-]+@[\w-]+\.[\w.]+)", r'<a href="mailto:\1">\1</a>', t)
    return t


def render(md: str) -> tuple[str, str]:
    out, in_list, title = [], False, "FINTRACK"
    for line in md.splitlines():
        s = line.strip()
        if s.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(s[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if not s:
            continue
        if s.startswith("# "):
            title = s[2:]
            out.append(f"<h1>{inline(title)}</h1>")
        elif s.startswith("## "):
            out.append(f"<h2>{inline(s[3:])}</h2>")
        elif s.startswith("Última atualização"):
            out.append(f'<p class="muted">{inline(s)}</p>')
        else:
            out.append(f"<p>{inline(s)}</p>")
    if in_list:
        out.append("</ul>")
    return title, "\n".join(out)


def page(title: str, body: str) -> str:
    return f"""<!doctype html>
<html lang="pt">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>{STYLE}</style>
</head>
<body><main>
<header><div class="logo">F</div><div class="brand">FINTRACK</div></header>
<article>
{body}
</article>
<nav><a href="index.html">Início</a><a href="privacidade.html">Política de privacidade</a><a href="termos.html">Termos de utilização</a></nav>
<footer>FINTRACK · <a href="mailto:appfintracksolution@gmail.com">appfintracksolution@gmail.com</a></footer>
</main></body>
</html>
"""


for name in ["privacidade", "termos"]:
    title, body = render((ROOT / "assets" / "legal" / f"{name}.md").read_text(encoding="utf-8"))
    (OUT / f"{name}.html").write_text(page(title, body), encoding="utf-8")

index = """<h1>FINTRACK</h1>
<p>Gestão financeira pessoal, simples e segura: saldos, compromissos, orçamentos,
objetivos e Kixikila, com inteligência no próprio telemóvel e dados cifrados.</p>
<ul>
<li><a href="privacidade.html">Política de privacidade</a></li>
<li><a href="termos.html">Termos de utilização</a></li>
</ul>
<p class="muted">Contacto: <a href="mailto:appfintracksolution@gmail.com">appfintracksolution@gmail.com</a></p>"""
(OUT / "index.html").write_text(page("FINTRACK", index), encoding="utf-8")
# Sem processamento Jekyll: publica os ficheiros tal como estão.
(OUT / ".nojekyll").write_text("")
print("Páginas geradas em docs/.")
