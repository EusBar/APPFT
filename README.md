# FINTRACK

*Your Money. Under Control.*

App de gestão e inteligência financeira pessoal (Android e iOS, Flutter), construído a partir do **Prompt Master 4.0**.

## Estado

**Fase 1 — Fundação (v0.3.0)**

- `packages/fintrack_core`: núcleo em Dart puro, sem UI
  - `Money`: valores em inteiros na unidade mínima, formato `1 234 567,89 Kz`
  - `Currency`: AOA, USD, EUR, BRL, GBP, ZAR
  - `Account` e `AccountType`: banco, numerário, carteira móvel, cartão, poupança
  - `Balances`: totais por moeda, sem nunca somar moedas diferentes; poupança fora do disponível
  - `PinPolicy`, `LockoutPolicy`, `AutoLockPolicy`, `NameRules`, `newId` (UUID v4)
- `lib/design/`: design system (tokens, cores semânticas, temas claro e escuro) e textos em português
- `lib/security/`: desbloqueio local
  - `PinVault`: Argon2id + AES-256-GCM; o PIN nunca é guardado; segredos no Keystore/Keychain
  - criação e confirmação do PIN, ecrã de bloqueio com contagem decrescente
  - bloqueio automático configurável, capa de privacidade, modo discreto
- `lib/data/`: base de dados local cifrada com **SQLCipher** (AES-256); a chave de 256 bits só é libertada pelo PIN
- `lib/onboarding/`: nome, moeda principal e primeira conta, em três passos
- `lib/home/`: saldo disponível, total e lista de contas; criar novas contas
- `lib/settings/`: bloqueio automático (imediato, 1, 5 ou 15 min) e apagar tudo

**Limitações conhecidas**

- O limite de tentativas é aplicado por software e usa o relógio do dispositivo; ainda não é imposto por hardware.
- A capa de privacidade é desenhada pelo Flutter; falta o `FLAG_SECURE` nativo no Android.
- Sem conta na nuvem, 10 falhas de PIN só se resolvem repondo o app.
- Ainda não há movimentos: o saldo de cada conta é o saldo inicial.

**A seguir na Fase 1:** biometria. Depois, Fase 2: movimentos (entradas, saídas, transferências) com livro-razão imutável.

## Compilação

Cada envio para `main` corre o workflow **Build** no GitHub Actions: analisa, testa e gera o APK, disponível em *Actions → última execução → Artifacts → fintrack-apk*.

Localmente, com o Flutter instalado:

```sh
flutter create --platforms=android,ios --org ao.fintrack --project-name fintrack .
flutter pub get
flutter test
flutter run
```
