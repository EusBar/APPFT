import 'money.dart';
import 'names.dart';

/// Tipos de movimento (secção 6). Compromissos chegam numa fase seguinte.
enum MovementKind {
  income('income'),
  expense('expense'),

  /// Transferência entre contas próprias: não é rendimento nem despesa.
  transfer('transfer');

  const MovementKind(this.code);
  final String code;

  static MovementKind fromCode(String code) => values.firstWhere(
        (k) => k.code == code,
        orElse: () => throw ArgumentError.value(code, 'code', 'Tipo desconhecido'),
      );
}

/// De onde veio o registo.
enum MovementOrigin {
  manual('manual'),
  import('import'),
  recurring('recurring'),
  smartEntry('smart_entry'),

  /// Saída gerada ao pagar um compromisso.
  commitment('commitment'),
  ai('ai');

  const MovementOrigin(this.code);
  final String code;

  static MovementOrigin fromCode(String code) => values.firstWhere(
        (o) => o.code == code,
        orElse: () => throw ArgumentError.value(code, 'code', 'Origem desconhecida'),
      );
}

/// Registo do livro-razão. Nunca se altera nem se apaga depois de gravado:
/// corrige-se com um estorno ([reverses]) e, se for o caso, um registo novo
/// que o substitui ([replaces]).
class Movement {
  Movement({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.amount,
    this.toAccountId,
    this.toAmount,
    this.categoryId,
    String description = '',
    String note = '',
    required DateTime date,
    this.origin = MovementOrigin.manual,
    this.reverses,
    this.replaces,
    this.batchId,
    required this.createdAt,
  })  : description = description.trim().replaceAll(RegExp(r'\s+'), ' '),
        note = note.trim(),
        date = DateTime(date.year, date.month, date.day) {
    if (amount.minor <= 0) {
      throw ArgumentError.value(amount, 'amount', 'O valor tem de ser positivo');
    }
    if (this.description.length > descriptionMaxLength) {
      throw ArgumentError.value(description, 'description', 'Descrição longa demais');
    }
    if (this.note.length > noteMaxLength) {
      throw ArgumentError.value(note, 'note', 'Observação longa demais');
    }
    if (kind == MovementKind.transfer) {
      if (toAccountId == null || toAmount == null) {
        throw ArgumentError('Transferência sem conta ou valor de destino');
      }
      if (toAccountId == accountId) {
        throw ArgumentError('Transferência para a mesma conta');
      }
      if (toAmount!.minor <= 0) {
        throw ArgumentError.value(toAmount, 'toAmount', 'O valor tem de ser positivo');
      }
      if (categoryId != null) {
        throw ArgumentError('Transferências não têm categoria');
      }
    } else {
      if (toAccountId != null || toAmount != null) {
        throw ArgumentError('Só transferências têm conta de destino');
      }
      if (categoryId == null) throw ArgumentError('Falta a categoria');
    }
    if (reverses != null && replaces != null) {
      throw ArgumentError('Um estorno não substitui outro registo');
    }
  }

  static const descriptionMaxLength = NameRules.maxLength * 2;
  static const noteMaxLength = 500;

  final String id;
  final MovementKind kind;

  /// Conta de destino (entrada) ou de origem (saída, transferência).
  final String accountId;
  final Money amount;

  /// Só transferências: conta e valor recebido (pode ser outra moeda).
  final String? toAccountId;
  final Money? toAmount;

  final String? categoryId;
  final String description;
  final String note;
  final DateTime date;
  final MovementOrigin origin;

  /// Se preenchido, este registo é o estorno de [reverses].
  final String? reverses;

  /// Se preenchido, este registo corrige [replaces] (que foi estornado).
  final String? replaces;

  /// Lote de importação que criou este registo (para anular a importação).
  final String? batchId;
  final DateTime createdAt;

  bool get isReversal => reverses != null;

  /// Estorno deste movimento: os mesmos valores com efeito contrário.
  Movement reversal({required String id, required DateTime createdAt}) {
    if (isReversal) throw StateError('Não se estorna um estorno');
    return Movement(
      id: id,
      kind: kind,
      accountId: accountId,
      amount: amount,
      toAccountId: toAccountId,
      toAmount: toAmount,
      categoryId: categoryId,
      description: description,
      date: date,
      origin: origin,
      reverses: this.id,
      batchId: batchId,
      createdAt: createdAt,
    );
  }

  /// Efeito no saldo de [account], em unidades mínimas da moeda dessa conta.
  int effectOn(String account) {
    final sign = isReversal ? -1 : 1;
    var e = 0;
    switch (kind) {
      case MovementKind.income:
        if (accountId == account) e += amount.minor;
      case MovementKind.expense:
        if (accountId == account) e -= amount.minor;
      case MovementKind.transfer:
        if (accountId == account) e -= amount.minor;
        if (toAccountId == account) e += toAmount!.minor;
    }
    return sign * e;
  }
}
