import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../security/session.dart';
import 'cloud_api.dart';
import 'cloud_controller.dart';

/// Conta FINTRACK: criar, entrar, sincronizar, terminar sessão, eliminar.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, this.entry = false, this.startCreate = false});

  /// Ecrã de entrada depois de terminar a sessão: começa em "Entrar" e
  /// oferece começar sem conta.
  final bool entry;

  /// No modo de entrada, abre já em "Criar conta".
  final bool startCreate;

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
    _create = !widget.entry || widget.startCreate;
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
      CloudStep? step = _create
          ? await cloud.signUp(_email.text, _password.text)
          : await cloud.signIn(_email.text, _password.text);
      while (step is NeedsEmailCode) {
        if (!mounted) return;
        setState(() => _busy = false); // à espera do utilizador, não do app
        final code = await _askEmailCode(step.email);
        if (code == null) return;
        if (mounted) setState(() => _busy = true);
        try {
          step = await cloud.confirmEmailCode(code);
        } on NeedsRecoveryCode {
          step = await _recover(cloud);
        } on CloudException catch (e) {
          if (mounted) setState(() => _error = e.message);
        }
      }
      if (step == null) return;
      final ready = step;
      final recovery = ready is CloudReady ? ready.recoveryCode : null;
      if (recovery != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RecoveryCodeScreen(code: recovery),
          fullscreenDialog: true,
        ));
      }
      await cloud.syncNow();
      _password.clear();
      _confirm.clear();
      // Conta sem dados na nuvem (nova): segue para criar o perfil.
      if (widget.entry && ref.read(sessionProvider).status != SessionStatus.unlocked) {
        await ref.read(sessionProvider.notifier).startWithoutAccount();
      }
      // Veio da vitrine: fecha este ecrã para o início (ou o perfil) aparecer.
      if (widget.entry && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on NeedsRecoveryCode {
      if (await _recover(cloud) != null) {
        await cloud.syncNow();
        if (widget.entry && ref.read(sessionProvider).status != SessionStatus.unlocked) {
          await ref.read(sessionProvider.notifier).startWithoutAccount();
        }
        if (widget.entry && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível concluir. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<CloudStep?> _recover(CloudController cloud) async {
    while (mounted) {
      setState(() => _busy = false);
      final rc = await _askRecoveryCode();
      if (rc == null) return null;
      if (mounted) setState(() => _busy = true);
      try {
        return await cloud.continueWithRecovery(rc);
      } on CloudException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    }
    return null;
  }

  Future<String?> _askEmailCode(String email) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Código enviado por e-mail'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enviámos um código de 6 dígitos para $email. Escreva-o aqui (válido 15 minutos).'),
            const SizedBox(height: FtSpace.sm),
            TextField(
              key: const Key('email-code'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: 24, letterSpacing: 6),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(cloudProvider.notifier).resendCode();
                messenger.showSnackBar(const SnackBar(content: Text('Código reenviado.')));
              },
              child: const Text('Reenviar código'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Confirmar')),
        ],
      ),
    );
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

  Future<void> _renameDevice(String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome deste dispositivo'),
        content: TextField(controller: controller, maxLength: 60, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (name != null) await ref.read(cloudProvider.notifier).renameDevice(name);
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

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminar sessão?'),
        content: const Text('Este telemóvel deixa de sincronizar. Os dados ficam aqui; '
            'para voltar, entre de novo com o e-mail e a palavra-passe.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminar sessão')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cloud = ref.read(cloudProvider.notifier);
    setState(() => _busy = true);
    final saved = await cloud.flushBeforeSignOut();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!saved) {
      final force = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sem ligação à nuvem'),
          content: const Text('Não foi possível guardar as últimas alterações. Se terminar agora, '
              'o que mudou desde a última sincronização perde-se.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminar mesmo assim')),
          ],
        ),
      );
      if (force != true || !mounted) return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await cloud.signOut();
    // Volta à raiz: o ecrã de entrada substitui o início.
    navigator.popUntil((r) => r.isFirst);
    messenger.showSnackBar(const SnackBar(content: Text('Sessão terminada. Os dados da conta saíram deste telemóvel.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = ref.watch(cloudProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: Text(widget.entry ? (_create ? 'Criar conta' : 'Entrar') : 'Conta e sincronização')),
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
                    Text('Dispositivos com sessão', style: theme.textTheme.titleSmall),
                    const SizedBox(height: FtSpace.xs),
                    for (final d in cloud.devices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(d.platform == 'ios' ? Icons.phone_iphone : Icons.phone_android),
                        title: Text(d.id == cloud.deviceId ? '${d.name} (este)' : d.name),
                        subtitle: Text('Último acesso: ${dayLabel(d.lastSeen.toLocal())}'),
                        trailing: d.id == cloud.deviceId
                            ? IconButton(
                                tooltip: 'Mudar o nome',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _renameDevice(d.name),
                              )
                            : null,
                      ),
                    if (cloud.devices.length > 1)
                      TextButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Terminar sessão nos outros dispositivos'),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await ref.read(cloudProvider.notifier).signOutOtherDevices();
                          messenger.showSnackBar(const SnackBar(content: Text('Sessões dos outros dispositivos terminadas.')));
                        },
                      ),
                    const Divider(height: FtSpace.xl),
                    OutlinedButton(
                      key: const Key('cloud-signout'),
                      onPressed: _busy ? null : _signOut,
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
