import 'dart:typed_data';

import 'package:fintrack/data/local_store.dart';
import 'package:fintrack/main.dart';
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

  setUp(() {
    secrets = MemorySecretStore();
    data = MemoryLocalStore();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secretStoreProvider.overrideWithValue(secrets),
          pinVaultProvider.overrideWithValue(PinVault(secrets, deriver: fakeDerive)),
          localStoreFactoryProvider.overrideWithValue(data),
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
