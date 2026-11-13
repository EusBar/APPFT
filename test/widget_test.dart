import 'dart:typed_data';

import 'package:fintrack/data/local_store.dart';
import 'package:fintrack/cloud/cloud_api.dart';
import 'package:fintrack/cloud/cloud_controller.dart';
import 'package:fintrack/main.dart';
import 'package:fintrack/onboarding/onboarding_screen.dart';
import 'package:fintrack/notifications/reminders.dart';
import 'package:fintrack/security/biometric_key_store.dart';
import 'package:fintrack/security/pin_vault.dart';
import 'package:fintrack/security/secret_store.dart';
import 'package:fintrack/security/session.dart';
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Derivação falsa e instantânea: os testes de interface não precisam do
/// Argon2id real (testado em pin_vault_test.dart).
Future<Uint8List> fakeDerive(String pin, List<int> salt, Argon2Params _) async =>
    Uint8List.fromList([
      for (var i = 0; i < 64; i++) (pin.codeUnitAt(i % pin.length) * 31 + salt[i % salt.length] + i) & 0xff,
    ]);

void main() {
  late MemorySecretStore secrets;
  late MemoryLocalStore data;
  late MemoryBiometricKeyStore bio;
  late MemoryReminders reminders;
  late MemoryCloudApi cloud;

  setUp(() {
    cloud = MemoryCloudApi();
    reminders = MemoryReminders();
    secrets = MemorySecretStore();
    data = MemoryLocalStore();
    bio = MemoryBiometricKeyStore();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secretStoreProvider.overrideWithValue(secrets),
          pinVaultProvider.overrideWithValue(PinVault(secrets, deriver: fakeDerive)),
          localStoreFactoryProvider.overrideWithValue(data),
          biometricKeyStoreProvider.overrideWithValue(bio),
          remindersProvider.overrideWithValue(reminders),
          cloudApiProvider.overrideWithValue(cloud),
          cloudDeriverProvider.overrideWithValue(fakeDerive),
        ],
        child: const FintrackApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Faz scroll até ao botão antes de tocar (o ecrã de teste é 800x600).
  Future<void> tapText(WidgetTester tester, String text) async {
    // Listas só constroem o que está perto do ecrã: desliza até encontrar.
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        150,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('sem PIN, o app abre na criação do PIN', (tester) async {
    await pumpApp(tester);
    expect(find.text('Crie um PIN de 6 dígitos'), findsOneWidget);
  });

  testWidgets('recusa um PIN trivial com explicação', (tester) async {
    await pumpApp(tester);
    await typePin(tester, '123456');
    expect(find.textContaining('sequência'), findsOneWidget);
    expect(find.text('Crie um PIN de 6 dígitos'), findsOneWidget);
  });

  testWidgets('PIN aceitável passa à confirmação; diferente recomeça', (tester) async {
    await pumpApp(tester);
    await typePin(tester, '482917');
    expect(find.text('Confirme o PIN'), findsOneWidget);

    await typePin(tester, '482918');
    expect(find.textContaining('não coincidem'), findsOneWidget);
    expect(find.text('Crie um PIN de 6 dígitos'), findsOneWidget);
  });

  testWidgets('PIN, onboarding e primeira conta chegam ao início', (tester) async {
    await pumpApp(tester);
    await typePin(tester, '482917');
    await typePin(tester, '482917');

    // Passo 1: nome (vazio é recusado).
    expect(find.text('Como se chama?'), findsOneWidget);
    await tapText(tester, 'Continuar');
    expect(find.text('Escreva o seu nome.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-name')), '  Ana   Maria ');
    await tapText(tester, 'Continuar');

    // Passo 2: moeda principal (Kwanza por defeito).
    expect(find.text('Moeda principal'), findsOneWidget);
    await tapText(tester, 'Continuar');

    // Passo 3: primeira conta.
    expect(find.text('Primeira conta'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('account-balance')), '12 500,5');
    await tapText(tester, 'Começar');

    expect(find.text('Olá, Ana'), findsOneWidget);
    expect(data.profile?.name, 'Ana Maria');
    expect(data.profile?.mainCurrency, Currency.aoa);
    expect(data.stored.single.openingBalance, const Money(1250050, Currency.aoa));
    expect(data.openedWith, hasLength(32));
    await tester.scrollUntilVisible(
      find.text('Conta à ordem'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Conta à ordem'), findsOneWidget);

    // Modo discreto oculta os valores.
    expect(find.textContaining('12\u00A0500,50'), findsWidgets);
    await tester.tap(find.byTooltip('Ocultar valores'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12\u00A0500,50'), findsNothing);

    // Bloquear fecha a base e pede o PIN.
    await tester.tap(find.byTooltip('Bloquear'));
    await tester.pumpAndSettle();
    expect(find.text('Introduza o PIN'), findsOneWidget);
    expect(data.closed, isTrue);

    // Desbloquear volta ao início, sem repetir o onboarding.
    await typePin(tester, '482917');
    expect(find.text('Olá, Ana'), findsOneWidget);
  });

  /// PIN criado e onboarding feito com uma conta de 100 000,00 Kz.
  Future<void> setUpUser(WidgetTester tester) async {
    await pumpApp(tester);
    await typePin(tester, '482917');
    await typePin(tester, '482917');
    await tester.enterText(find.byKey(const Key('profile-name')), 'Eusébio');
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    await tester.enterText(find.byKey(const Key('account-balance')), '100 000');
    await tapText(tester, 'Começar');
    expect(find.text('Olá, Eusébio'), findsOneWidget);
  }

  testWidgets('a tecla à esquerda do zero apaga os dígitos', (tester) async {
    await pumpApp(tester);
    for (final d in ['4', '8', '2']) {
      await tester.tap(find.widgetWithText(InkWell, d));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    // Se os 3 dígitos não tivessem sido apagados, ficaria 482482 (recusado).
    await typePin(tester, '482917');
    expect(find.text('Confirme o PIN'), findsOneWidget);
  });

  testWidgets('saída registada desconta o saldo; anular repõe-no', (tester) async {
    await setUpUser(tester);

    await tester.tap(find.text('Movimento'));
    await tester.pumpAndSettle();
    expect(find.text('Novo movimento'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('movement-amount')), '2 500');
    await tester.scrollUntilVisible(
      find.text('Alimentação'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tapText(tester, 'Alimentação');
    await tester.enterText(find.byKey(const Key('movement-description')), 'Mercado');
    await tapText(tester, 'Gravar');

    expect(data.ledger, hasLength(1));
    expect(data.ledger.single.amount, const Money(250000, Currency.aoa));
    expect(find.text('97\u00A0500,00\u00A0Kz'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Mercado'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mercado'), findsOneWidget);

    // Anular cria um estorno; nada é apagado. Desliza para tirar a linha
    // de baixo do botão flutuante.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mercado'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Anular');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();

    expect(data.ledger, hasLength(2));
    expect(data.ledger.last.reverses, data.ledger.first.id);
    expect(find.text('97\u00A0500,00\u00A0Kz'), findsNothing);
    expect(find.text('100\u00A0000,00\u00A0Kz'), findsWidgets);
  });

  testWidgets('compromisso: criar, pagar uma vez e descontar no saldo', (tester) async {
    await setUpUser(tester);

    await tester.tap(find.text('Planear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compromisso'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('commitment-description')), 'Renda');
    await tester.enterText(find.byKey(const Key('commitment-amount')), '30 000');
    await tapText(tester, 'Habitação');
    await tapText(tester, 'Guardar compromisso');

    expect(data.commitmentsById, hasLength(1));
    expect(data.ledger, isEmpty, reason: 'um compromisso não é um movimento');
    expect(find.text('Renda'), findsOneWidget);

    await tester.tap(find.text('Renda'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Marcar como pago');
    await tester.tap(find.text('Confirmar pagamento'));
    await tester.pumpAndSettle();

    expect(data.ledger, hasLength(1));
    expect(data.ledger.single.origin, MovementOrigin.commitment);
    expect(data.commitmentsById.values.single.status, CommitmentStatus.paid);
    expect(find.text('Marcar como pago'), findsNothing);

    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    expect(find.text('70\u00A0000,00\u00A0Kz'), findsWidgets);
  });

  testWidgets('relatório do mês abre a partir do cartão do fluxo', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.textContaining('FLUXO DE'));
    await tester.pumpAndSettle();
    expect(find.text('Relatórios'), findsOneWidget);
    expect(find.text('RESUMO · AOA'), findsOneWidget);
  });

  testWidgets('contas: corrigir o saldo inicial e apagar uma conta sem histórico', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();

    // Corrigir o saldo inicial (ainda sem movimentos).
    await tester.tap(find.text('Conta à ordem'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Editar ou corrigir saldo inicial');
    await tester.enterText(find.byKey(const Key('account-balance')), '150 000');
    await tapText(tester, 'Guardar alterações');
    expect(data.stored.single.openingBalance, const Money(15000000, Currency.aoa));

    // Uma segunda conta, criada por engano, pode ser apagada.
    await tester.tap(find.text('Nova conta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('account-name')), 'Carteira errada');
    await tapText(tester, 'Guardar conta');
    expect(data.stored, hasLength(2));
    await tester.tap(find.text('Carteira errada'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Apagar conta');
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();
    expect(data.stored, hasLength(1));
    expect(find.text('Carteira errada'), findsNothing);
  });

  testWidgets('perfil: alcunha muda a saudação', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-nickname')), 'EMBK');
    await tapText(tester, 'Guardar perfil');
    expect(data.profile?.nickname, 'EMBK');
    expect(data.profile?.name, 'Eusébio');
    expect(find.text('Olá, EMBK'), findsOneWidget);
  });

  testWidgets('orçamento global e objetivo com marco de 25%', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.text('Planear'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Orçamentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orçamento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-amount')), '50 000');
    await tapText(tester, 'Guardar orçamento');
    expect(data.budgetsById.values.single.isGlobal, isTrue);
    expect(find.text('Todas as despesas'), findsOneWidget);

    await tester.tap(find.text('Objetivos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Objetivo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal-name')), 'Viagem');
    await tester.enterText(find.byKey(const Key('goal-target')), '100 000');
    await tapText(tester, 'Guardar objetivo');
    expect(data.goalsById, hasLength(1));

    await tester.tap(find.text('Viagem'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Juntar');
    await tester.enterText(find.byType(TextField).last, '30 000');
    await tester.tap(find.text('Registar'));
    await tester.pumpAndSettle();
    expect(data.contributions.single.amount, const Money(3000000, Currency.aoa));
    expect(find.textContaining('25%'), findsWidgets);
  });

  testWidgets('compromisso mensal: pagar prepara o do mês seguinte', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.text('Planear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compromisso'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('commitment-description')), 'Internet');
    await tester.enterText(find.byKey(const Key('commitment-amount')), '15 000');
    await tester.tap(find.text('Não se repete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos os meses').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Despesas domésticas');
    await tapText(tester, 'Guardar compromisso');

    final first = data.commitmentsById.values.single;
    expect(first.recurrence, Recurrence.monthly);

    await tester.tap(find.text('Internet'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Marcar como pago');
    await tester.tap(find.text('Confirmar pagamento'));
    await tester.pumpAndSettle();

    expect(data.ledger, hasLength(1));
    final pending = data.commitmentsById.values.where((c) => c.status == CommitmentStatus.pending).toList();
    expect(pending, hasLength(1), reason: 'a próxima ocorrência fica pendente, nunca paga');
    expect(pending.single.dueDate, Recurrence.monthly.next(first.dueDate));
    expect(pending.single.seriesId, first.id);
  });

  testWidgets('Início mostra só o resumo do Planear; toque abre a secção', (tester) async {
    await setUpUser(tester);
    await tester.scrollUntilVisible(find.text('PLANEAR'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Nada pendente'), findsOneWidget);
    expect(find.text('Definir'), findsOneWidget);
    await tapText(tester, 'Kixikila');
    expect(find.textContaining('Acompanhe a sua Kixikila'), findsOneWidget);
  });

  testWidgets('Kixikila: criar grupo e registar contribuição', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.text('Planear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kixikila'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Kixikila'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('kixikila-name')), 'Família');
    await tester.enterText(find.byKey(const Key('kixikila-amount')), '10 000');
    await tester.enterText(find.byKey(const Key('kixikila-member-1')), 'Ana');
    await tapText(tester, 'Guardar Kixikila');
    expect(data.kixikilaById.values.single.payout, const Money(2000000, Currency.aoa));

    await tapText(tester, 'Registar contribuição');
    await tester.tap(find.text('Registar'));
    await tester.pumpAndSettle();
    expect(data.ledger.single.categoryId, 'exp.kixikila');
    expect(data.kixikilaLog.single.round, 0);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('importar pede consentimento antes de abrir ficheiros', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.text('Movimentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher ficheiro'));
    await tester.pumpAndSettle();
    expect(find.text('O FINTRACK quer aceder a ficheiros'), findsOneWidget);
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    expect(secrets.values.containsKey('ft.consent.files'), isFalse);
  });

  testWidgets('lembretes: ativar agenda os compromissos, sem valores', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.text('Planear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compromisso'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('commitment-description')), 'Renda');
    await tester.enterText(find.byKey(const Key('commitment-amount')), '45 000');
    await tapText(tester, 'Habitação');
    await tapText(tester, 'Guardar compromisso');

    await tester.tap(find.byTooltip('Definições'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Lembretes');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(secrets.values['ft.consent.notifications'], '1');
    expect(reminders.scheduled.map((r) => r.body), ['Renda vence amanhã.', 'Renda vence hoje.']);
    expect(reminders.scheduled.any((r) => r.body.contains('45')), isFalse);
  });

  testWidgets('conta na nuvem: criar, guardar o código e sincronizar cifrado', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.byTooltip('Definições'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Conta e sincronização');
    await tester.enterText(find.byKey(const Key('cloud-email')), 'eu@exemplo.ao');
    await tester.enterText(find.byKey(const Key('cloud-password')), 'Segura12345');
    await tester.enterText(find.byKey(const Key('cloud-confirm')), 'Segura12345');
    final submit = find.widgetWithText(FilledButton, 'Criar conta');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // O código aparece uma vez; é preciso confirmar o último grupo.
    final shown = tester.widget<SelectableText>(find.byKey(const Key('recovery-code'))).data!;
    final code = shown.replaceAll(' – ', '-');
    await tester.enterText(find.byKey(const Key('recovery-check')), 'XXXX');
    await tapText(tester, 'Guardei o código');
    expect(find.text('Não corresponde. Verifique o código.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('recovery-check')), code.split('-').last);
    await tapText(tester, 'Guardei o código');

    expect(find.text('eu@exemplo.ao'), findsOneWidget);
    final user = cloud.users['eu@exemplo.ao']!.$1;
    expect(cloud.vaults[user], isNotNull);
    final records = cloud.records[user]!;
    expect(records.keys, contains('account/${data.stored.single.id}'));
    expect(records.values.any((r) => r.payload.contains('Eusébio')), isFalse, reason: 'tudo cifrado');
    expect(data.settings['cloud.email'], 'eu@exemplo.ao');

    // Terminar sessão: os dados saem do telemóvel e abre o ecrã de entrada.
    final deviceId = data.settings['cloud.deviceId'];
    final signOut = find.byKey(const Key('cloud-signout'));
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar sessão'));
    await tester.pumpAndSettle();
    expect(find.text('Criar conta grátis'), findsOneWidget, reason: 'vitrine de entrada');
    expect(find.text('Olá, Eusébio'), findsNothing);
    expect(find.byTooltip('Definições'), findsNothing, reason: 'sem caminho de volta aos dados');
    expect(data.profile, isNull);
    expect(data.stored, isEmpty);
    expect(data.settings['cloud.email'], isNull);
    expect(data.settings['cloud.refresh'], isNull);
    expect(data.settings['cloud.deviceId'], deviceId, reason: 'continua o mesmo aparelho');

    // Entrar de novo traz os dados de volta.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final signIn = find.byKey(const Key('welcome-signin'));
    await tester.ensureVisible(signIn);
    await tester.pumpAndSettle();
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cloud-email')), 'eu@exemplo.ao');
    await tester.enterText(find.byKey(const Key('cloud-password')), 'Segura12345');
    final enter = find.widgetWithText(FilledButton, 'Entrar');
    await tester.ensureVisible(enter);
    await tester.pumpAndSettle();
    await tester.tap(enter);
    await tester.pumpAndSettle();
    expect(find.text('Olá, Eusébio'), findsOneWidget);
    expect(data.stored, hasLength(1));
  });

  testWidgets('ecrã de entrada permite começar sem conta', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.byTooltip('Definições'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Conta e sincronização');
    await tester.enterText(find.byKey(const Key('cloud-email')), 'eu@exemplo.ao');
    await tester.enterText(find.byKey(const Key('cloud-password')), 'Segura12345');
    await tester.enterText(find.byKey(const Key('cloud-confirm')), 'Segura12345');
    final submit = find.widgetWithText(FilledButton, 'Criar conta');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final shown = tester.widget<SelectableText>(find.byKey(const Key('recovery-code'))).data!;
    await tester.enterText(find.byKey(const Key('recovery-check')), shown.replaceAll(' – ', '-').split('-').last);
    await tapText(tester, 'Guardei o código');
    final signOut = find.byKey(const Key('cloud-signout'));
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar sessão'));
    await tester.pumpAndSettle();
    // Espera que o aviso desapareça (tapa o fundo do ecrã).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final without = find.byKey(const Key('start-without-account'));
    await tester.ensureVisible(without);
    await tester.pumpAndSettle();
    await tester.tap(without);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget, reason: 'onboarding de raiz');
  });

  testWidgets('conta com confirmação por código e entrada num telemóvel novo', (tester) async {
    cloud.confirmation = true;
    await setUpUser(tester);
    await tester.tap(find.byTooltip('Definições'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Conta e sincronização');
    await tester.enterText(find.byKey(const Key('cloud-email')), 'Eu@Exemplo.ao');
    await tester.enterText(find.byKey(const Key('cloud-password')), 'Segura12345');
    await tester.enterText(find.byKey(const Key('cloud-confirm')), 'Segura12345');
    final submit = find.widgetWithText(FilledButton, 'Criar conta');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // Código errado, depois o certo.
    expect(find.text('Código enviado por e-mail'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email-code')), '000000');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Código enviado por e-mail'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email-code')), '123456');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    final code = tester.widget<SelectableText>(find.byKey(const Key('recovery-code'))).data!.replaceAll(' – ', '-');
    await tester.enterText(find.byKey(const Key('recovery-check')), code.split('-').last);
    await tapText(tester, 'Guardei o código');
    final user = cloud.users['eu@exemplo.ao']!.$1;
    expect(cloud.deviceRows[user], hasLength(1), reason: 'este telemóvel registado');
    expect(find.textContaining('(este)'), findsOneWidget);

    // "Telemóvel novo": apagar tudo e entrar com a mesma conta pede código.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Apagar tudo e repor');
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar tudo'));
    await tester.pumpAndSettle();
    await typePin(tester, '482917');
    await typePin(tester, '482917');
    await tapText(tester, 'Já tenho conta FINTRACK');
    await tester.tap(find.text('Entrar').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cloud-email')), 'eu@exemplo.ao');
    await tester.enterText(find.byKey(const Key('cloud-password')), 'Segura12345');
    final enter = find.widgetWithText(FilledButton, 'Entrar');
    await tester.ensureVisible(enter);
    await tester.pumpAndSettle();
    await tester.tap(enter);
    await tester.pumpAndSettle();
    expect(find.text('Código enviado por e-mail'), findsOneWidget, reason: 'dispositivo novo');
    await tester.enterText(find.byKey(const Key('email-code')), '654321');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    // Os dados voltaram e o perfil abre o Início.
    expect(find.text('Olá, Eusébio'), findsOneWidget);
    expect(data.stored, hasLength(1));
    expect(cloud.deviceRows[user], hasLength(2));
  });

  testWidgets('FINTRACK AI: Smart Entry prepara, o utilizador revê e grava', (tester) async {
    await setUpUser(tester);
    await tester.tap(find.text('IA'));
    await tester.pumpAndSettle();
    expect(find.text('Nada a assinalar.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('smart-entry')), 'Gastei 12 500 Kz no Kero hoje');
    await tapText(tester, 'Preparar movimento');
    expect(find.text('Alimentação'), findsOneWidget);
    expect(data.ledger, isEmpty, reason: 'nada é gravado sem confirmação');

    await tapText(tester, 'Rever e gravar');
    expect(find.text('Rever movimento'), findsOneWidget);
    await tapText(tester, 'Gravar');
    expect(data.ledger.single.amount, const Money(1250000, Currency.aoa));
    expect(data.ledger.single.categoryId, 'exp.alimentacao');
    expect(data.ledger.single.origin, MovementOrigin.smartEntry);
  });

  testWidgets('biometria: ativar com PIN e desbloquear sem PIN', (tester) async {
    await setUpUser(tester);

    await tester.tap(find.byTooltip('Definições'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Desbloquear com biometria');
    expect(find.text('Confirme o PIN'), findsOneWidget);
    await typePin(tester, '482917');
    expect(find.text('Biometria ativada.'), findsOneWidget);
    expect(bio.stored, hasLength(32));

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bloquear'));
    await tester.pumpAndSettle();

    // O pedido de biometria abre sozinho e desbloqueia.
    expect(find.text('Olá, Eusébio'), findsOneWidget);

    // Biometria invalidada: volta ao PIN e desativa-se.
    await tester.tap(find.byTooltip('Bloquear'));
    bio.nextResult = const BiometricInvalidated();
    await tester.pumpAndSettle();
    expect(find.textContaining('deixou de ser válida'), findsOneWidget);
    await typePin(tester, '482917');
    expect(find.text('Olá, Eusébio'), findsOneWidget);
  });

  testWidgets('onboarding mostra a política de privacidade', (tester) async {
    await pumpApp(tester);
    await typePin(tester, '482917');
    await typePin(tester, '482917');
    await tapText(tester, 'Política de privacidade');
    expect(find.text('Política de Privacidade do FINTRACK'), findsOneWidget);
    expect(find.textContaining('apenas no seu telemóvel'), findsWidgets);
  });

  testWidgets('saldo inválido mostra erro e não grava', (tester) async {
    await pumpApp(tester);
    await typePin(tester, '482917');
    await typePin(tester, '482917');
    await tester.enterText(find.byKey(const Key('profile-name')), 'Rui');
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');

    await tester.enterText(find.byKey(const Key('account-balance')), '12,345');
    await tapText(tester, 'Começar');
    expect(find.textContaining('Valor inválido'), findsOneWidget);
    expect(data.profile, isNull);
  });
}
