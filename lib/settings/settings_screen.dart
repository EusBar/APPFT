import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../security/pin_pad.dart';
import '../security/session.dart';

/// Definições de segurança.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar tudo deste telemóvel?'),
        content: const Text(
          'O PIN, as contas e todos os dados guardados neste telemóvel são '
          'apagados. Não é possível desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(sessionProvider.notifier).resetApp();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final autoLock = ref.watch(sessionProvider.select((s) => s.autoLock));
    final biometric = ref.watch(sessionProvider.select((s) => s.biometricEnabled));
    final controller = ref.read(sessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FtSpace.md, FtSpace.md, FtSpace.md, FtSpace.xs),
            child: Text('Bloqueio automático', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FtSpace.md),
            child: Text(
              'Quando o FINTRACK fica em segundo plano, pede o PIN ao voltar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<AutoLockSetting>(
            groupValue: autoLock,
            onChanged: (s) {
              if (s != null) controller.setAutoLock(s);
            },
            child: Column(
              children: [
                for (final s in AutoLockSetting.values)
                  RadioListTile<AutoLockSetting>(value: s, title: Text(autoLockLabel(s))),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Desbloquear com biometria'),
            subtitle: const Text('Impressão digital ou rosto, como atalho do PIN.'),
            value: biometric,
            onChanged: (on) async {
              if (!on) {
                await controller.disableBiometrics();
                return;
              }
              final result = await Navigator.of(context).push<BiometricSetup>(
                MaterialPageRoute(builder: (_) => const _EnableBiometricScreen()),
              );
              if (!context.mounted || result == null) return;
              final text = switch (result) {
                BiometricSetup.enabled => 'Biometria ativada.',
                BiometricSetup.unavailable =>
                  'Este telemóvel não tem biometria configurada. '
                      'Registe uma impressão digital ou o rosto nas definições do telemóvel.',
                BiometricSetup.failed =>
                  'Não foi possível ativar. Confirme que tem uma impressão digital '
                      'ou o rosto registados nas definições do telemóvel.',
                BiometricSetup.wrongPin => 'PIN incorreto.',
              };
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.enhanced_encryption_outlined),
            title: Text('Dados cifrados neste telemóvel'),
            subtitle: Text(
              'A base de dados usa AES-256 (SQLCipher). A chave só é libertada '
              'com o PIN certo e nunca sai do dispositivo.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
            title: Text('Apagar tudo e repor', style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('Remove o PIN e todos os dados deste telemóvel.'),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Pede o PIN para ativar a biometria: é o PIN que liberta a chave que fica
/// guardada sob a impressão digital ou o rosto.
class _EnableBiometricScreen extends ConsumerStatefulWidget {
  const _EnableBiometricScreen();

  @override
  ConsumerState<_EnableBiometricScreen> createState() => _EnableBiometricScreenState();
}

class _EnableBiometricScreenState extends ConsumerState<_EnableBiometricScreen> {
  String? _error;

  Future<void> _onCompleted(String pin) async {
    final result = await ref.read(sessionProvider.notifier).enableBiometrics(pin);
    if (!mounted) return;
    if (result == BiometricSetup.wrongPin) {
      setState(() => _error = 'PIN incorreto. Tente de novo.');
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ativar biometria')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.lg),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Confirme o PIN', style: theme.textTheme.headlineSmall),
              const SizedBox(height: FtSpace.sm),
              Text(
                'Depois, o telemóvel pede a impressão digital ou o rosto.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(
                height: 56,
                child: Center(
                  child: _error == null
                      ? null
                      : Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
              PinPad(onCompleted: _onCompleted),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}
