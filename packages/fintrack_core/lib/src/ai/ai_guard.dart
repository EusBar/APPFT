import '../commitment.dart';
import '../ledger.dart';
import '../money.dart';
import '../movement.dart';

enum GuardKind { duplicate, unusualAmount, availableNegative }

/// Um sinal para verificar — nunca uma acusação de fraude (secção 13).
class GuardAlert {
  const GuardAlert({
    required this.id,
    required this.kind,
    required this.priority,
    this.movementId,
    this.otherMovementId,
    this.amount,
    this.typical,
    this.categoryId,
  });

  /// Estável entre execuções, para o utilizador poder dispensar o alerta.
  final String id;
  final GuardKind kind;

  /// 1 = baixa, 2 = média, 3 = alta.
  final int priority;
  final String? movementId;
  final String? otherMovementId;
  final Money? amount;

  /// Valor habitual na categoria (mediana), para comparação.
  final Money? typical;
  final String? categoryId;
}

/// AI Guard básico, local e gratuito: regras e estatística simples sobre o
/// livro-razão. Corre no telemóvel, sem Internet.
class AiGuard {
  static const _window = Duration(days: 45);

  static List<GuardAlert> scan(
    Ledger ledger, {
    required DateTime today,
    Set<String> dismissed = const {},
  }) {
    final alerts = <GuardAlert>[];
    final t = DateTime(today.year, today.month, today.day);
    final active = ledger.active();
    final recent = [for (final m in active) if (!m.date.isBefore(t.subtract(_window))) m];

    // 1. Possíveis duplicados: mesma conta, tipo, valor e dia.
    final seen = <String, Movement>{};
    for (final m in [...recent]..sort((a, b) => a.createdAt.compareTo(b.createdAt))) {
      final key = '${m.kind.code}|${m.accountId}|${m.toAccountId}|${m.amount.minor}|${m.amount.currency.code}|${m.date}';
      final first = seen[key];
      if (first != null) {
        alerts.add(GuardAlert(
          id: 'dup:${first.id}:${m.id}',
          kind: GuardKind.duplicate,
          priority: 2,
          movementId: m.id,
          otherMovementId: first.id,
          amount: m.amount,
        ));
      } else {
        seen[key] = m;
      }
    }

    // 2. Valores fora do padrão da categoria (mediana e desvio absoluto).
    final byCategory = <String, List<int>>{};
    for (final m in active) {
      if (m.kind != MovementKind.expense || m.categoryId == null) continue;
      (byCategory['${m.categoryId}|${m.amount.currency.code}'] ??= []).add(m.amount.minor);
    }
    for (final m in recent) {
      if (m.kind != MovementKind.expense || m.categoryId == null) continue;
      final history = [...?byCategory['${m.categoryId}|${m.amount.currency.code}']]..remove(m.amount.minor);
      if (history.length < 5) continue; // poucos dados: não julga
      history.sort();
      final median = history[history.length ~/ 2];
      final deviations = [for (final h in history) (h - median).abs()]..sort();
      final mad = deviations[deviations.length ~/ 2];
      final threshold = [median * 3, median + mad * 6].reduce((a, b) => a > b ? a : b);
      if (median > 0 && m.amount.minor > threshold) {
        alerts.add(GuardAlert(
          id: 'big:${m.id}',
          kind: GuardKind.unusualAmount,
          priority: m.amount.minor > median * 6 ? 3 : 2,
          movementId: m.id,
          amount: m.amount,
          typical: Money(median, m.amount.currency),
          categoryId: m.categoryId,
        ));
      }
    }

    // 3. Risco de saldo disponível negativo até ao fim do mês.
    ledger.available(today: t, horizon: AvailableHorizon.endOfMonth).forEach((currency, value) {
      if (value.isNegative) {
        alerts.add(GuardAlert(
          id: 'neg:${currency.code}:${t.year}-${t.month}',
          kind: GuardKind.availableNegative,
          priority: 3,
          amount: value,
        ));
      }
    });

    alerts.removeWhere((a) => dismissed.contains(a.id));
    alerts.sort((a, b) => b.priority.compareTo(a.priority));
    return alerts;
  }
}
