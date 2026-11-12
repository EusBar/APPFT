# FINTRACK

*Your Money. Under Control.*

App de gestão e inteligência financeira pessoal (Android e iOS, Flutter), construído a partir do **Prompt Master 4.0**.

## Estado

**Fase 1 — Fundação** ✅ · **Fase 2 — Gestão financeira** ✅ · **Fase 3 — Motor financeiro (v0.5.0)**

- `packages/fintrack_core`: núcleo em Dart puro, sem UI
  - `Money` (inteiros na unidade mínima), `Currency` (AOA, USD, EUR, BRL, GBP, ZAR)
  - `Account`, `AccountType`, `Category` (categorias iniciais da secção 7)
  - `Movement`: entrada, saída e transferência própria (com valor enviado e recebido)
  - `Ledger`: livro-razão imutável — saldos, totais do período, validação, estornos, duplicados
  - `Commitment` e `AvailableHorizon`: compromissos (pendente, pago, cancelado) e saldo disponível com horizonte (fim do mês, 7, 30 ou 90 dias)
  - o estado de um compromisso pago deriva do livro-razão: anular o pagamento reabre-o, corrigir mantém-no pago
  - testes de propriedades: transferências não alteram o consolidado; recalcular dá sempre o mesmo; pagar um compromisso nunca o desconta duas vezes
- `lib/security/`: PIN (Argon2id + AES-256-GCM), **biometria** (chave no Keystore/Keychain com biometria forte obrigatória, via `flutter_secure_storage`), bloqueio automático, modo discreto
- `lib/data/`: base SQLCipher (AES-256). Gatilhos impedem alterar ou apagar movimentos; cada um só pode ser estornado uma vez
- `lib/finance/`: novo movimento, correção (estorno + novo registo), anulação, histórico com pesquisa e filtros
- `lib/planning/`: compromissos — criar, editar, pagar (gera a saída ligada), cancelar
- `lib/home/`: Início (saldo disponível com horizonte, dicas rotativas, fluxo do mês, próximos compromissos, contas, recentes), Movimentos, Planear, Contas
- fundos com pontos turísticos da região da moeda principal (5 por moeda; Angola em preparação)
- `lib/design/`: design system, fundos fotográficos desfocados, textos em português
- `tool/configure_platforms.sh`: nome FINTRACK, ícone, biometria e tema nas pastas Android/iOS geradas no CI

**Limitações conhecidas**

- O limite de tentativas do PIN é aplicado por software e usa o relógio do dispositivo.
- Falta o `FLAG_SECURE` nativo no Android (a capa de privacidade é desenhada pelo Flutter).
- Sem conta na nuvem, 10 falhas de PIN só se resolvem repondo o app.
- O APK é assinado com uma chave de teste gerada em cada compilação: para atualizar, desinstale a versão anterior (perde os dados de teste).

**A seguir:** fotografias de Angola; gerir categorias e arquivar contas; Fase 4 — dashboard completo, relatórios PDF/CSV e importação.

## Créditos

Fotografias de fundo: [Unsplash](https://unsplash.com) (Licença Unsplash), desfocadas e reduzidas.

## Compilação

Cada envio para `main` corre o workflow **Build** no GitHub Actions: analisa, testa e gera o APK, disponível em *Actions → última execução → Artifacts → fintrack-apk*.

Localmente, com o Flutter instalado:

```sh
flutter create --platforms=android,ios --org ao.fintrack --project-name fintrack .
flutter pub get
flutter test
flutter run
```
