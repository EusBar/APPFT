"""Folheto promocional do FINTRACK (docs/marketing/FINTRACK_Descubra.pdf)."""
import base64
import io
import pathlib
import subprocess

import qrcode
import qrcode.image.svg

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "marketing"
SITE = "https://eusbar.github.io/APPFT/"
YT = "https://youtube.com/@fintrack-d4d"

def qr(url):
    b = io.BytesIO()
    qrcode.make(url, image_factory=qrcode.image.svg.SvgPathImage, box_size=10, border=1).save(b)
    return b.getvalue().decode().split("?>", 1)[-1]

def photo(n):
    return "data:image/jpeg;base64," + base64.b64encode((ROOT / f"assets/backgrounds/countries/{n}.jpg").read_bytes()).decode()

STATS = [("14", "dias de Premium<br>grátis"), ("0", "anúncios e<br>rastreio"), ("100%", "cifrado, até<br>na nuvem"), ("6", "moedas, sem<br>as misturar")]
WOW = [
    ("⚡", "Escreva como fala", "“Gastei 12 500 Kz no Kero hoje”. Ou cole o SMS do banco. O movimento aparece pronto.", "ai"),
    ("💡", "Saiba quanto pode gastar", "O saldo disponível já desconta as contas a pagar até ao fim do mês. Sem surpresas.", "teal"),
    ("🫀", "O pulso do seu dinheiro", "Uma nota de 0 a 100 todos os meses, com o porquê. Veja-a subir.", "ai"),
    ("💬", "Pergunte e ele responde", "“Em que gasto mais?” “Compara com o mês passado.” Resposta na hora, no seu telemóvel.", "ai"),
    ("🤝", "Kixikila sem confusão", "Grupo, contribuições e a sua vez de receber, tudo organizado.", "commit"),
    ("🛡️", "Um guarda atento", "Avisa sobre duplicados, gastos fora do normal e contas que não chegam.", "income"),
]
cards = "".join(f'<div class="w t-{t}"><div class="e">{e}</div><h3>{h}</h3><p>{d}</p></div>' for e, h, d, t in WOW)
stats = "".join(f'<div class="s"><b>{n}</b><span>{l}</span></div>' for n, l in STATS)

