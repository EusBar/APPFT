# FINTRACK — Lançamento nas lojas

Tudo o que falta para publicar depende de contas e pagamentos do responsável
pelo projeto. O código, o servidor e a compilação já estão preparados.

## 1. Google Play (Android)

1. Criar a conta de programador em **play.google.com/console** (25 USD, uma vez),
   com appfintracksolution@gmail.com.
2. Criar a aplicação **FINTRACK** (pacote `ao.fintrack.fintrack`) e preencher a
   ficha com `docs/PLAY_STORE.md`.
3. Gerar o pacote da loja: GitHub → Actions → **Build** → *Run workflow*. O
   artefacto **fintrack-play-aab** traz o `app-release.aab` (e os símbolos de
   depuração, para relatórios de falhas legíveis).
4. Enviar o `.aab` para **Teste interno** e depois **Produção**.
5. **Monetização → Subscrições:** criar `fintrack_premium_monthly` e
   `fintrack_premium_yearly`, com os preços escolhidos.
6. **Confirmação no servidor:** na Google Cloud, criar uma conta de serviço com
   acesso à *Google Play Android Developer API*; na Play Console, dar-lhe acesso
   a "Ver dados financeiros e gerir encomendas e subscrições". Guardar o JSON da
   chave no Supabase → Edge Functions → Secrets como `GOOGLE_SERVICE_ACCOUNT`.

## 2. App Store (iPhone)

1. Inscrever-se no **Apple Developer Program** (99 USD/ano) na app *Apple Developer*.
2. Na **App Store Connect**, criar a app com o identificador `ao.fintrack.fintrack`.
3. **Users and Access → Integrations → App Store Connect API:** criar uma chave
   (função *App Manager*). Guardar nos Segredos do GitHub:
   - `APPLE_ASC_KEY_ID` (Key ID), `APPLE_ASC_ISSUER_ID` (Issuer ID),
   - `APPLE_ASC_KEY_P8` (conteúdo do ficheiro `.p8`),
   - `APPLE_TEAM_ID` (Membership → Team ID).
4. GitHub → Actions → **Build** → *Run workflow*: o trabalho **ios-testflight**
   assina e envia a versão para o **TestFlight**.
5. **Subscrições:** criar o grupo "FINTRACK Premium" com os mesmos dois produtos.
6. **Confirmação no servidor:** criar uma chave *In-App Purchase* (Users and
   Access → Integrations → In-App Purchase) e guardar no Supabase → Edge
   Functions → Secrets: `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`.
7. Preencher as etiquetas de privacidade e a ficha (mesmos textos da Google Play).

## 3. Antes de publicar

- [x] Autorização para usar as 5 fotografias de Angola (confirmada pelo responsável).
- [ ] Decidir os preços do Premium (mensal e anual).
- [ ] Ativar o GitHub Pages (Settings → Pages → ramo principal, pasta `/docs`). Endereços:
  - Política de privacidade: https://eusbar.github.io/APPFT/privacidade.html
  - Termos de utilização: https://eusbar.github.io/APPFT/termos.html
- [ ] Fazer uma compra de teste em cada loja e confirmar que o Premium abre.
