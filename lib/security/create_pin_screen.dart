import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/backdrop.dart';
import '../design/tokens.dart';
import '../cloud/cloud_controller.dart';
import 'pin_pad.dart';
import 'session.dart';

String pinIssueMessage(PinIssue issue) {
  switch (issue) {
    case PinIssue.length:
    case PinIssue.notDigits:
      return 'O PIN tem de ter 6 dígitos.';
    case PinIssue.allSame:
      return 'Não use o mesmo dígito repetido. Escolha outro PIN.';
    case PinIssue.sequential:
      return 'Não use uma sequência como 123456. Escolha outro PIN.';
    case PinIssue.repeatedPattern:
      return 'Não use um padrão repetido como 121212. Escolha outro PIN.';
    case PinIssue.date:
      return 'Este PIN parece uma data, fácil de adivinhar. Escolha outro.';
  }
}

/// Criação do PIN: escolher e confirmar.
class CreatePinScreen extends ConsumerStatefulWidget {
  const CreatePinScreen({super.key});

  @override
  ConsumerState<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends ConsumerState<CreatePinScreen> {
  String? _first;
  String? _error;
  bool _saving = false;
  bool _syncing = false;
  bool _created = false;

  /// Segundo método de desbloqueio, logo a seguir ao PIN.
  Future<void> _offerBiometrics(String pin) async {
    if (mounted) setState(() => _created = true);
    if (!await ref.read(biometricKeyStoreProvider).isAvailable() || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint, size: 40),
        title: const Text('Desbloquear com impressão digital?'),
        content: const Text('Abra o FINTRACK com a impressão digital ou o rosto. '
            'O PIN continua a servir sempre que precisar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ativar')),
        ],
      ),
    );
    if (yes != true) return;
    final result = await ref.read(sessionProvider.notifier).enableBiometrics(pin);
    if (!mounted || result == BiometricSetup.enabled) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Não foi possível ativar a biometria. Pode tentar mais tarde nas Definições.'),
    ));
  }

  Future<void> _onCompleted(String pin) async {
    if (_first == null) {
      final issue = PinPolicy.check(pin);
      setState(() {
        _error = issue == null ? null : pinIssueMessage(issue);
        if (issue == null) _first = pin;
      });
      return;
    }

    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'Os PINs não coincidem. Comece de novo.';
      });
      return;
    }

    final session = ref.read(sessionProvider.notifier);
    final cloud = ref.read(cloudProvider.notifier);
    setState(() => _saving = true);
    try {
      await session.createPin(pin, beforeReady: () async {
        if (mounted) setState(() => _saving = false);
        await _offerBiometrics(pin);
        // Entrou na conta antes do PIN: os dados vêm agora da nuvem.
        if (cloud.hasParked) {
          if (mounted) setState(() => _saving = _syncing = true);
          await cloud.adoptParked();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _saving = _created = false);
      if (!mounted) return;
      setState(() {
        _first = null;
        _error = 'Não foi possível guardar o PIN neste dispositivo. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirming = _first != null;

    return FtBackdrop(
      image: FtImage.createPin,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.lg),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                confirming ? 'Confirme o PIN' : 'Crie um PIN de 6 dígitos',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FtSpace.sm),
              Text(
                confirming
                    ? 'Introduza o mesmo PIN outra vez.'
                    : 'Desbloqueia o FINTRACK neste telemóvel. O PIN nunca sai do dispositivo.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: 72,
                child: Center(
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              if (_saving)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: FtSpace.xl),
                  child: Column(children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: FtSpace.md),
                    Text(_syncing ? 'A trazer os seus dados da nuvem…' : 'A proteger o FINTRACK…'),
                  ]),
                )
              else if (_created)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: FtSpace.xl),
                  child: Column(children: [
                    Icon(Icons.check_circle, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: FtSpace.md),
                    const Text('PIN criado'),
                  ]),
                )
              else
                PinPad(onCompleted: _onCompleted),
            ],
          ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
