import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  const nbsp = ' ';

  group('Money.parse', () {
    test('formato local com espaços e vírgula', () {
      expect(Money.parse('12 500,00', aoa).minor, 1250000);
      expect(Money.parse('1.234.567,89', aoa).minor, 123456789);
      expect(Money.parse('12500', aoa).minor, 1250000);
      expect(Money.parse('12,', aoa).minor, 1200);
      expect(Money.parse(',5', aoa).minor, 50);
    });

    test('ponto único: milhares com 3 algarismos, decimal com 1 ou 2', () {
      expect(Money.parse('12.500', aoa).minor, 1250000);
      expect(Money.parse('12.5', aoa).minor, 1250);
      expect(Money.parse('12.50', aoa).minor, 1250);
    });

    test('recusa valores inválidos em vez de arredondar', () {
      expect(() => Money.parse('12,345', aoa), throwsFormatException);
      expect(() => Money.parse('abc', aoa), throwsFormatException);
      expect(() => Money.parse('', aoa), throwsFormatException);
      expect(() => Money.parse('1,2,3', aoa), throwsFormatException);
    });
  });

  group('Money', () {
    test('formata como 1 234 567,89 Kz', () {
      expect(
        const Money(123456789, aoa).format(),
        '1${nbsp}234${nbsp}567,89${nbsp}Kz',
      );
      expect(const Money(1250000, aoa).format(withSymbol: false), '12${nbsp}500,00');
      expect(const Money(-50, aoa).format(), '-0,50${nbsp}Kz');
      expect(const Money.zero(aoa).format(), '0,00${nbsp}Kz');
    });

    test('soma em inteiros sem erro de arredondamento', () {
      expect(const Money(10, aoa) + const Money(20, aoa), const Money(30, aoa));
      expect(const Money(30, aoa) - const Money(50, aoa), const Money(-20, aoa));
    });

    test('nunca soma moedas diferentes', () {
      expect(
        () => const Money(100, aoa) + const Money(100, Currency.usd),
        throwsArgumentError,
      );
    });

    test('ida e volta: format seguido de parse devolve o mesmo valor', () {
      for (final minor in [0, 1, 99, 100, 1250000, 123456789, 999999999999]) {
        final m = Money(minor, aoa);
        expect(Money.parse(m.format(withSymbol: false), aoa), m);
      }
    });
  });

  group('PinPolicy', () {
    test('recusa PINs triviais', () {
      expect(PinPolicy.check('000000'), PinIssue.allSame);
      expect(PinPolicy.check('123456'), PinIssue.sequential);
      expect(PinPolicy.check('654321'), PinIssue.sequential);
      expect(PinPolicy.check('890123'), PinIssue.sequential);
      expect(PinPolicy.check('121212'), PinIssue.repeatedPattern);
      expect(PinPolicy.check('123123'), PinIssue.repeatedPattern);
      expect(PinPolicy.check('250390'), PinIssue.date);
      expect(PinPolicy.check('900325'), PinIssue.date);
    });

    test('recusa formato errado', () {
      expect(PinPolicy.check('12345'), PinIssue.length);
      expect(PinPolicy.check('12a456'), PinIssue.notDigits);
    });

    test('aceita PINs não triviais', () {
      expect(PinPolicy.check('482917'), isNull);
      expect(PinPolicy.isAcceptable('739158'), isTrue);
    });
  });

  group('LockoutPolicy', () {
    test('atrasos progressivos', () {
      expect(LockoutPolicy.delayAfter(0), Duration.zero);
      expect(LockoutPolicy.delayAfter(2), Duration.zero);
      expect(LockoutPolicy.delayAfter(3), const Duration(seconds: 30));
      expect(LockoutPolicy.delayAfter(9), const Duration(hours: 1));
    });

    test('10 falhas exigem novo início de sessão', () {
      expect(LockoutPolicy.requiresAccountSignIn(9), isFalse);
      expect(LockoutPolicy.requiresAccountSignIn(10), isTrue);
    });
  });

  test('moedas suportadas', () {
    expect(Currency.fromCode('aoa'), Currency.aoa);
    expect(() => Currency.fromCode('XXX'), throwsArgumentError);
  });
}
