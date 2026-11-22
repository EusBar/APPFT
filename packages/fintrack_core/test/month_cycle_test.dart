import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  test('mês de calendário', () {
    const c = MonthCycle.calendar;
    final m = c.of(DateTime(2026, 11, 22));
    expect([m.year, m.month], [2026, 11]);
    expect(m.from, DateTime(2026, 11, 1));
    expect(m.to, DateTime(2026, 11, 30));
    expect(c.byLabel(2027, 2).to, DateTime(2027, 2, 28));
  });

  test('de salário a salário (dia 25): 25 out a 24 nov chama-se novembro', () {
    const c = MonthCycle(25);
    final nov = c.byLabel(2026, 11);
    expect(nov.from, DateTime(2026, 10, 25));
    expect(nov.to, DateTime(2026, 11, 24));
    expect(c.of(DateTime(2026, 11, 22)), nov);
    expect(c.of(DateTime(2026, 11, 25)).month, 12);
    expect(c.of(DateTime(2026, 10, 25)).month, 11);
    expect(c.of(DateTime(2026, 10, 24)).month, 10);
  });

  test('início cedo (dia 10): 10 nov a 9 dez chama-se novembro', () {
    const c = MonthCycle(10);
    final nov = c.byLabel(2026, 11);
    expect(nov.from, DateTime(2026, 11, 10));
    expect(nov.to, DateTime(2026, 12, 9));
    expect(c.of(DateTime(2026, 12, 9)), nov);
    expect(c.of(DateTime(2026, 11, 9)).month, 10);
  });

  test('períodos contínuos, sem buracos nem sobreposições, em dois anos', () {
    for (final day in [1, 2, 10, 15, 16, 25, 28]) {
      final c = MonthCycle(day);
      var p = c.byLabel(2026, 1);
      for (var i = 0; i < 24; i++) {
        final n = p.next(c);
        expect(n.from, p.to.add(const Duration(days: 1)), reason: 'dia $day, ${p.month}/${p.year}');
        p = n;
      }
    }
    // Viragem de ano: dezembro com início a 25 vai de 25 nov a 24 dez.
    final dez = const MonthCycle(25).byLabel(2026, 12);
    expect(dez.from, DateTime(2026, 11, 25));
    expect(const MonthCycle(25).byLabel(2027, 1).from, DateTime(2026, 12, 25));
  });

  test('valores fora do intervalo ficam entre 1 e 28', () {
    expect(const MonthCycle(31).startDay, 28);
    expect(const MonthCycle(0).isCalendar, isTrue);
  });

  test('últimos meses, do mais recente para o mais antigo', () {
    final list = const MonthCycle(25).recent(DateTime(2026, 11, 22), count: 3);
    expect([for (final m in list) m.month], [11, 10, 9]);
  });
}
