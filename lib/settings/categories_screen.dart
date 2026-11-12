import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';

const _iconChoices = [
  'home', 'food', 'transport', 'health', 'education', 'personal', 'household', 'debt',
  'savings', 'shield', 'project', 'family', 'group', 'salary', 'business', 'refund', 'interest', 'other',
];

/// Gerir categorias: criar, renomear, mudar o ícone e arquivar. Arquivar
/// esconde a categoria dos formulários; o histórico mantém-se.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {Category? category, CategoryKind? kind}) async {
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(category: category, kind: kind ?? category!.kind),
    );
    if (result == null) return;
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    await store.saveCategory(result);
    ref.invalidate(financeProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final finance = ref.watch(financeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      body: finance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível ler as categorias.')),
        data: (data) => ListView(
          padding: const EdgeInsets.only(bottom: FtSpace.xl),
          children: [
            for (final kind in [CategoryKind.expense, CategoryKind.income]) ...[
              ListTile(
                title: Text(kind == CategoryKind.expense ? 'Saídas' : 'Entradas', style: theme.textTheme.titleSmall),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nova'),
                  onPressed: () => _edit(context, ref, kind: kind),
                ),
              ),
              for (final c in data.categories.where((c) => c.kind == kind))
                ListTile(
                  leading: Icon(categoryIcon(c.icon),
                      color: c.archived ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5) : null),
                  title: Text(
                    c.name,
                    style: c.archived ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null,
                  ),
                  subtitle: c.archived ? const Text('Arquivada') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(context, ref, category: c),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.category, required this.kind});

  final Category? category;
  final CategoryKind kind;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _icon = widget.category?.icon ?? 'other';
  late bool _archived = widget.category?.archived ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = NameRules.clean(_name.text);
    if (name == null) {
      setState(() => _error = 'Escreva um nome.');
      return;
    }
    final c = widget.category;
    Navigator.of(context).pop(c == null
        ? Category(id: 'cus.${newId()}', kind: widget.kind, name: name, icon: _icon)
        : c.copyWith(name: name, icon: _icon, archived: _archived));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, MediaQuery.viewInsetsOf(context).bottom + FtSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.category == null ? 'Nova categoria' : 'Editar categoria', style: theme.textTheme.titleLarge),
          const SizedBox(height: FtSpace.md),
          TextField(
            key: const Key('category-name'),
            controller: _name,
            maxLength: NameRules.maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Nome', errorText: _error, border: const OutlineInputBorder()),
          ),
          Wrap(
            spacing: FtSpace.xs,
            runSpacing: FtSpace.xs,
            children: [
              for (final i in _iconChoices)
                ChoiceChip(
                  label: Icon(categoryIcon(i), size: 20),
                  selected: _icon == i,
                  onSelected: (_) => setState(() => _icon = i),
                ),
            ],
          ),
          if (widget.category != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Arquivada'),
              subtitle: const Text('Deixa de aparecer nos formulários; o histórico mantém-se.'),
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
          const SizedBox(height: FtSpace.md),
          FilledButton(onPressed: _save, child: const Text('Guardar categoria')),
        ],
      ),
    );
  }
}
