import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final day = DateTime(2026, 11, 12, 15, 30);

  Account account(
    AccountType type,
    int minor, {
    Currency currency = aoa,
    bool archived = false,
  }) =>
      Account(
        id: newId(),
        type: type,
        name: 'Conta',
        openingBalance: Money(minor, currency),
        startDate: day,
        archived: archived,
      );

  group('NameRules', () {
    test('limpa espaços e recusa vazio ou longo', () {
      expect(NameRules.clean('  Ana   Maria '), 'Ana Maria');
      expect(NameRules.clean('   '), isNull);
      expect(NameRules.clean('a' * 41), isNull);
      expect(NameRules.clean('a' * 40), 'a' * 40);
    });
  });

  group('Account', () {
    test('poupança fica fora do saldo disponível por defeito', () {
      expect(account(AccountType.savings, 0).includeInAvailable, isFalse);
      expect(account(AccountType.cash, 0).includeInAvailable, isTrue);
    });

    test('guarda só a data de início', () {
      expect(account(AccountType.bank, 0).startDate, DateTime(2026, 11, 12));
    });

    test('recusa nome vazio e limpa instituição vazia', () {
      expect(
        () => Account(
          id: '1',
          type: AccountType.bank,
          name: ' ',
          openingBalance: const Money.zero(aoa),
          startDate: day,
        ),
        throwsArgumentError,
      );
      final a = Account(
        id: '1',
        type: AccountType.bank,
        name: 'Ordenado',
        institution: '  ',
        openingBalance: const Money.zero(aoa),
        startDate: day,
      );
      expect(a.institution, isNull);
    });

    test('códigos de tipo são estáveis', () {
      for (final t in AccountType.values) {
        expect(AccountType.fromCode(t.code), t);
      }
      expect(() => AccountType.fromCode('x'), throwsArgumentError);
    });
  });

  group('Balances', () {
    test('soma por moeda sem misturar', () {
      final totals = Balances.byCurrency([
        account(AccountType.bank, 1000),
        account(AccountType.cash, 500),
        account(AccountType.bank, 700, currency: Currency.usd),
      ]);
      expect(totals[aoa], const Money(1500, aoa));
      expect(totals[Currency.usd], const Money(700, Currency.usd));
    });

    test('disponível exclui poupança e arquivadas', () {
      final totals = Balances.byCurrency([
        account(AccountType.bank, 1000),
        account(AccountType.savings, 9000),
        account(AccountType.cash, 300, archived: true),
      ], availableOnly: true);
      expect(totals[aoa], const Money(1000, aoa));
    });
  });

  test('newId gera UUID v4 diferentes', () {
    final a = newId();
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(a),
      isTrue,
    );
    expect(newId(), isNot(a));
  });
}
