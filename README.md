# FINTRACK

*Your Money. Under Control.*

App de gestão e inteligência financeira pessoal (Android e iOS, Flutter), construído a partir do **Prompt Master 4.0**.

## Estado

**Fase 1 — Fundação** ✅ · **Fase 2 — Gestão financeira** ✅ · **Fase 3 — Motor financeiro** ✅ · **Fase 4 — Relatórios e importação** ✅ · **Fase 5 — Planeamento** ✅ · **Etapa 3 — Publicação, sem pagamentos** ✅ · **Etapa 4 — Nuvem** ✅ · **Etapa 5A — FINTRACK AI local** ✅ (v0.13.0)

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
- `PeriodReport` (núcleo): abertura, entradas, saídas, transferências, fecho, categorias, contas e compromissos pendentes por moeda; `MovementCsv` com proteção contra fórmulas
- `lib/reports/`: relatório mensal no app, PDF A4 (cabeçalho, resumo, categorias, contas, compromissos, movimentos, paginação) e CSV para Excel, partilhados manualmente
- Importação (núcleo `importer.dart` + `lib/importing/`): CSV (";", "," ou tabulação, UTF-8 ou Latin-1) e Excel .xlsx; deteção de colunas (incl. débito/crédito de extratos), datas e números de série do Excel, pré-visualização, duplicados desmarcados e anulação da importação inteira com estornos
- Contas: editar; corrigir o saldo inicial e apagar só sem histórico; arquivar e reativar
- Histórico: filtros por período, conta, categoria e intervalo de valores
- Planeamento (núcleo `planning.dart`): orçamentos mensais (global ou por categoria, transporte de saldo, alertas 50/80/100%, estimativa de fim de mês), objetivos (reservados numa conta ou planeados, contribuição mensal necessária, marcos), compromissos recorrentes (semanal, mensal, anual; nunca pagos sozinhos) e categorização local pelo histórico
- Perfil: nome, alcunha e fotografia (reduzida, na base cifrada)
- Kixikila (núcleo `kixikila.dart`): grupos, rondas, contribuições e recebimento ligados ao livro-razão
- Lembretes locais (compromissos e Kixikila, sem valores no ecrã bloqueado) e alertas de orçamento
- Privacidade: consentimento explicado antes de fotografias, ficheiros e notificações; revogável nas Definições
- Categorias: criar, renomear, mudar o ícone e arquivar
- Os seus dados: cópia de segurança cifrada (Argon2id + AES-256-GCM) com restauro, exportação completa em JSON
- Política de privacidade e termos (`assets/legal/`, no app e públicos); ficha da Play Store em `docs/PLAY_STORE.md`
- Nuvem (`lib/cloud/`, `supabase/migrations/`): conta Supabase (e-mail e palavra-passe), cifra ponta-a-ponta XChaCha20-Poly1305 de cada registo, chave embrulhada pela palavra-passe e por um código de recuperação (Argon2id + AES-GCM), sincronização offline-first por resumos SHA-256, movimentos só acrescentam também no servidor, RLS por utilizador, eliminação da conta no app
- FINTRACK AI local (núcleo `src/ai/`): Smart Entry por texto e SMS colado (nunca adivinha conta nem moeda), AI Guard (duplicados, valores fora do padrão por mediana/MAD, disponível negativo) e validador de números das respostas da IA; separador IA no app
- `tool/configure_android.py`: compileSdk 37, desugaring e recetores de notificações
- `lib/planning/`: compromissos — criar, editar, pagar (gera a saída ligada), cancelar
- `lib/home/`: Início (saldo disponível com horizonte, dicas rotativas, fluxo do mês, próximos compromissos, contas, recentes), Movimentos, Planear, Contas
- fundos com pontos turísticos da região da moeda principal (5 por moeda)
- `lib/design/`: design system, fundos fotográficos desfocados, textos em português
- `tool/configure_platforms.sh`: nome FINTRACK, ícone, biometria e tema nas pastas Android/iOS geradas no CI

**Limitações conhecidas**

- O limite de tentativas do PIN é aplicado por software e usa o relógio do dispositivo.
- Falta o `FLAG_SECURE` nativo no Android (a capa de privacidade é desenhada pelo Flutter).
- Sem conta na nuvem, 10 falhas de PIN só se resolvem repondo o app.
- Sem os segredos `FINTRACK_KEYSTORE_*` no GitHub, o APK é assinado com uma chave de teste diferente em cada compilação (para atualizar é preciso desinstalar).
- Os ficheiros exportados (PDF/CSV) não são cifrados.

**Etapa 4B:** confirmação da conta e código de 6 dígitos em dispositivos novos (ativos assim que houver SMTP próprio), lista de dispositivos com aviso de nova sessão e terminar sessões remotas, sincronização ao voltar ao app e a cada 10 minutos. Sem sincronização em segundo plano: a base só abre com PIN/biometria.

**A seguir (etapa 5B):** Copilot com o Claude através de um gateway (Edge Function), com consentimento e validador de números.

## Créditos

Fotografias de fundo: [Unsplash](https://unsplash.com) (Licença Unsplash) e, para Angola, fornecidas pelo autor do projeto. Desfocadas e reduzidas.

## Compilação

Cada envio para `main` corre o workflow **Build** no GitHub Actions: analisa, testa e gera o APK, disponível em *Actions → última execução → Artifacts → fintrack-apk*.

Localmente, com o Flutter instalado:

```sh
flutter create --platforms=android,ios --org ao.fintrack --project-name fintrack .
flutter pub get
flutter test
flutter run
```
