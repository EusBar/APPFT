import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../data/snapshot.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../privacy/consent.dart';
import '../security/session.dart';

String _stamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

Future<void> _share(List<int> bytes, String mime, String name) => SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mime)],
      fileNameOverrides: [name],
      subject: name,
    ));

/// Pede uma palavra-passe (duas vezes ao criar).
Future<String?> askPassword(BuildContext context, {required bool confirm}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordDialog(confirm: confirm),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    if (_a.text.length < EncryptedBackup.minPasswordLength) {
      setState(() => _error = 'Pelo menos ${EncryptedBackup.minPasswordLength} caracteres.');
      return;
    }
    if (widget.confirm && _a.text != _b.text) {
      setState(() => _error = 'As palavras-passe não coincidem.');
      return;
    }
    Navigator.of(context).pop(_a.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Palavra-passe da cópia' : 'Palavra-passe da cópia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.confirm)
            const Padding(
              padding: EdgeInsets.only(bottom: FtSpace.sm),
              child: Text(
                'Sem esta palavra-passe a cópia não pode ser aberta, nem pelo FINTRACK. Guarde-a bem.',
              ),
            ),
          TextField(
            key: const Key('backup-password'),
            controller: _a,
            obscureText: _hidden,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Palavra-passe',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Mostrar' : 'Ocultar',
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          if (widget.confirm)
            TextField(
              key: const Key('backup-password-confirm'),
              controller: _b,
              obscureText: _hidden,
              decoration: const InputDecoration(labelText: 'Repita a palavra-passe'),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: const Text('Continuar')),
      ],
    );
  }
}

/// Restaura uma cópia cifrada: escolher ficheiro, palavra-passe, confirmar.
/// Usado nas Definições e no início (depois de reinstalar).
Future<bool> restoreBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await ensureConsent(context, ref, Consent.files)) return false;
  final files = await FilePicker.pickFiles();
  if (files.isEmpty || !context.mounted) return false;
  final bytes = await files.first.readAsBytes();
  if (!context.mounted) return false;
  final password = await askPassword(context, confirm: false);
  if (password == null || !context.mounted) return false;
  Snapshot snapshot;
  try {
    snapshot = await EncryptedBackup.decrypt(bytes, password);
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Não foi possível ler esta cópia.')));
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restaurar esta cópia?'),
      content: Text(
        'Cópia de ${snapshot.profile.name}: ${snapshot.accounts.length} contas e '
        '${snapshot.movements.length} registos. Substitui todos os dados atuais deste telemóvel.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restaurar')),
      ],
    ),
  );
  if (ok != true) return false;
  await ref.read(sessionProvider.notifier).restore(snapshot);
  ref.invalidate(financeProvider);
  messenger.showSnackBar(const SnackBar(content: Text('Cópia restaurada.')));
  return true;
}

/// Os seus dados: cópia de segurança cifrada, restauro e exportação.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível concluir.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    final password = await askPassword(context, confirm: true);
    final store = ref.read(sessionProvider.notifier).store;
    if (password == null || store == null) return;
    await _run(() async {
      final bytes = await EncryptedBackup.encrypt(await Snapshot.read(store), password);
      await _share(bytes, 'application/octet-stream', 'FINTRACK-copia-${_stamp()}.ftbackup');
    });
  }

  Future<void> _export() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exportar todos os dados'),
        content: const Text(
          'Ficheiro JSON legível com todos os seus dados, sem cifra. Útil para os ver noutro '
          'programa. Para guardar em segurança, prefira a cópia cifrada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Exportar')),
        ],
      ),
    );
    final store = ref.read(sessionProvider.notifier).store;
    if (ok != true || store == null) return;
    await _run(() async {
      final json = (await Snapshot.read(store)).encodePretty();
      await _share(utf8.encode(json), 'application/json', 'FINTRACK-dados-${_stamp()}.json');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Os seus dados')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FtSpace.sm),
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Criar cópia de segurança cifrada'),
            subtitle: const Text('Ficheiro protegido por palavra-passe (Argon2id + AES-256). Guarde-o fora do telemóvel.'),
            enabled: !_busy,
            onTap: _backup,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restaurar uma cópia'),
            subtitle: const Text('Substitui os dados deste telemóvel pelos da cópia.'),
            enabled: !_busy,
            onTap: () => restoreBackup(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('Exportar todos os dados (JSON)'),
            subtitle: const Text('Direito de acesso e portabilidade. Ficheiro sem cifra.'),
            enabled: !_busy,
            onTap: _export,
          ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(FtSpace.md),
            child: Text(
              'Os ficheiros só saem do telemóvel quando os partilha. Para apagar tudo, use '
              '"Apagar tudo e repor" nas Definições.',
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}
