# Política de Privacidade do FINTRACK

Última atualização: 14 de novembro de 2026

O FINTRACK é uma aplicação de gestão financeira pessoal. Esta política explica que dados trata, onde ficam e que direitos tem. Escrevemo-la em linguagem simples, de acordo com a Lei n.º 22/11 de Angola (Lei da Proteção de Dados Pessoais) e, quando aplicável, com o RGPD (Europa) e a LGPD (Brasil).

## O essencial

- Os seus dados financeiros ficam no seu telemóvel, numa base de dados cifrada (AES-256).
- A **conta FINTRACK é opcional**. Se a criar, os dados são cifrados no telemóvel **antes** de seguirem para a nuvem (cifra ponta-a-ponta): o servidor só guarda texto ilegível e nem nós os conseguimos ler.
- A **inteligência artificial do FINTRACK corre no telemóvel**. Nenhum dado é enviado a serviços de IA.
- Não há publicidade nem ferramentas de análise ou rastreio.
- O FINTRACK **não se liga a bancos**, não pede credenciais bancárias e não movimenta dinheiro.
- Pode **exportar** ou **apagar** todos os seus dados a qualquer momento, dentro da aplicação.

## Que dados tratamos

- **Perfil:** nome, alcunha e, se quiser, uma fotografia.
- **Dados financeiros que regista:** contas, saldos iniciais, movimentos, categorias, compromissos, orçamentos, objetivos e grupos de Kixikila (os outros membros são apenas nomes que escreve).
- **Segurança:** o PIN nunca é guardado. Guardamos apenas um verificador derivado com Argon2id e as chaves no Android Keystore ou no iOS Keychain.
- **Conta FINTRACK (opcional):** e-mail, palavra-passe (guardada pelo fornecedor de autenticação apenas em forma irreversível), nome e sistema de cada telemóvel ligado à conta, e os seus dados financeiros **cifrados** no telemóvel.
- **Premium (opcional):** o plano subscrito e a data de validade, confirmados junto da Google Play ou da App Store. Os dados de pagamento ficam apenas na loja; o FINTRACK nunca os recebe.

## Onde ficam e como são protegidos

- Base de dados local cifrada com SQLCipher (AES-256). A chave só é libertada com o seu PIN ou a sua biometria.
- A biometria é verificada pelo sistema do telemóvel. O FINTRACK nunca recebe a sua impressão digital nem o seu rosto.
- As cópias de segurança são cifradas com a palavra-passe que escolher (Argon2id + AES-256-GCM). Sem essa palavra-passe, ninguém as consegue abrir, nem nós.
- Sem cópias automáticas para a nuvem do sistema (Google ou iCloud).
- **Nuvem do FINTRACK:** servidores Supabase na União Europeia (Frankfurt). Cada registo é cifrado no telemóvel com XChaCha20-Poly1305; a chave só existe nos seus telemóveis, protegida pela sua palavra-passe e por um código de recuperação que só o utilizador conhece. Cada pessoa só tem acesso às suas próprias linhas.
- **Códigos por e-mail:** ao criar conta ou entrar num telemóvel novo, enviamos um código de 6 dígitos para o seu e-mail.

## Permissões

O FINTRACK pede cada acesso só quando é preciso e explica porquê antes de o pedir:

- **Fotografias:** para escolher a fotografia do perfil. O seletor do sistema entrega apenas a fotografia escolhida.
- **Ficheiros:** para importar movimentos de CSV ou Excel, ou restaurar uma cópia. Só é lido o ficheiro escolhido.
- **Notificações:** para lembrar compromissos e contribuições. Os avisos não mostram valores no ecrã bloqueado.
- **Biometria:** opcional, como atalho do PIN.

Pode retirar cada consentimento em Definições › Privacidade e permissões.

## Partilha com terceiros

Não vendemos, não alugamos e não partilhamos os seus dados. Os relatórios em PDF ou CSV e as exportações só saem do telemóvel quando os partilha manualmente, e o destino é escolhido por si.

Prestadores que nos ajudam a funcionar, apenas na medida necessária:

- **Supabase** (alojamento da nuvem e autenticação): guarda o e-mail e os dados já cifrados.
- **Google (Gmail)**: envia os e-mails com os códigos.
- **Google Play e App Store**: tratam os pagamentos do Premium; o FINTRACK só recebe a confirmação e a validade.

## Inteligência artificial

O Smart Entry, o AI Guard, o pulso financeiro, as tendências e as respostas do "Pergunte ao FINTRACK" são calculados **no seu telemóvel**, sem Internet. Se um dia existir uma função de IA na nuvem, será opcional, esta política será atualizada antes e pediremos o seu consentimento explícito.

## Os seus direitos

Tem direito a aceder aos seus dados, corrigi-los, exportá-los e apagá-los. Na aplicação:

- **Exportar:** Definições › Os seus dados › Exportar todos os dados.
- **Apagar do telemóvel:** Definições › Apagar tudo e repor. Os dados são apagados do telemóvel de imediato.
- **Apagar a conta e os dados na nuvem:** Definições › Conta e sincronização › Eliminar conta e dados na nuvem. Tudo é apagado do servidor de imediato.
- **Cancelar o Premium:** nas subscrições da Google Play ou da App Store.

## Menores

O FINTRACK destina-se a maiores de 18 anos.

## Contacto

Para questões sobre privacidade: **appfintracksolution@gmail.com**.

## Alterações

Avisaremos dentro da aplicação sempre que esta política mudar de forma relevante.
