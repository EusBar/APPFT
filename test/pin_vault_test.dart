import 'package:fintrack/security/pin_vault.dart';
import 'package:fintrack/security/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Parâmetros leves para os testes serem rápidos; o caminho é o real
  // (Argon2id num isolate + AES-256-GCM).
  const fast = Argon2Params(memoryKiB: 64, iterations: 1, parallelism: 1);
  const pin = '482917';
  const wrong = '482918';

  late MemorySecretStore store;
  late DateTime now;
  late PinVault vault;

  setUp(() {
    store = MemorySecretStore();
    now = DateTime(2026, 11, 11, 22, 0);
    vault = PinVault(store, params: fast, now: () => now);
  });

  test('cria o PIN e desbloqueia com a mesma chave de dados', () async {
    expect(await vault.hasPin(), isFalse);
    final key = await vault.createPin(pin);
    expect(key, hasLength(32));
    expect(await vault.hasPin(), isTrue);

    final result = await vault.unlock(pin);
    expect(result, isA<UnlockSuccess>());
    expect((result as UnlockSuccess).dataKey, key);
  });

  test('o PIN nunca fica guardado em texto simples', () async {
    await vault.createPin(pin);
    for (final value in store.values.values) {
      expect(value.contains(pin), isFalse);
    }
  });

  test('recusa PIN trivial e segundo PIN', () async {
    expect(() => vault.createPin('123456'), throwsArgumentError);
    await vault.createPin(pin);
    expect(() => vault.createPin('739158'), throwsStateError);
  });

  test('atraso progressivo à terceira falha', () async {
    await vault.createPin(pin);

    final first = await vault.unlock(wrong) as UnlockWrongPin;
    expect(first.failures, 1);
    expect(first.wait, Duration.zero);
    await vault.unlock(wrong);

    final third = await vault.unlock(wrong) as UnlockWrongPin;
    expect(third.failures, 3);
    expect(third.wait, const Duration(seconds: 30));

    // Durante a espera nem o PIN certo entra.
    expect(await vault.unlock(pin), isA<UnlockThrottled>());

    now = now.add(const Duration(seconds: 31));
    expect(await vault.unlock(pin), isA<UnlockSuccess>());
    expect((await vault.status()).failures, 0);
  });

  test('10 falhas bloqueiam de vez até repor', () async {
    await vault.createPin(pin);
    UnlockResult? last;
    for (var i = 0; i < 10; i++) {
      last = await vault.unlock(wrong);
      now = now.add(const Duration(hours: 2));
    }
    expect(last, isA<UnlockSignInRequired>());
    expect(await vault.unlock(pin), isA<UnlockSignInRequired>());

    await vault.reset();
    expect(await vault.hasPin(), isFalse);
    expect(store.values, isEmpty);
  });

  test('recuar o relógio não prolonga a espera além do previsto', () async {
    await vault.createPin(pin);
    for (var i = 0; i < 3; i++) {
      await vault.unlock(wrong);
    }
    now = now.subtract(const Duration(days: 1));
    expect((await vault.status()).remaining, const Duration(seconds: 30));
  });
}
