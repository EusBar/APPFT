import 'package:fintrack/main.dart';
import 'package:fintrack/security/secret_store.dart';
import 'package:fintrack/security/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
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
}
