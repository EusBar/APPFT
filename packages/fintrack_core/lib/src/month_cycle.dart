/// Um mês financeiro: do dia [from] ao dia [to] (ambos incluídos), com o nome
/// do mês civil a que pertence ([year]/[month]).
class FinancialMonth {
  const FinancialMonth({required this.year, required this.month, required this.from, required this.to});

  final int year;
  final int month;
  final DateTime from;
  final DateTime to;

  int get days => to.difference(from).inDays + 1;

  /// O mês financeiro anterior / seguinte.
  FinancialMonth previous(MonthCycle cycle) => cycle.byLabel(year, month - 1);
  FinancialMonth next(MonthCycle cycle) => cycle.byLabel(year, month + 1);

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  @override
  bool operator ==(Object other) => other is FinancialMonth && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Como se divide o tempo em meses financeiros.
///
/// * [startDay] 1: mês de calendário (dia 1 ao último dia).
/// * [startDay] 2 a 28: começa nesse dia (ex.: dia do salário) e acaba na
///   véspera do mesmo dia do mês seguinte.
///
/// Os períodos são contínuos e nunca se sobrepõem: cada dia pertence a um único
/// mês. Cada período tem o nome do mês civil onde caem mais dias: de 25 out a
/// 24 nov é "novembro"; de 10 nov a 9 dez é "novembro".
class MonthCycle {
  const MonthCycle([int startDay = 1]) : startDay = startDay < 1 ? 1 : (startDay > 28 ? 28 : startDay);

  final int startDay;

  static const calendar = MonthCycle();

  bool get isCalendar => startDay == 1;

  /// Período com o nome [year]/[month] (aceita meses fora de 1..12).
  FinancialMonth byLabel(int year, int month) {
    final label = DateTime(year, month);
    if (isCalendar) {
      return FinancialMonth(
        year: label.year,
        month: label.month,
        from: label,
        to: DateTime(label.year, label.month + 1, 0),
      );
    }
    // Começo no fim do mês anterior quando a maior parte dos dias cai no mês
    // seguinte (dia de início depois de 15).
    final start = startDay > 15
        ? DateTime(label.year, label.month - 1, startDay)
        : DateTime(label.year, label.month, startDay);
    final end = DateTime(start.year, start.month + 1, startDay - 1);
    return FinancialMonth(year: label.year, month: label.month, from: start, to: end);
  }

  /// Período que contém [day].
  FinancialMonth of(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (isCalendar) return byLabel(d.year, d.month);
    // O dia pertence ao período que começa no último "dia de início" <= d.
    final start = d.day >= startDay ? DateTime(d.year, d.month, startDay) : DateTime(d.year, d.month - 1, startDay);
    final label = startDay > 15 ? DateTime(start.year, start.month + 1) : DateTime(start.year, start.month);
    return byLabel(label.year, label.month);
  }

  /// Os últimos [count] períodos até ao que contém [today], do mais recente
  /// para o mais antigo.
  List<FinancialMonth> recent(DateTime today, {int count = 12}) {
    final current = of(today);
    return [for (var i = 0; i < count; i++) byLabel(current.year, current.month - i)];
  }
}
