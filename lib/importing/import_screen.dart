import 'dart:convert';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';
import 'xlsx_reader.dart';

String importIssueMessage(ImportIssue issue) => switch (issue) {
      ImportIssue.missingDate => 'Sem data',
      ImportIssue.invalidDate => 'Data inválida',
      ImportIssue.missingAmount => 'Sem valor',
      ImportIssue.invalidAmount => 'Valor inválido',
      ImportIssue.zeroAmount => 'Valor zero',
      ImportIssue.transferNotSupported => 'Transferência (registe à mão)',
      ImportIssue.beforeAccountStart => 'Antes do início da conta',
      ImportIssue.inFuture => 'Data no futuro',
    };

/// Converte bytes de texto: UTF-8 (com ou sem BOM) ou, se falhar, Latin-1
/// (CSV gravado pelo Excel no Windows).
String decodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Importação de CSV ou Excel: escolher ficheiro, indicar colunas, rever e
/// confirmar. Duplicados ficam desmarcados; a importação inteira pode ser
/// anulada depois (com estornos).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  static const _maxBytes = 5 * 1024 * 1024;

  String? _fileName;
  List<List<String>>? _rows;
  bool _hasHeader = true;
  ImportColumns _columns = const ImportColumns();
  String? _accountId;
  final Set<int> _excluded = {};
  bool _excludedTouched = false;
  String? _error;
  bool _busy = false;
  String _batchId = newId();

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'xlsx'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final size = await file.length();
      if (size != null && size > _maxBytes) {
        setState(() => _error = 'Ficheiro grande demais (máximo 5 MB).');
        return;
      }
      final bytes = await file.readAsBytes();
      loadBytes(file.name, bytes);
    } catch (_) {
      setState(() => _error = 'Não foi possível ler o ficheiro.');
    }
  }

  /// Também usado nos testes.
  void loadBytes(String name, List<int> bytes) {
    try {
      final rows = name.toLowerCase().endsWith('.xlsx')
          ? XlsxReader.read(bytes)
          : TabularText.parse(decodeText(bytes));
      if (rows.isEmpty) {
        setState(() => _error = 'O ficheiro está vazio.');
        return;
      }
      setState(() {
        _fileName = name;
        _rows = rows;
        _hasHeader = rows.first.every((c) => parseImportDate(c) == null);
        _columns = _hasHeader ? ImportColumns.guess(rows.first) : const ImportColumns();
        _excluded.clear();
        _excludedTouched = false;
        _batchId = newId();
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  List<ImportRow> _plan(FinanceData data) {
    final rows = _rows;
    final account = data.account(_accountId) ?? data.openAccounts.firstOrNull;
    if (rows == null || account == null || !_columns.isUsable) return const [];
    var tick = DateTime.now();
    return ImportPlan.build(
      rows: rows,
      hasHeader: _hasHeader,
      columns: _columns,
      account: account,
      categories: data.categories,
      ledger: data.ledger,
      today: DateTime.now(),
      batchId: _batchId,
      newId: newId,
      now: () => tick = tick.add(const Duration(milliseconds: 1)),
      suggest: (description, kind) => data.suggester.suggest(description, kind, data.categories),
    );
  }

  Future<void> _import(List<Movement> movements) async {
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null || movements.isEmpty) return;
    setState(() => _busy = true);
    try {
      await store.append(movements);
      ref.invalidate(financeProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${movements.length} movimentos importados.')),
      );
      setState(() {
        _rows = null;
        _fileName = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível importar. Nada foi gravado.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(FinanceData data, List<Movement> batch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anular esta importação?'),
        content: Text(
          'Os ${batch.length} movimentos ficam anulados por estornos. Nada é apagado: '
          'o histórico mostra a importação e a anulação.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true) return;
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final now = DateTime.now();
    await store.append([
      for (final (i, m) in batch.indexed)
        m.reversal(id: newId(), createdAt: now.add(Duration(milliseconds: i))),
    ]);
    ref.invalidate(financeProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importação anulada.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final finance = ref.watch(financeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Importar movimentos')),
      body: finance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível ler os dados.')),
        data: (data) => _body(context, data),
      ),
    );
  }

  Widget _body(BuildContext context, FinanceData data) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    _accountId ??= data.openAccounts.firstOrNull?.id;
    final rows = _rows;

    if (rows == null) {
      final batches = data.ledger.importBatches();
      return ListView(
        padding: const EdgeInsets.all(FtSpace.lg),
        children: [
          Text(
            'Traga o histórico de uma folha de cálculo ou do extrato do banco. '
            'Aceita CSV (separado por ";" ou ",") e Excel (.xlsx), com datas como '
            '03/11/2026 e valores como 12 500,00.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FtSpace.md),
          Text(
            'Nada é gravado sem a sua confirmação. Duplicados ficam de fora, e pode anular '
            'uma importação inteira depois.',
            style: muted,
          ),
          const SizedBox(height: FtSpace.lg),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Escolher ficheiro'),
            onPressed: _pick,
          ),
          if (_error != null) ...[
            const SizedBox(height: FtSpace.sm),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (batches.isNotEmpty) ...[
            const SizedBox(height: FtSpace.xl),
            Text('Importações anteriores', style: theme.textTheme.titleSmall),
            for (final entry in batches.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text('${entry.value.length} movimentos'),
                subtitle: Text(
                  'Importados em ${dayLabel(entry.value.first.createdAt)} · '
                  '${data.account(entry.value.first.accountId)?.name ?? '?'}',
                ),
                trailing: TextButton(
                  onPressed: () => _undo(data, entry.value),
                  child: const Text('Anular'),
                ),
              ),
          ],
        ],
      );
    }

    final header = _hasHeader ? rows.first : null;
    final width = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    String columnLabel(int i) {
      final h = header != null && i < header.length ? header[i] : '';
      return h.isEmpty ? 'Coluna ${i + 1}' : h;
    }

    final plan = _plan(data);
    if (!_excludedTouched) {
      _excluded
        ..clear()
        ..addAll([for (final r in plan) if (r.duplicate) r.line]);
    }
    final importable = [for (final r in plan) if (r.isValid) r];
    final selected = [
      for (final r in importable)
        if (!_excluded.contains(r.line)) r.movement!,
    ];
    final errors = plan.where((r) => !r.isValid).length;
    final duplicates = importable.where((r) => r.duplicate).length;

    Widget columnPicker(String label, int? value, void Function(int?) onChanged) => Padding(
          padding: const EdgeInsets.only(bottom: FtSpace.sm),
          child: DropdownButtonFormField<int?>(
            key: ValueKey('$label-$value-$_hasHeader'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('—')),
              for (var i = 0; i < width; i++)
                DropdownMenuItem<int?>(value: i, child: Text(columnLabel(i), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              onChanged(v);
              _excludedTouched = false;
            }),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(FtSpace.lg),
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined),
            const SizedBox(width: FtSpace.sm),
            Expanded(child: Text(_fileName ?? '', style: theme.textTheme.titleSmall)),
            TextButton(onPressed: _pick, child: const Text('Trocar')),
          ],
        ),
        Text('${rows.length} linhas lidas.', style: muted),
        const SizedBox(height: FtSpace.md),
        DropdownButtonFormField<String>(
          initialValue: _accountId,
          decoration: const InputDecoration(labelText: 'Importar para a conta', border: OutlineInputBorder()),
          items: [
            for (final a in data.openAccounts)
              DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.currency.code}')),
          ],
          onChanged: (id) => setState(() {
            _accountId = id;
            _excludedTouched = false;
          }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('A primeira linha é o cabeçalho'),
          value: _hasHeader,
          onChanged: (v) => setState(() {
            _hasHeader = v;
            _columns = v ? ImportColumns.guess(rows.first) : _columns;
            _excludedTouched = false;
          }),
        ),
        Text('Colunas', style: theme.textTheme.titleSmall),
        const SizedBox(height: FtSpace.sm),
        columnPicker('Data *', _columns.date, (v) => _columns = _columns.copyWith(date: () => v)),
        columnPicker('Descrição', _columns.description, (v) => _columns = _columns.copyWith(description: () => v)),
        columnPicker('Valor (negativo = saída)', _columns.amount, (v) => _columns = _columns.copyWith(amount: () => v)),
        if (_columns.amount == null) ...[
          columnPicker('Débito (saídas)', _columns.debit, (v) => _columns = _columns.copyWith(debit: () => v)),
          columnPicker('Crédito (entradas)', _columns.credit, (v) => _columns = _columns.copyWith(credit: () => v)),
        ],
        columnPicker('Tipo (Entrada/Saída)', _columns.kind, (v) => _columns = _columns.copyWith(kind: () => v)),
        columnPicker('Categoria', _columns.category, (v) => _columns = _columns.copyWith(category: () => v)),
        if (!_columns.isUsable)
          Text('Indique pelo menos a data e o valor (ou débito/crédito).',
              style: TextStyle(color: theme.colorScheme.error)),
        if (_columns.isUsable) ...[
          const SizedBox(height: FtSpace.md),
          Text('Pré-visualização', style: theme.textTheme.titleSmall),
          const SizedBox(height: FtSpace.xs),
          Text(
            '${importable.length} válidas · $duplicates possíveis duplicados (desmarcados) · '
            '$errors com erro',
            style: muted,
          ),
          const SizedBox(height: FtSpace.sm),
          for (final r in plan.take(300)) _PreviewRow(
            row: r,
            data: data,
            checked: r.isValid && !_excluded.contains(r.line),
            onChanged: !r.isValid
                ? null
                : (v) => setState(() {
                      _excludedTouched = true;
                      if (v) {
                        _excluded.remove(r.line);
                      } else {
                        _excluded.add(r.line);
                      }
                    }),
          ),
          if (plan.length > 300) Text('… e mais ${plan.length - 300} linhas.', style: muted),
        ],
        if (_error != null) ...[
          const SizedBox(height: FtSpace.sm),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: FtSpace.lg),
        FilledButton(
          onPressed: _busy || selected.isEmpty ? null : () => _import(selected),
          child: Text('Importar ${selected.length} movimentos'),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row, required this.data, required this.checked, this.onChanged});

  final ImportRow row;
  final FinanceData data;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final m = row.movement;
    final issue = row.issue;
    final subtitle = issue != null
        ? 'Linha ${row.line} · ${importIssueMessage(issue)}'
        : [
            'Linha ${row.line}',
            if (m != null) dayLabel(m.date),
            if (m != null) data.category(m.categoryId)?.name ?? '',
            if (row.duplicate) 'possível duplicado',
          ].join(' · ');
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      title: Text(
        m == null || m.description.isEmpty ? (m == null ? '—' : movementKindLabel(m.kind)) : m.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: issue != null ? theme.colorScheme.error : row.duplicate ? colors.alert : null),
      ),
      secondary: m == null
          ? null
          : Text(
              '${m.kind == MovementKind.expense ? '−' : '+'}${m.amount.format()}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: ftAmountFeatures,
                color: m.kind == MovementKind.expense ? colors.expense : colors.income,
              ),
            ),
    );
  }
}
