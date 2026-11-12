# FINTRACK

*Your Money. Under Control.*

App de gestão e inteligência financeira pessoal (Android e iOS, Flutter), construído a partir do **Prompt Master 4.0**.

## Estado

**Fase 1 — Fundação (v0.2.0)** · ainda por compilar no GitHub Actions

- `packages/fintrack_core`: núcleo em Dart puro, sem UI
  - `Money`: valores em inteiros na unidade mínima, formato `1 234 567,89 Kz`
  - `Currency`: AOA, USD, EUR, BRL, GBP, ZAR
  - `PinPolicy`: recusa PINs triviais (repetidos, sequências, datas)
  - `LockoutPolicy`: atrasos progressivos e limite de 10 tentativas
  - `AutoLockPolicy`: bloqueio automático (imediato, 1, 5 ou 15 minutos)
- `lib/design/tokens.dart`: design system (cores semânticas, espaçamento, raios, animação, temas claro e escuro)
- `lib/security/`: desbloqueio local
  - `PinVault`: Argon2id + AES-256-GCM; o PIN nunca é guardado; segredos no Keystore/Keychain
  - criação e confirmação do PIN, ecrã de bloqueio com contagem decrescente
  - bloqueio automático em segundo plano, capa de privacidade, modo discreto

**Limitações conhecidas**

- O limite de tentativas é aplicado por software e usa o relógio do dispositivo; ainda não é imposto por hardware.
- A capa de privacidade é desenhada pelo Flutter; falta o `FLAG_SECURE` nativo no Android.
- Sem conta na nuvem, 10 falhas de PIN só se resolvem repondo o app.

**A seguir na Fase 1:** base de dados cifrada (SQLCipher), onboarding (nome, moeda, primeira conta), biometria, definições de segurança.

## Compilação

Cada envio para `main` corre o workflow **Build** no GitHub Actions: analisa, testa e gera o APK, disponível em *Actions → última execução → Artifacts → fintrack-apk*.

Localmente, com o Flutter instalado:

```sh
flutter create --platforms=android,ios --org ao.fintrack --project-name fintrack .
flutter pub get
flutter test
flutter run
```
