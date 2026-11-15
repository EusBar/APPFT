"""Gera o manual de uso do FINTRACK em PDF (docs/marketing/FINTRACK_Manual.pdf).

python3 tool/build_manual.py  (precisa de qrcode e Playwright)
"""
import base64
import io
import pathlib
import subprocess

import qrcode
import qrcode.image.svg

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "marketing"
SITE = "https://eusbar.github.io/APPFT/"

qr = qrcode.make(SITE, image_factory=qrcode.image.svg.SvgPathImage, box_size=10, border=1)
buf = io.BytesIO()
qr.save(buf)
qr_svg = buf.getvalue().decode().split("?>", 1)[-1]

def photo(name: str) -> str:
    data = (ROOT / "assets" / "backgrounds" / "countries" / f"{name}.jpg").read_bytes()
    return "data:image/jpeg;base64," + base64.b64encode(data).decode()

def steps(items):
    return "".join(f'<li><span class="n">{i}</span><div>{t}</div></li>' for i, t in enumerate(items, 1))

def tips(items):
    return "".join(f"<li>{t}</li>" for t in items)

SECTIONS = [
    ("01", "Instalar", "teal", f"""
<p>O FINTRACK está disponível para <b>Android 7.0 ou mais recente</b>. A versão para iPhone chega em breve.</p>
<ol class="steps">{steps([
    f'Abra o site <b>{SITE}</b> (ou leia o QR code da capa).',
    'Toque em <b>Transferir para Android (APK)</b>.',
    'Abra o ficheiro transferido. Se o Android pedir, permita <b>“instalar aplicações desta fonte”</b>.',
    'O aviso de que a app não vem da Google Play é normal até à publicação na loja.',
])}</ol>
<div class="note">Para atualizar, transfira de novo no mesmo site e instale por cima: <b>os seus dados mantêm-se</b>.</div>"""),
    ("02", "Primeiros passos", "teal", f"""
<ol class="steps">{steps([
    '<b>Boas-vindas:</b> escolha <b>Criar conta grátis</b>, <b>Já tenho conta</b> ou <b>Começar sem conta</b>.',
    '<b>Conta (opcional):</b> e-mail e palavra-passe; recebe um <b>código de 6 dígitos</b> no e-mail para confirmar.',
    '<b>Código de recuperação:</b> guarde-o num lugar seguro. É a única forma de recuperar os dados se esquecer a palavra-passe.',
    '<b>PIN de 6 dígitos:</b> protege a app neste telemóvel. Evite sequências e datas.',
    '<b>Impressão digital ou rosto:</b> ative para abrir a app num toque.',
    '<b>Perfil:</b> nome, moeda principal e a primeira conta com o saldo atual.',
])}</ol>"""),
    ("03", "Início", "teal", f"""
<p>O ecrã principal resume o seu mês num relance:</p>
<ul class="dots">{tips([
    '<b>Saldo disponível:</b> o que pode gastar até ao fim do mês, já descontadas as contas a pagar. Toque em “até …” para mudar o horizonte.',
    '<b>Fluxo do mês:</b> entradas, saídas e resultado. Toque para abrir o relatório.',
    '<b>Planear:</b> estado dos compromissos, orçamentos, objetivos e Kixikila.',
    '<b>Contas</b> e <b>movimentos recentes</b>.',
    '<b>Olho</b> no topo: modo discreto, esconde todos os valores. <b>Cadeado:</b> bloqueia a app.',
])}</ul>"""),
    ("04", "Registar movimentos", "income", f"""
<ol class="steps">{steps([
    'Toque em <b>+ Movimento</b>.',
    'Escolha <b>Saída</b>, <b>Entrada</b> ou <b>Transferência</b> entre contas.',
    'Indique o valor, a conta, a categoria e a data. A descrição é opcional.',
    'Grave. O saldo atualiza na hora.',
])}</ol>
<div class="note">Enganou-se? Abra o movimento e use <b>Anular</b>: o FINTRACK regista um estorno e mantém o histórico completo, como um banco.</div>"""),
    ("05", "Planear", "commit", f"""
<ul class="dots">{tips([
    '<b>Compromissos:</b> renda, propinas, prestações. Recebe lembretes e o valor sai do saldo disponível antes de pagar.',
    '<b>Orçamentos:</b> limite mensal total ou por categoria, com avisos aos 50%, 80% e 100%.',
    '<b>Objetivos:</b> viagem, carro, reserva de emergência. Veja quanto juntar por mês para cumprir o prazo.',
    '<b>Kixikila:</b> acompanhe o grupo, as contribuições e a sua vez de receber.',
])}</ul>"""),
    ("06", "FINTRACK AI", "ai", f"""
<p>A inteligência do FINTRACK funciona <b>no seu telemóvel, sem Internet</b>. Separador <b>IA</b>:</p>
<ul class="dots">{tips([
    '<b>Pulso financeiro:</b> nota de 0 a 100 do seu mês, com o porquê de cada ponto.',
    '<b>Pergunte ao FINTRACK:</b> “Quanto gastei este mês?”, “Em que gasto mais?”, “Quanto posso gastar?”, “Compara com o mês passado”.',
    '<b>Para si:</b> observações automáticas (ritmo de gastos, projeção do mês, categorias acima do habitual).',
    '<b>Evolução:</b> curvas de 6 meses. Toque num mês para ver os valores.',
    '<b>Smart Entry:</b> escreva “Gastei 12 500 Kz no Kero hoje” ou cole o SMS do banco; o movimento prepara-se sozinho para confirmar.',
    '<b>AI Guard:</b> avisa sobre possíveis duplicados, valores fora do habitual e saldo disponível negativo.',
])}</ul>"""),
    ("07", "Relatórios e dados", "teal", f"""
<ul class="dots">{tips([
    '<b>Relatório do mês:</b> no cartão “Fluxo” do Início ou em Movimentos → Relatórios. Partilhe em <b>PDF</b> ou <b>Excel (CSV)</b>.',
    '<b>Importar:</b> traga movimentos de ficheiros CSV ou Excel.',
    '<b>Cópia de segurança:</b> Definições → Os seus dados. A cópia é cifrada com uma palavra-passe à sua escolha.',
])}</ul>"""),
    ("08", "Nuvem e vários telemóveis", "teal", f"""
<ul class="dots">{tips([
    'Com conta, tudo sincroniza sozinho e com <b>cifra ponta-a-ponta</b>: nem o FINTRACK consegue ler os seus dados.',
    'Noutro telemóvel, toque em <b>Já tenho conta</b>; chega um código ao e-mail e os dados voltam.',
    'Em <b>Definições → Conta e sincronização</b> vê os dispositivos ligados e pode terminar sessões.',
    '<b>Terminar sessão</b> retira os dados da conta deste telemóvel (continuam guardados na nuvem).',
])}</ul>"""),
    ("09", "Premium", "ai", f"""
<p>O essencial e toda a segurança são <b>grátis para sempre</b>. O Premium desbloqueia o Pulso, o Pergunte ao FINTRACK, as Tendências, o Smart Entry e os relatórios em PDF.</p>
<div class="note">Cada instalação tem <b>14 dias grátis</b> com tudo aberto. As subscrições ficam disponíveis com a publicação na Google Play e na App Store.</div>"""),
]

