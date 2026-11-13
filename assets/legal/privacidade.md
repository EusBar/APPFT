# Política de Privacidade do FINTRACK

Última atualização: 13 de novembro de 2026

O FINTRACK é uma aplicação de gestão financeira pessoal. Esta política explica que dados trata, onde ficam e que direitos tem. Escrevemo-la em linguagem simples, de acordo com a Lei n.º 22/11 de Angola (Lei da Proteção de Dados Pessoais) e, quando aplicável, com o RGPD (Europa) e a LGPD (Brasil).

## O essencial

- Os seus dados financeiros ficam **apenas no seu telemóvel**, numa base de dados cifrada (AES-256).
- Nesta versão, o FINTRACK **não envia dados para servidores**, não tem publicidade e não usa ferramentas de análise ou rastreio.
- O FINTRACK **não se liga a bancos**, não pede credenciais bancárias e não movimenta dinheiro.
- Pode **exportar** ou **apagar** todos os seus dados a qualquer momento, dentro da aplicação.

## Que dados tratamos

- **Perfil:** nome, alcunha e, se quiser, uma fotografia.
- **Dados financeiros que regista:** contas, saldos iniciais, movimentos, categorias, compromissos, orçamentos, objetivos e grupos de Kixikila (os outros membros são apenas nomes que escreve).
- **Segurança:** o PIN nunca é guardado. Guardamos apenas um verificador derivado com Argon2id e as chaves no Android Keystore ou no iOS Keychain.

## Onde ficam e como são protegidos

- Base de dados local cifrada com SQLCipher (AES-256). A chave só é libertada com o seu PIN ou a sua biometria.
- A biometria é verificada pelo sistema do telemóvel. O FINTRACK nunca recebe a sua impressão digital nem o seu rosto.
- As cópias de segurança são cifradas com a palavra-passe que escolher (Argon2id + AES-256-GCM). Sem essa palavra-passe, ninguém as consegue abrir, nem nós.
- Sem cópias automáticas para a nuvem do sistema: os dados não saem do aparelho sem uma ação sua.

## Permissões

O FINTRACK pede cada acesso só quando é preciso e explica porquê antes de o pedir:

- **Fotografias:** para escolher a fotografia do perfil. O seletor do sistema entrega apenas a fotografia escolhida.
- **Ficheiros:** para importar movimentos de CSV ou Excel, ou restaurar uma cópia. Só é lido o ficheiro escolhido.
- **Notificações:** para lembrar compromissos e contribuições. Os avisos não mostram valores no ecrã bloqueado.
- **Biometria:** opcional, como atalho do PIN.

Pode retirar cada consentimento em Definições › Privacidade e permissões.

## Partilha com terceiros

Não vendemos, não alugamos e não partilhamos os seus dados. Os relatórios em PDF ou CSV e as exportações só saem do telemóvel quando os partilha manualmente, e o destino é escolhido por si.

## Funcionalidades futuras

Quando existirem a conta na nuvem, a sincronização e o assistente de inteligência artificial, esta política será atualizada **antes** de essas funções ficarem disponíveis, e pediremos o seu consentimento explícito. A inteligência artificial na nuvem será opcional e receberá apenas dados agregados e minimizados.

## Os seus direitos

Tem direito a aceder aos seus dados, corrigi-los, exportá-los e apagá-los. Na aplicação:

- **Exportar:** Definições › Os seus dados › Exportar todos os dados.
- **Apagar:** Definições › Apagar tudo e repor. Os dados são apagados do telemóvel de imediato.

## Menores

O FINTRACK destina-se a maiores de 18 anos.

## Contacto

Para questões sobre privacidade: **[e-mail de contacto a indicar antes da publicação]**.

## Alterações

Avisaremos dentro da aplicação sempre que esta política mudar de forma relevante.
