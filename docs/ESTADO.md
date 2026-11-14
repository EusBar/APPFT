# FINTRACK — Estado do projeto (para continuar noutra conversa)

Atualizado: 14 de novembro de 2026 · Versão **1.0.0+30** · Ramo principal: `ccr-ab042d49-b2g5qo`

## Plano principal (1 a 7) — concluído
1. Importação (CSV/Excel) e filtros
2. Planeamento: compromissos, orçamentos, objetivos, Kixikila, lembretes
3. Preparação da publicação: ficha (`docs/PLAY_STORE.md`), ícones, textos legais,
   páginas públicas em https://eusbar.github.io/APPFT/ (geradas por `tool/build_legal_site.py`)
4. Nuvem (Supabase, projeto `ombecebntvsidifctjts`, Frankfurt): conta, sincronização
   cifrada ponta-a-ponta, códigos por e-mail (SMTP Gmail appfintracksolution@gmail.com),
   dispositivos, terminar sessão → vitrine
5. FINTRACK AI **só no telemóvel** (decisão do responsável: sem IA na nuvem/Anthropic):
   Smart Entry, AI Guard, "Pergunte ao FINTRACK", pulso financeiro, tendências
6. Premium: 14 dias grátis; subscrições `fintrack_premium_monthly` / `fintrack_premium_yearly`
7. Reforço: limites no servidor, função `verify-purchase` (confirma compras na loja,
   tabela `subscriptions`), cache no livro-razão, código ofuscado, .aab e TestFlight preparados

## Pendente (depende do responsável) — ver `docs/LANCAMENTO.md`
- Contas Google Play e Apple Developer; preços do Premium; Supabase Pro no lançamento.
- Fotografias de Angola: autorizadas.

## Como se trabalha neste projeto
- O responsável usa só o telemóvel e escreve em português (Angola); respostas em português,
  curtas, com o link do APK no fim de cada alteração.
- Flutter não corre no ambiente de desenvolvimento: tudo é verificado no GitHub Actions
  (`.github/workflows/build.yml`: núcleo + análise + testes + APK; job `ios` compila no Mac Intel).
- APK: Actions → execução com visto verde → artefacto **fintrack-apk**.
- Segredos (nunca no chat): assinatura Android nos Segredos do GitHub; chaves das lojas
  no Supabase (Edge Functions → Secrets) e no GitHub, conforme `docs/LANCAMENTO.md`.
- Design: estilo iOS/Spotify, paisagens do banco de imagens a rodar de 30 em 30 s com o nome
  do lugar na fotografia, texto sobre placas escuras translúcidas.

## Estrutura
- `packages/fintrack_core/` — regras em Dart puro (livro-razão, dinheiro, planeamento, IA local) + testes
- `lib/` — app Flutter (security, cloud, ai, premium, planning, home, ...)
- `supabase/` — migrações SQL e funções (`verify-purchase`)
- `tool/` — scripts de configuração do CI (Android, iOS, assinatura) e das páginas legais