HTML = f"""<!doctype html><html lang="pt"><head><meta charset="utf-8"><style>
@page {{ size:A4; margin:0 }}
:root {{ --bg:#0b0f14; --card:#131a22; --line:#22303c; --text:#e6edf3; --muted:#9aa7b4;
 --teal:#5eead4; --income:#34d399; --commit:#fbbf24; --ai:#a78bfa; --expense:#f87171 }}
* {{ box-sizing:border-box }}
html,body {{ margin:0; background:var(--bg); color:var(--text); font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
 -webkit-print-color-adjust:exact; print-color-adjust:exact }}
a {{ color:inherit; text-decoration:none }}
.page {{ width:210mm; height:297mm; position:relative; overflow:hidden; page-break-after:always; background:var(--bg) }}
.hero {{ height:196mm; padding:15mm; display:flex; flex-direction:column; justify-content:space-between;
 background:linear-gradient(180deg,rgba(11,15,20,.05) 0%,rgba(11,15,20,.35) 45%,var(--bg) 100%), url({photo('aoa_4')}) center 30%/cover }}
.brand {{ display:flex; align-items:center; gap:10px; font-weight:800; letter-spacing:3px }}
.brand span {{ width:36px; height:36px; border-radius:10px; background:var(--teal); color:var(--bg); display:grid; place-items:center; font-size:19px }}
.pill {{ display:inline-block; padding:6px 12px; border-radius:20px; background:rgba(167,139,250,.22); color:#ddd3ff;
 font-size:12px; font-weight:700; letter-spacing:1px; margin-bottom:12px; border:1px solid rgba(167,139,250,.45) }}
h1 {{ font-size:56px; line-height:1.02; margin:0; letter-spacing:-1px }}
h1 em {{ font-style:normal; color:var(--teal) }}
.lead {{ font-size:17px; color:#d5dde5; margin:12px 0 0; max-width:150mm; line-height:1.45 }}
.stats {{ display:grid; grid-template-columns:repeat(4,1fr); gap:10px; padding:0 15mm; margin-top:-2mm }}
.s {{ background:var(--card); border:1px solid var(--line); border-radius:16px; padding:12px 14px }}
.s b {{ display:block; font-size:30px; line-height:1; color:var(--teal); margin-bottom:4px }}
.s:nth-child(2) b {{ color:var(--income) }} .s:nth-child(3) b {{ color:var(--ai) }} .s:nth-child(4) b {{ color:var(--commit) }}
.s span {{ font-size:11.5px; color:var(--muted); line-height:1.3 }}
.cta {{ margin:12mm 15mm 0; display:grid; grid-template-columns:1fr 1fr; gap:10px }}
.btn {{ display:flex; align-items:center; justify-content:space-between; gap:12px; padding:18px 22px; border-radius:20px; font-weight:800; font-size:17px }}
.b1 {{ background:linear-gradient(135deg,var(--teal),#2dd4bf); color:#062a26 }}
.b2 {{ background:#ff0033; color:#fff }}
.btn small {{ display:block; font-weight:600; font-size:11px; opacity:.85 }}
.arrow {{ font-size:22px }}
.wrap {{ padding:16mm 15mm 0 }}
h2 {{ font-size:32px; margin:0 0 4px; letter-spacing:-.5px }}
.sub {{ color:var(--muted); font-size:13.5px; margin:0 0 7mm }}
.grid {{ display:grid; grid-template-columns:1fr 1fr; gap:12px }}
.w {{ background:var(--card); border:1px solid var(--line); border-radius:18px; padding:18px 18px 20px; position:relative; overflow:hidden }}
.w::after {{ content:''; position:absolute; right:-30px; top:-30px; width:90px; height:90px; border-radius:50%; opacity:.18 }}
.t-ai::after {{ background:var(--ai) }} .t-teal::after {{ background:var(--teal) }} .t-commit::after {{ background:var(--commit) }} .t-income::after {{ background:var(--income) }}
.e {{ font-size:28px }} .w h3 {{ margin:8px 0 5px; font-size:17px }} .w p {{ margin:0; font-size:13px; color:#c9d3dc; line-height:1.45 }}
.steps {{ margin:11mm 15mm 0; padding:14px 18px; border-radius:18px; border:1px solid var(--line);
 background:linear-gradient(135deg,rgba(94,234,212,.12),rgba(167,139,250,.12)); display:grid; grid-template-columns:repeat(3,1fr); gap:12px }}
.st .k {{ display:inline-grid; place-items:center; width:24px; height:24px; border-radius:50%; background:var(--teal); color:var(--bg); font-size:12px; margin-bottom:6px }}
.st div {{ font-size:13.5px; line-height:1.4 }}
.qrs {{ margin:11mm 15mm 0; display:grid; grid-template-columns:1fr 1fr; gap:12px }}
.q {{ display:flex; gap:14px; align-items:center; background:var(--card); border:1px solid var(--line); border-radius:18px; padding:12px }}
.q .code {{ width:34mm; flex:0 0 34mm; background:#fff; border-radius:12px; padding:6px }}
.q svg {{ width:100%; height:auto; display:block }}
.q h4 {{ margin:0 0 4px; font-size:15px }} .q p {{ margin:0 0 6px; font-size:11.5px; color:var(--muted); line-height:1.35 }}
.q .link {{ font-size:11px; font-weight:700; color:var(--teal); white-space:nowrap }}
.q.yt .link {{ color:#ff5a76 }}
.foot {{ position:absolute; bottom:10mm; left:15mm; right:15mm; display:flex; justify-content:space-between; font-size:10.5px; color:var(--muted) }}
</style></head><body>

<div class="page">
  <div class="hero">
    <div class="brand"><span>F</span>FINTRACK</div>
    <div>
      <div class="pill">FEITO EM ANGOLA, PARA O SEU DIA-A-DIA</div>
      <h1>O seu dinheiro<br>finalmente <em>claro.</em></h1>
      <p class="lead">Saiba sempre quanto pode gastar, registe tudo em segundos e deixe a inteligência do FINTRACK mostrar-lhe para onde vai cada kwanza.</p>
    </div>
  </div>
  <div class="stats">{stats}</div>
  <div class="cta">
    <a class="btn b1" href="{SITE}"><div>Transferir grátis<small>Android · eusbar.github.io/APPFT</small></div><span class="arrow">↓</span></a>
    <a class="btn b2" href="{YT}"><div>Ver em vídeo<small>YouTube · @fintrack-d4d</small></div><span class="arrow">▶</span></a>
  </div>
  <div class="foot"><span>FINTRACK · gestão financeira pessoal</span><span>appfintracksolution@gmail.com</span></div>
</div>

<div class="page">
  <div class="wrap">
    <h2>Vai querer abrir todos os dias.</h2>
    <p class="sub">Seis razões que tornam o FINTRACK diferente de tudo o que já experimentou.</p>
    <div class="grid">{cards}</div>
  </div>
  <div class="steps">
    <div class="st"><span class="k">1</span><div>Abra o <b>site</b> e toque em <b>Transferir</b>.</div></div>
    <div class="st"><span class="k">2</span><div>Crie o seu <b>PIN</b> e ative a impressão digital.</div></div>
    <div class="st"><span class="k">3</span><div>Registe o primeiro gasto e veja o <b>pulso</b> a nascer.</div></div>
  </div>
  <div class="qrs">
    <a class="q" href="{SITE}"><div class="code">{qr(SITE)}</div><div><h4>Transferir o FINTRACK</h4><p>App, manual de uso e atualizações, sempre no mesmo sítio.</p><span class="link">eusbar.github.io/APPFT</span></div></a>
    <a class="q yt" href="{YT}"><div class="code">{qr(YT)}</div><div><h4>Ver os vídeos</h4><p>Veja o FINTRACK a funcionar em poucos minutos.</p><span class="link">youtube.com/@fintrack-d4d</span></div></a>
  </div>
  <div class="foot"><span>Segurança de banco: PIN, biometria e cifra. Sem anúncios. Nunca pede dados bancários.</span><span>Em breve na Google Play e App Store</span></div>
</div>
</body></html>"""

html = OUT / "promo.html"
html.write_text(HTML, encoding="utf-8")
pdf = OUT / "FINTRACK_Descubra.pdf"
subprocess.run(["node", "-e", f"""const {{chromium}}=require('playwright');(async()=>{{const b=await chromium.launch();const p=await b.newPage();
await p.goto('file://{html}');await p.pdf({{path:'{pdf}',format:'A4',printBackground:true,preferCSSPageSize:true}});await b.close()}})()"""], check=True)
print(pdf)
