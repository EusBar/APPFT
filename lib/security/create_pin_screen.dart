import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
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

    try {
      await ref.read(sessionProvider.notifier).createPin(pin);
    } catch (_) {
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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.lg),
          child: Column(
            children: [
              const Spacer(),
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
              PinPad(onCompleted: _onCompleted),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
