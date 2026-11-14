# FINTRACK — Ficha da Play Store e lista de publicação

Tudo o que é preciso para publicar, pronto a copiar. Os passos com 💳 só se fazem
depois de pagar a conta de programador (deixados para o fim, por decisão do projeto).

## 1. Ficha da loja

**Nome (30):** FINTRACK — Finanças Pessoais

**Descrição curta (80):**
Controle o seu dinheiro com segurança: contas, orçamentos, Kixikila e relatórios.

**Descrição completa (até 4000):**

FINTRACK — Your Money. Under Control.

Organize as suas finanças pessoais num só lugar, com segurança de nível bancário e
sem ligar o app ao seu banco.

SEGURANÇA PRIMEIRO (grátis, sempre)
• PIN de 6 dígitos e desbloqueio por impressão digital ou rosto
• Base de dados cifrada (AES-256) e chaves protegidas pelo telemóvel
• Bloqueio automático, ecrã protegido e modo discreto para ocultar valores
• Os seus dados ficam no seu telemóvel; sem publicidade e sem rastreio

TODO O SEU DINHEIRO
• Bancos, numerário, carteiras móveis, cartões e poupança
• Kwanza e outras moedas, sem nunca misturar valores sem câmbio
• Entradas, saídas e transferências entre contas
• Histórico que nunca se apaga: as correções ficam registadas

PLANEAR
• Compromissos (renda, propinas, prestações) que reduzem o saldo disponível
• Orçamentos com alertas a 50%, 80% e 100%
• Objetivos com quanto juntar por mês
• Kixikila: rondas, contribuições e a sua vez de receber
• Lembretes que nunca mostram valores no ecrã bloqueado

RELATÓRIOS E DADOS
• Relatório mensal em PDF e exportação para Excel (CSV)
• Importação de extratos e folhas de cálculo (CSV e Excel)
• Cópia de segurança cifrada com palavra-passe

O FINTRACK não é um banco, não movimenta dinheiro e não presta aconselhamento
financeiro profissional.

**E-mail de contacto:** appfintracksolution@gmail.com

**Categoria:** Finanças · **Etiquetas:** finanças pessoais, orçamento, poupança
**Classificação de conteúdo:** Todos (sem conteúdo sensível; questionário IARC)
**Público-alvo:** 18+

**Recursos gráficos (no repositório):**
- Ícone 512×512: `assets/store/icon_512.png`
- Imagem de destaque 1024×500: `assets/store/feature_graphic.png`
- Capturas de ecrã (2 a 8, telemóvel): a tirar com o **modo de demonstração** (etapa futura) ou com dados fictícios — nunca com dados reais.

**Política de privacidade (URL pública):**
`https://eusbar.github.io/APPFT/privacidade.html`
(depois de juntar o trabalho ao ramo `main`; antes disso, usar o ramo atual)

## 2. Formulário "Segurança dos dados" (respostas para esta versão)

| Pergunta | Resposta |
|---|---|
| Recolhe ou partilha dados de utilizadores? | **Não recolhe** (os dados ficam no aparelho e não são enviados ao programador) |
| Dados encriptados em trânsito? | Não aplicável (não há envio) |
| O utilizador pode pedir a eliminação? | **Sim** — "Apagar tudo e repor" dentro do app |
| Segue a Política para Famílias? | Não (18+) |

Nota: quando houver conta na nuvem, sincronização ou IA, este formulário **tem de ser
atualizado antes** de publicar essa versão.

## 3. Declarações da Play Console

- **Funcionalidades financeiras:** app de gestão pessoal / orçamento; **não** oferece
  empréstimos, pagamentos, criptomoedas nem serviços bancários.
- **Permissões sensíveis:** nenhuma. Fotografias e ficheiros usam os seletores do
  sistema (sem `READ_MEDIA_IMAGES` nem `READ_EXTERNAL_STORAGE`); sem leitura de SMS.
- **Alarmes exatos:** não usados (lembretes inexatos).
- **Eliminação de conta:** sem conta na nuvem nesta versão; eliminação local disponível.
  Quando houver conta: eliminação no app **e** numa página web.
- **Anúncios:** não contém.

## 4. Lista de publicação

- [x] Política de privacidade e termos (no app e no repositório)
- [x] Eliminação e exportação de dados dentro do app
- [x] Assinatura fixa do APK (segredos no GitHub)
- [x] Ícone 512 e imagem de destaque
- [x] E-mail de contacto: appfintracksolution@gmail.com (política, termos e ficha)
- [ ] Capturas de ecrã com dados fictícios
- [ ] 💳 Conta de programador Google Play (25 USD) e verificação de identidade
- [ ] 💳 Gerar **AAB** (`flutter build appbundle`) e ativar a Assinatura de apps da Play
- [ ] 💳 Teste fechado: **12 testadores durante 14 dias** (contas pessoais novas)
- [ ] 💳 Pedido de acesso à produção e publicação

## 5. App Store (iOS) — para depois

- [ ] 💳 Apple Developer (99 USD/ano) e compilação iOS no CI (macOS)
- [ ] Etiquetas de privacidade (equivalentes ao ponto 2)
- [ ] TestFlight e revisão da App Store
