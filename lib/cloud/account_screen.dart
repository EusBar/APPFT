import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import 'cloud_api.dart';
import 'cloud_controller.dart';

/// Conta FINTRACK: criar, entrar, sincronizar, terminar sessão, eliminar.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _create = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(cloudProvider.notifier).load();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validate() {
    if (!_emailRe.hasMatch(_email.text.trim())) return 'E-mail inválido.';
    final p = _password.text;
    if (p.length < 10 || !p.contains(RegExp('[a-z]')) || !p.contains(RegExp('[A-Z]')) || !p.contains(RegExp('[0-9]'))) {
      return 'A palavra-passe precisa de 10 caracteres, com maiúsculas, minúsculas e algarismos.';
    }
    if (_create && p != _confirm.text) return 'As palavras-passe não coincidem.';
    return null;
  }

  Future<void> _submit() async {
    final invalid = _validate();
    setState(() => _error = invalid);
    if (invalid != null) return;
    setState(() => _busy = true);
    final cloud = ref.read(cloudProvider.notifier);
    try {
      String? code;
      if (_create) {
        code = await cloud.signUp(_email.text, _password.text);
      } else {
        try {
          code = await cloud.signIn(_email.text, _password.text);
        } on NeedsRecoveryCode {
          if (!mounted) return;
          final rc = await _askRecoveryCode();
          if (rc == null) return;
          code = await cloud.signIn(_email.text, _password.text, recoveryCode: rc);
        }
      }
      if (!mounted) return;
      if (code != null) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RecoveryCodeScreen(code: code!),
          fullscreenDialog: true,
        ));
      }
      await cloud.syncNow();
      _password.clear();
      _confirm.clear();
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível concluir. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askRecoveryCode() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Código de recuperação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A palavra-passe mudou desde que os dados foram cifrados. Escreva o código de '
              'recuperação que guardou ao criar a conta.',
            ),
            TextField(
              key: const Key('recovery-input'),
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'XXXX-XXXX-…'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Continuar')),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(String email) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar a conta na nuvem?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A conta e todos os dados guardados na nuvem são apagados de imediato e não podem '
              'ser recuperados. Os dados deste telemóvel ficam. Para confirmar, escreva o seu e-mail.',
            ),
            TextField(controller: typed, keyboardType: TextInputType.emailAddress),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(typed.text.trim().toLowerCase() == email.toLowerCase()),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cloudProvider.notifier).deleteCloudAccount();
      messenger.showSnackBar(const SnackBar(content: Text('Conta na nuvem eliminada.')));
    } on CloudException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = ref.watch(cloudProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Conta e sincronização')),
      body: !cloud.loaded
          ? const Center(child: CircularProgressIndicator())
          : cloud.signedIn
              ? ListView(
                  padding: const EdgeInsets.all(FtSpace.lg),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(cloud.email!),
                      subtitle: Text(
                        cloud.syncing
                            ? 'A sincronizar…'
                            : cloud.lastSync == null
                                ? 'Ainda não sincronizado'
                                : 'Última sincronização: ${dayLabel(cloud.lastSync!)} às '
                                    '${cloud.lastSync!.hour.toString().padLeft(2, '0')}:'
                                    '${cloud.lastSync!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                    if (cloud.error != null)
                      Text(cloud.error!, style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: FtSpace.md),
                    FilledButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('Sincronizar agora'),
                      onPressed: cloud.syncing ? null : () => ref.read(cloudProvider.notifier).syncNow(),
                    ),
                    const SizedBox(height: FtSpace.lg),
                    Text(
                      'Os dados são cifrados neste telemóvel antes de saírem (XChaCha20-Poly1305). '
                      'O servidor só guarda texto ilegível. Noutro telemóvel, entre com o mesmo '
                      'e-mail e palavra-passe para trazer tudo.',
                      style: muted,
                    ),
                    const Divider(height: FtSpace.xl),
                    OutlinedButton(
                      onPressed: () => ref.read(cloudProvider.notifier).signOut(),
                      child: const Text('Terminar sessão neste telemóvel'),
                    ),
                    const SizedBox(height: FtSpace.sm),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: () => _deleteAccount(cloud.email!),
                      child: const Text('Eliminar conta e dados na nuvem'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(FtSpace.lg),
                  children: [
                    Text('Os seus dados em todos os telemóveis', style: theme.textTheme.titleLarge),
                    const SizedBox(height: FtSpace.sm),
                    for (final p in const [
                      'Cifra ponta-a-ponta: nem o FINTRACK consegue ler os seus dados na nuvem.',
                      'Cópia automática: se perder o telemóvel, entra noutro e recupera tudo.',
                      'Opcional: sem conta, o FINTRACK continua a funcionar só neste telemóvel.',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: FtSpace.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: FtSpace.sm),
                            Expanded(child: Text(p, style: muted)),
                          ],
                        ),
                      ),
                    const SizedBox(height: FtSpace.md),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Criar conta')),
                        ButtonSegment(value: false, label: Text('Entrar')),
                      ],
                      selected: {_create},
                      onSelectionChanged: (v) => setState(() {
                        _create = v.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: FtSpace.md),
                    TextField(
                      key: const Key('cloud-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: FtSpace.sm),
                    TextField(
                      key: const Key('cloud-password'),
                      controller: _password,
                      obscureText: _hidden,
                      autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Palavra-passe',
                        helperText: _create ? 'Mínimo 10 caracteres, com maiúsculas, minúsculas e algarismos.' : null,
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Mostrar' : 'Ocultar',
                          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
                    ),
                    if (_create) ...[
                      const SizedBox(height: FtSpace.sm),
                      TextField(
                        key: const Key('cloud-confirm'),
                        controller: _confirm,
                        obscureText: _hidden,
                        decoration: const InputDecoration(
                          labelText: 'Repita a palavra-passe',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: FtSpace.sm),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: FtSpace.lg),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_create ? 'Criar conta' : 'Entrar'),
                    ),
                    if (_busy) const Padding(padding: EdgeInsets.only(top: FtSpace.sm), child: LinearProgressIndicator()),
                  ],
                ),
    );
  }
}