SAFETY = [
    'Nunca partilhe o PIN, a palavra-passe ou o código de recuperação. O FINTRACK nunca os pede.',
    'O FINTRACK não se liga a bancos e nunca pede credenciais bancárias.',
    'Esqueceu o PIN? Com conta, reponha a app e entre de novo: os dados voltam da nuvem.',
    'Sem conta, faça cópias de segurança regulares.',
]

def section_html(num, title, tone, body):
    return f'<section class="sec tone-{tone}"><div class="head"><span class="num">{num}</span><h2>{title}</h2></div>{body}</section>'

sections = "".join(section_html(*s) for s in SECTIONS)

HTML = f"""<!doctype html><html lang="pt"><head><meta charset="utf-8"><style>
@page {{ size: A4; margin: 0; }}
:root {{ --bg:#0b0f14; --card:#131a22; --line:#22303c; --text:#e6edf3; --muted:#9aa7b4;
  --teal:#5eead4; --income:#34d399; --expense:#f87171; --commit:#fbbf24; --ai:#a78bfa; }}
* {{ box-sizing:border-box; }}
html, body {{ margin:0; background:var(--bg); color:var(--text);
  font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif; -webkit-print-color-adjust:exact; print-color-adjust:exact; }}
.page {{ width:210mm; min-height:297mm; padding:16mm 15mm; position:relative; page-break-after:always; background:var(--bg); }}
.cover {{ padding:0; display:flex; flex-direction:column; }}
.hero {{ height:170mm; background:linear-gradient(180deg,rgba(11,15,20,.1),rgba(11,15,20,.55) 60%,var(--bg)),
  url({photo('aoa_1')}) center/cover; padding:16mm 15mm; display:flex; flex-direction:column; justify-content:space-between; }}
.brand {{ display:flex; align-items:center; gap:10px; font-weight:800; letter-spacing:3px; }}
.brand span {{ width:36px; height:36px; border-radius:10px; background:var(--teal); color:var(--bg); display:grid; place-items:center; font-size:19px; }}
.hero h1 {{ font-size:44px; line-height:1.08; margin:0; }}
.hero h1 em {{ font-style:normal; color:var(--teal); }}
.hero p {{ font-size:16px; color:#cfd8e1; margin:10px 0 0; max-width:130mm; }}
.coverbody {{ padding:10mm 15mm; display:grid; grid-template-columns:1fr 46mm; gap:10mm; align-items:center; }}
.toc {{ display:grid; grid-template-columns:1fr 1fr; gap:6px 18px; font-size:13px; color:var(--muted); }}
.toc b {{ color:var(--teal); margin-right:6px; }}
.qr {{ background:#fff; border-radius:14px; padding:8px; }}
.qr svg {{ width:100%; height:auto; display:block; }}
.qrcap {{ font-size:11px; color:var(--muted); text-align:center; margin-top:6px; }}
.site {{ margin:0 15mm; padding:12px 16px; border-radius:14px; background:var(--card); border:1px solid var(--line);
  display:flex; justify-content:space-between; align-items:center; font-size:14px; }}
.site a {{ color:var(--teal); font-weight:700; text-decoration:none; }}
.top {{ display:flex; justify-content:space-between; color:var(--muted); font-size:11px; letter-spacing:1.5px; text-transform:uppercase; margin-bottom:8mm; }}
.sec {{ background:var(--card); border:1px solid var(--line); border-radius:18px; padding:14px 18px 12px; margin-bottom:5mm; break-inside:avoid; }}
.head {{ display:flex; align-items:center; gap:12px; margin-bottom:6px; }}
.num {{ font-size:12px; font-weight:800; padding:4px 9px; border-radius:20px; }}
h2 {{ margin:0; font-size:19px; }}
.tone-teal .num {{ background:rgba(94,234,212,.15); color:var(--teal); }}
.tone-income .num {{ background:rgba(52,211,153,.15); color:var(--income); }}
.tone-commit .num {{ background:rgba(251,191,36,.15); color:var(--commit); }}
.tone-ai .num {{ background:rgba(167,139,250,.18); color:var(--ai); }}
.tone-ai {{ border-color:rgba(167,139,250,.35); }}
p {{ font-size:12.5px; line-height:1.55; margin:4px 0 8px; color:#d5dde5; }}
b {{ color:#fff; }}
ol.steps {{ list-style:none; padding:0; margin:4px 0 6px; }}
ol.steps li {{ display:flex; gap:10px; font-size:12.5px; line-height:1.5; margin-bottom:6px; color:#d5dde5; }}
.n {{ flex:0 0 20px; height:20px; border-radius:50%; background:var(--teal); color:var(--bg); font-weight:800; font-size:11px; display:grid; place-items:center; margin-top:1px; }}
ul.dots {{ margin:4px 0 6px; padding-left:16px; }}
ul.dots li {{ font-size:12.5px; line-height:1.5; margin-bottom:5px; color:#d5dde5; }}
ul.dots li::marker {{ color:var(--teal); }}
.tone-ai ul.dots li::marker {{ color:var(--ai); }}
.note {{ font-size:12px; line-height:1.5; background:rgba(94,234,212,.08); border-left:3px solid var(--teal);
  padding:8px 12px; border-radius:8px; color:#d5dde5; margin-top:4px; }}
.tone-ai .note {{ background:rgba(167,139,250,.10); border-color:var(--ai); }}
.safety {{ border-color:rgba(248,113,113,.4); }}
.safety .num {{ background:rgba(248,113,113,.15); color:var(--expense); }}
.safety li::marker {{ color:var(--expense) !important; }}
.end {{ margin-top:6mm; padding:16px 18px; border-radius:18px; display:flex; justify-content:space-between; align-items:center;
  background:linear-gradient(135deg,rgba(94,234,212,.18),rgba(167,139,250,.18)); border:1px solid var(--line); }}
.end a {{ color:var(--teal); font-weight:700; text-decoration:none; }}
.small {{ font-size:10px; color:var(--muted); margin-top:5mm; }}
</style></head><body>

<div class="page cover">
  <div class="hero">
    <div class="brand"><span>F</span>FINTRACK</div>
    <div>
      <h1>Manual de uso<br><em>FINTRACK</em></h1>
      <p>Tudo o que precisa para controlar o seu dinheiro com clareza e segurança, em poucos minutos.</p>
    </div>
  </div>
  <div class="coverbody">
    <div class="toc">{''.join(f'<div><b>{n}</b>{t}</div>' for n, t, _, _ in SECTIONS)}<div><b>10</b>Segurança</div></div>
    <div><div class="qr">{qr_svg}</div><div class="qrcap">Transferir e atualizar</div></div>
  </div>
  <div class="site"><span>Site oficial · transferência e atualizações</span><a href="{SITE}">eusbar.github.io/APPFT</a></div>
</div>

<div class="page">
  <div class="top"><span>FINTRACK · Manual de uso</span><span>Começar</span></div>
  {''.join(section_html(*s) for s in SECTIONS[:3])}
</div>

<div class="page">
  <div class="top"><span>FINTRACK · Manual de uso</span><span>Usar no dia-a-dia</span></div>
  {''.join(section_html(*s) for s in SECTIONS[3:6])}
</div>

<div class="page">
  <div class="top"><span>FINTRACK · Manual de uso</span><span>Dados, conta e segurança</span></div>
  {''.join(section_html(*s) for s in SECTIONS[6:])}
  <section class="sec safety"><div class="head"><span class="num">10</span><h2>Segurança</h2></div>
    <ul class="dots">{tips(SAFETY)}</ul></section>
  <div class="end">
    <div><b>Precisa de ajuda?</b><br><span style="color:var(--muted);font-size:12px">appfintracksolution@gmail.com</span></div>
    <div style="text-align:right"><span style="color:var(--muted);font-size:12px">Última versão sempre em</span><br><a href="{SITE}">eusbar.github.io/APPFT</a></div>
  </div>
  <p class="small">O FINTRACK é uma ferramenta de organização financeira pessoal; não é um banco nem presta aconselhamento financeiro profissional.
  Política de privacidade e termos em eusbar.github.io/APPFT. Fotografia da capa: Quedas de Kalandula, Malanje.</p>
</div>
</body></html>"""

html_path = OUT / "manual.html"
html_path.write_text(HTML, encoding="utf-8")
pdf = OUT / "FINTRACK_Manual.pdf"
subprocess.run(["node", "-e", f"""
const {{chromium}}=require('playwright');(async()=>{{const b=await chromium.launch();const p=await b.newPage();
await p.goto('file://{html_path}');await p.pdf({{path:'{pdf}',format:'A4',printBackground:true,preferCSSPageSize:true}});await b.close()}})()"""], check=True)
print("Manual:", pdf)
