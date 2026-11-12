import 'commitment.dart';
import 'ledger.dart';
import 'money.dart';
import 'names.dart';

/// Kixikila: poupança rotativa em grupo (secção 8A). Em cada ronda todos
/// contribuem e um membro recebe o total. Os outros membros são só nomes:
/// sem partilha de dados nem contas de terceiros.
class KixikilaGroup {
  KixikilaGroup({
    required this.id,
    required String name,
    required List<String> members,
    required this.contribution,
    required this.period,
    required DateTime startDate,
    required this.myTurn,
    required this.accountId,
    this.archived = false,
    required this.createdAt,
  })  : name = _name(name),
        members = List.unmodifiable([for (final m in members) _name(m)]),
        startDate = DateTime(startDate.year, startDate.month, startDate.day) {
    if (this.members.length < 2) throw ArgumentError('Uma Kixikila tem pelo menos 2 membros');
    if (myTurn < 0 || myTurn >= this.members.length) {
      throw ArgumentError.value(myTurn, 'myTurn', 'Posição fora do grupo');
    }
    if (contribution.minor <= 0) throw ArgumentError.value(contribution, 'contribution', 'Contribuição inválida');
    if (period != Recurrence.weekly && period != Recurrence.monthly) {
      throw ArgumentError.value(period, 'period', 'Periodicidade semanal ou mensal');
    }
  }

  static String _name(String n) {
    final clean = NameRules.clean(n);
    if (clean == null) throw ArgumentError.value(n, 'name', 'Nome inválido');
    return clean;
  }

  final String id;
  final String name;

  /// Membros pela ordem de recebimento (um deles é o utilizador).
  final List<String> members;
  final Money contribution;
  final Recurrence period;
  final DateTime startDate;

  /// Índice, em [members], da ronda em que o utilizador recebe.
  final int myTurn;

  /// Conta de onde sai a contribuição e onde entra o recebimento.
  final String accountId;
  final bool archived;
  final DateTime createdAt;

  int get rounds => members.length;

  /// Valor recebido na sua vez: todas as contribuições da ronda.
  Money get payout => Money(contribution.minor * members.length, contribution.currency);

  /// Data da ronda [round] (0 = primeira).
  DateTime roundDate(int round) {
    var d = startDate;
    for (var i = 0; i < round; i++) {
      d = period.next(d, anchorDay: startDate.day)!;
    }
    return d;
  }

  KixikilaGroup copyWith({bool? archived}) => KixikilaGroup(
        id: id,
        name: name,
        members: members,
        contribution: contribution,
        period: period,
        startDate: startDate,
        myTurn: myTurn,
        accountId: accountId,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

enum KixikilaRecordKind {
  contribution('contribution'),
  payout('payout');

  const KixikilaRecordKind(this.code);
  final String code;

  static KixikilaRecordKind fromCode(String code) => values.firstWhere((k) => k.code == code);
}

/// Liga uma ronda ao movimento que a registou no livro-razão.
class KixikilaRecord {
  const KixikilaRecord({
    required this.id,
    required this.groupId,
    required this.round,
    required this.kind,
    required this.movementId,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final int round;
  final KixikilaRecordKind kind;
  final String movementId;
  final DateTime createdAt;
}

class KixikilaStatus {
  const KixikilaStatus({
    required this.group,
    required this.paidRounds,
    required this.received,
    required this.nextContribution,
  });

  final KixikilaGroup group;

  /// Rondas cuja contribuição está registada (e não anulada).
  final Set<int> paidRounds;

  /// O recebimento da sua vez está registado.
  final bool received;

  /// Próxima ronda por pagar, ou `null` se já pagou todas.
  final int? nextContribution;

  DateTime get myPayoutDate => group.roundDate(group.myTurn);
  bool get finished => paidRounds.length == group.rounds && received;
}

class KixikilaEngine {
  static KixikilaStatus status(Ledger ledger, KixikilaGroup g, Iterable<KixikilaRecord> records) {
    bool active(KixikilaRecord r) {
      final m = ledger.byId(r.movementId);
      return m != null && !ledger.isReversed(m.id);
    }

    final paid = <int>{};
    var received = false;
    for (final r in records) {
      if (r.groupId != g.id || !active(r)) continue;
      if (r.kind == KixikilaRecordKind.contribution) paid.add(r.round);
      if (r.kind == KixikilaRecordKind.payout) received = true;
    }
    int? next;
    for (var k = 0; k < g.rounds; k++) {
      if (!paid.contains(k)) {
        next = k;
        break;
      }
    }
    return KixikilaStatus(group: g, paidRounds: paid, received: received, nextContribution: next);
  }
}