/// Mostra o código de recuperação uma única vez e confirma que foi guardado.
class RecoveryCodeScreen extends StatefulWidget {
  const RecoveryCodeScreen({super.key, required this.code});

  final String code;

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  final _check = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  String get _lastGroup => widget.code.split('-').last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Código de recuperação'), automaticallyImplyLeading: false),
        body: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            Text(
              'Guarde este código fora do telemóvel (papel, gestor de palavras-passe). É a única '
              'forma de abrir os seus dados se esquecer a palavra-passe. O FINTRACK não o guarda.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: FtSpace.lg),
            Container(
              padding: const EdgeInsets.all(FtSpace.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(FtRadius.md),
              ),
              child: SelectableText(
                widget.code.replaceAll('-', ' – '),
                key: const Key('recovery-code'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                  height: 1.6,
                ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
              onPressed: () => Clipboard.setData(ClipboardData(text: widget.code)),
            ),
            const SizedBox(height: FtSpace.md),
            Text('Para confirmar, escreva o último grupo de 4 caracteres:', style: theme.textTheme.bodySmall),
            TextField(
              key: const Key('recovery-check'),
              controller: _check,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(errorText: _error, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: FtSpace.lg),
            FilledButton(
              onPressed: () {
                if (_check.text.trim().toUpperCase() != _lastGroup) {
                  setState(() => _error = 'Não corresponde. Verifique o código.');
                  return;
                }
                Clipboard.setData(const ClipboardData(text: ''));
                Navigator.of(context).pop();
              },
              child: const Text('Guardei o código'),
            ),
          ],
        ),
      ),
    );
  }
}
