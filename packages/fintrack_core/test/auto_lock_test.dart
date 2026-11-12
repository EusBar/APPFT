import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 11, 11, 22, 0);

  bool lock(Duration elapsed, AutoLockSetting s) => AutoLockPolicy.shouldLock(
        backgroundedAt: t0,
        now: t0.add(elapsed),
        setting: s,
      );

  test('imediato bloqueia sempre', () {
    expect(lock(Duration.zero, AutoLockSetting.immediate), isTrue);
  });

  test('respeita o tempo configurado', () {
    expect(lock(const Duration(seconds: 59), AutoLockSetting.oneMinute), isFalse);
    expect(lock(const Duration(minutes: 1), AutoLockSetting.oneMinute), isTrue);
    expect(lock(const Duration(minutes: 14), AutoLockSetting.fifteenMinutes), isFalse);
    expect(lock(const Duration(minutes: 15), AutoLockSetting.fifteenMinutes), isTrue);
  });

  test('relógio a andar para trás bloqueia', () {
    expect(lock(const Duration(minutes: -5), AutoLockSetting.fifteenMinutes), isTrue);
  });
}
