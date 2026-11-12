import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../importing/import_screen.dart';
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

enum _Period { all, thisMonth, lastMonth, last90, thisYear, custom }

String _periodLabel(_Period p) => switch (p) {
      _Period.all => 'Sempre',
      _Period.thisMonth => 'Este mês',
      _Period.lastMonth => 'Mês passado',
      _Period.last90 => 'Últimos 90 dias',
      _Period.thisYear => 'Este ano',
      _Period.custom => 'Personalizado',
    };

class _MovementsViewState extends State<MovementsView> {
  final _search = TextEditingController();
  MovementKind? _kind;
  bool _showCancelled = false;
  _Period _period = _Period.all;
  DateTimeRange? _range;
  String? _accountFilter;
  String? _categoryFilter;
  int? _minMinor;
  int? _maxMinor;

  int get _activeFilters =>
      (_period != _Period.all ? 1 : 0) +
      (_accountFilter != null ? 1 : 0) +
      (_categoryFilter != null ? 1 : 0) +
      (_minMinor != null || _maxMinor != null ? 1 : 0);

  (DateTime, DateTime)? _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.all => null,
      _Period.thisMonth => (DateTime(now.year, now.month), today),
      _Period.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month, 0)),
      _Period.last90 => (today.subtract(const Duration(days: 89)), today),
      _Period.thisYear => (DateTime(now.year), today),
      _Period.custom => _range == null ? null : (_range!.start, _range!.end),
    };
  }

  bool _passesFilters(Movement m) {
    final b = _bounds();
    if (b != null && (m.date.isBefore(b.$1) || m.date.isAfter(b.$2))) return false;
    if (_accountFilter != null && m.accountId != _accountFilter && m.toAccountId != _accountFilter) {
      return false;
    }
    if (_categoryFilter != null && m.categoryId != _categoryFilter) return false;
    if (_minMinor != null && m.amount.minor < _minMinor!) return false;
    if (_maxMinor != null && m.amount.minor > _maxMinor!) return false;
    return true;
  }

  Future<void> _openFilters() async {
    final data = widget.data;
    var period = _period;
    var range = _range;
    var account = _accountFilter;
    var category = _categoryFilter;
    final min = TextEditingController(
      text: _minMinor == null ? '' : MovementCsv.plain(Money(_minMinor!, Currency.aoa)),
    );
    final max = TextEditingController(
      text: _maxMinor == null ? '' : MovementCsv.plain(Money(_maxMinor!, Currency.aoa)),
    );
    int? parse(String text) {
      if (text.trim().isEmpty) return null;
      try {
        return Money.parse(text, Currency.aoa).minor.abs();
      } on FormatException {
        return null;
      }
    }

    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
            children: [
              Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: FtSpace.md),
              Wrap(
                spacing: FtSpace.sm,
                runSpacing: FtSpace.sm,
                children: [
                  for (final p in _Period.values)
                    ChoiceChip(
                      label: Text(p == _Period.custom && range != null
                          ? '${shortDate(range!.start)} – ${shortDate(range!.end)}'
                          : _periodLabel(p)),
                      selected: period == p,
                      onSelected: (_) async {
                        if (p == _Period.custom) {
                          final now = DateTime.now();
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 10),
                            lastDate: now,
                            initialDateRange: range,
                            helpText: 'Intervalo de datas',
                          );
                          if (picked == null) return;
                          range = picked;
                        }
                        setSheet(() => period = p);
                      },
                    ),
                ],
              ),
              const SizedBox(height: FtSpace.md),
              DropdownButtonFormField<String?>(
                initialValue: account,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Conta', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  for (final a in data.accounts)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setSheet(() => account = v),
              ),
              const SizedBox(height: FtSpace.md),
              DropdownButtonFormField<String?>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  for (final c in data.categories)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text('${c.name} · ${c.kind == CategoryKind.income ? 'entrada' : 'saída'}'),
                    ),
                ],
                onChanged: (v) => setSheet(() => category = v),
              ),
              const SizedBox(height: FtSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: min,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Valor mínimo', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: FtSpace.md),
                  Expanded(
                    child: TextField(
                      controller: max,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Valor máximo', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FtSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Limpar'),
                    ),
                  ),
                  const SizedBox(width: FtSpace.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (apply == null) return;
    setState(() {
      if (apply) {
        _period = period;
        _range = range;
        _accountFilter = account;
        _categoryFilter = category;
        _minMinor = parse(min.text);
        _maxMinor = parse(max.text);
      } else {
        _period = _Period.all;
        _range = null;
        _accountFilter = null;
        _categoryFilter = null;
        _minMinor = null;
        _maxMinor = null;
      }
    });
  }

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
        if ((_kind == null || m.kind == _kind) && _matches(m, q) && _passesFilters(m)) m,
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
        Wrap(
          spacing: FtSpace.sm,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: const Text('Relatórios'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReportScreen()),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Importar'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
              ),
            ),
          ],
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
              Padding(
                padding: const EdgeInsets.only(right: FtSpace.sm),
                child: ActionChip(
                  avatar: const Icon(Icons.tune, size: 18),
                  label: Text(_activeFilters == 0 ? 'Filtros' : 'Filtros ($_activeFilters)'),
                  onPressed: _openFilters,
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
                  : 'Nenhum movimento corresponde à pesquisa ou aos filtros.',
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
