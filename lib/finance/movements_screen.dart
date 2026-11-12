import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../reports/report_screen.dart';
import 'finance_data.dart';
import 'movement_tile.dart';

/// Histórico com pesquisa e filtros; funciona offline, sobre a base local.
class MovementsView extends StatefulWidget {
  const MovementsView({super.key, required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  State<MovementsView> createState() => _MovementsViewState();
}

class _MovementsViewState extends State<MovementsView> {
  final _search = TextEditingController();
  MovementKind? _kind;
  bool _showCancelled = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Movement m, String q) {
    if (q.isEmpty) return true;
    final d = widget.data;
    final haystack = [
      m.description,
      m.note,
      d.category(m.categoryId)?.name ?? '',
      d.account(m.accountId)?.name ?? '',
      d.account(m.toAccountId)?.name ?? '',
      m.amount.format(withSymbol: false),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = widget.data.ledger;
    final q = _search.text.trim().toLowerCase();

    final source = _showCancelled
        ? ([
            for (final m in ledger.movements)
              if (!m.isReversal) m,
          ]..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
          }))
        : ledger.active();
    final list = [
      for (final m in source)
        if ((_kind == null || m.kind == _kind) && _matches(m, q)) m,
    ];

    final children = <Widget>[];
    DateTime? lastDay;
    for (final m in list) {
      if (m.date != lastDay) {
        lastDay = m.date;
        children.add(Padding(
          padding: const EdgeInsets.only(top: FtSpace.md, bottom: FtSpace.xs),
          child: Text(
            dayLabel(m.date),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ));
      }
      children.add(MovementTile(
        movement: m,
        data: widget.data,
        discreet: widget.discreet,
        cancelled: ledger.isReversed(m.id),
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.insights_outlined, size: 18),
            label: const Text('Relatórios e exportação'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReportScreen()),
            ),
          ),
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Pesquisar descrição, categoria, conta ou valor',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar pesquisa',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_search.clear),
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: FtSpace.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final k in [null, ...MovementKind.values])
                Padding(
                  padding: const EdgeInsets.only(right: FtSpace.sm),
                  child: ChoiceChip(
                    label: Text(k == null ? 'Todos' : movementKindLabel(k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
                ),
              FilterChip(
                label: const Text('Anulados'),
                selected: _showCancelled,
                onSelected: (v) => setState(() => _showCancelled = v),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FtSpace.xl),
            child: Text(
              ledger.movements.isEmpty
                  ? 'Ainda não há movimentos. Registe o primeiro no botão "Movimento".'
                  : 'Nenhum movimento corresponde à pesquisa.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...children,
      ],
    );
  }
}
