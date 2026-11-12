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
  final DateTime createdAt;

  /// Volta a pendente (ex.: o pagamento foi anulado no livro-razão).
  Commitment asPending() => Commitment(
        id: id,
        accountId: accountId,
        amount: amount,
        categoryId: categoryId,
        description: description,
        note: note,
        dueDate: dueDate,
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
