import 'money.dart';

/// Estado de um compromisso (secção 6).
enum CommitmentStatus {
  pending('pending'),
  paid('paid'),
  cancelled('cancelled');

  const CommitmentStatus(this.code);
  final String code;

  static CommitmentStatus fromCode(String code) => values.firstWhere(
        (s) => s.code == code,
        orElse: () => throw ArgumentError.value(code, 'code', 'Estado desconhecido'),
      );
}

/// Repetição de um compromisso (secção 6: movimentos recorrentes).
enum Recurrence {
  none('none'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const Recurrence(this.code);
  final String code;

  static Recurrence fromCode(String? code) =>
      values.firstWhere((r) => r.code == code, orElse: () => Recurrence.none);

  /// Próxima data a partir de [from]. Nos meses curtos, o dia 31 passa a ser
  /// o último dia do mês; [anchorDay] mantém o dia original da série.
  DateTime? next(DateTime from, {int? anchorDay}) {
    final day = anchorDay ?? from.day;
    DateTime clamp(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, day > last ? last : day);
    }

    return switch (this) {
      Recurrence.none => null,
      Recurrence.weekly => DateTime(from.year, from.month, from.day + 7),
      Recurrence.monthly => clamp(from.year, from.month + 1),
      Recurrence.yearly => clamp(from.year + 1, from.month),
    };
  }
}

/// Pagamento previsto: reduz o saldo disponível, não o contabilístico.
/// Ao ser pago gera uma saída ligada ([paidMovementId]) e deixa de contar
/// como pendente: nunca é descontado duas vezes.
class Commitment {
  Commitment({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.categoryId,
    String description = '',
    String note = '',
    required DateTime dueDate,
    this.status = CommitmentStatus.pending,
    this.paidMovementId,
    this.recurrence = Recurrence.none,
    this.seriesId,
    this.anchorDay,
    required this.createdAt,
  })  : description = description.trim().replaceAll(RegExp(r'\s+'), ' '),
        note = note.trim(),
        dueDate = DateTime(dueDate.year, dueDate.month, dueDate.day) {
    if (amount.minor <= 0) {
      throw ArgumentError.value(amount, 'amount', 'O valor tem de ser positivo');
    }
    if (this.description.isEmpty) {
      throw ArgumentError.value(description, 'description', 'Falta a descrição');
    }
    if (this.description.length > 80) {
      throw ArgumentError.value(description, 'description', 'Descrição longa demais');
    }
    if ((status == CommitmentStatus.paid) != (paidMovementId != null)) {
      throw ArgumentError('Um compromisso pago tem de apontar para a saída que o pagou');
    }
  }

  final String id;
  final String accountId;
  final Money amount;
  final String categoryId;
  final String description;
  final String note;
  final DateTime dueDate;
  final CommitmentStatus status;
  final String? paidMovementId;
  final Recurrence recurrence;

  /// Identifica a série de um compromisso recorrente.
  final String? seriesId;

  /// Dia do mês original da série (ex.: 31), para não "encolher" depois de
  /// fevereiro.
  final int? anchorDay;
  final DateTime createdAt;

  /// Próxima ocorrência de uma série, pendente, com novo [id].
  Commitment? nextOccurrence({required String id, required DateTime createdAt}) {
    final due = recurrence.next(dueDate, anchorDay: anchorDay ?? dueDate.day);
    if (due == null) return null;
    return Commitment(
      id: id,
      accountId: accountId,
      amount: amount,
      categoryId: categoryId,
      description: description,
      note: note,
      dueDate: due,
      recurrence: recurrence,
      seriesId: seriesId ?? this.id,
      anchorDay: anchorDay ?? dueDate.day,
      createdAt: createdAt,
    );
  }

  /// Volta a pendente (ex.: o pagamento foi anulado no livro-razão).
  Commitment asPending() => Commitment(
        id: id,
        accountId: accountId,
        amount: amount,
        categoryId: categoryId,
        description: description,
        note: note,
        dueDate: dueDate,
        recurrence: recurrence,
        seriesId: seriesId,
        anchorDay: anchorDay,
        createdAt: createdAt,
      );

  Commitment copyWith({
    String? accountId,
    Money? amount,
    String? categoryId,
    String? description,
    String? note,
    DateTime? dueDate,
    CommitmentStatus? status,
    String? paidMovementId,
    Recurrence? recurrence,
  }) =>
      Commitment(
        id: id,
        accountId: accountId ?? this.accountId,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        description: description ?? this.description,
        note: note ?? this.note,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        paidMovementId: paidMovementId ?? this.paidMovementId,
        recurrence: recurrence ?? this.recurrence,
        seriesId: seriesId,
        anchorDay: anchorDay,
        createdAt: createdAt,
      );
}

/// Até quando os compromissos pendentes reduzem o saldo disponível.
enum AvailableHorizon {
  endOfMonth('end_of_month'),
  days7('days_7'),
  days30('days_30'),
  days90('days_90');

  const AvailableHorizon(this.code);
  final String code;

  static AvailableHorizon fromCode(String? code) => values.firstWhere(
        (h) => h.code == code,
        orElse: () => AvailableHorizon.endOfMonth,
      );

  /// Último dia (incluído) do horizonte a contar de [today].
  DateTime end(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    return switch (this) {
      AvailableHorizon.endOfMonth => DateTime(t.year, t.month + 1, 0),
      AvailableHorizon.days7 => DateTime(t.year, t.month, t.day + 7),
      AvailableHorizon.days30 => DateTime(t.year, t.month, t.day + 30),
      AvailableHorizon.days90 => DateTime(t.year, t.month, t.day + 90),
    };
  }
}
