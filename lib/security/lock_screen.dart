import 'dart:async';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import 'pin_pad.dart';
import 'pin_vault.dart';
import 'session.dart';

/// Ecrã de desbloqueio por PIN, com atrasos progressivos.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;
  DateTime? _lockedUntil;
  bool _limitReached = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final status = await ref.read(pinVaultProvider).status();
    if (!mounted) return;
    if (status.signInRequired) {
      setState(() => _limitReached = true);
    } else if (status.remaining > Duration.zero) {
      _startCountdown(status.remaining);
    }
  }

  void _startCountdown(Duration wait) {
    _ticker?.cancel();
    setState(() => _lockedUntil = DateTime.now().add(wait));
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (!DateTime.now().isBefore(_lockedUntil!)) {
        timer.cancel();
        setState(() => _lockedUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _onCompleted(String pin) async {
    final UnlockResult result;
    try {
      result = await ref.read(sessionProvider.notifier).unlock(pin);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Não foi possível verificar o PIN. Tente de novo.');
      }
      return;
    }
    if (!mounted) return;

    switch (result) {
      case UnlockSuccess():
        break;
      case UnlockWrongPin(:final failures, :final wait):
        final left = LockoutPolicy.maxAttempts - failures;
        setState(() {
          _message = 'PIN incorreto. Restam $left tentativas.';
        });
        if (wait > Duration.zero) _startCountdown(wait);
      case UnlockThrottled(:final remaining):
        _startCountdown(remaining);
      case UnlockSignInRequired():
        setState(() => _limitReached = true);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repor o FINTRACK?'),
        content: const Text(
          'O PIN e todos os dados guardados neste telemóvel são apagados. '
          'Não é possível desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar e repor'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionProvider.notifier).resetApp();
    }
  }

  static String _clock(Duration d) {
    final s = d.inSeconds + 1;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final until = _lockedUntil;
    final waiting = until != null;

    String? info = _message;
    if (_limitReached) {
      info = 'Limite de ${LockoutPolicy.maxAttempts} tentativas atingido.';
    } else if (waiting) {
      final remaining = until.difference(DateTime.now());
      info = 'Demasiadas tentativas. Tente de novo em '
          '${_clock(remaining.isNegative ? Duration.zero : remaining)}.';
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.lg),
          child: Column(
            children: [
              const Spacer(),
              Text(
                'FINTRACK',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: FtSpace.sm),
              Text('Introduza o PIN', style: theme.textTheme.headlineSmall),
              SizedBox(
                height: 72,
                child: Center(
                  child: info == null
                      ? null
                      : Text(
                          info,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                            fontFeatures: ftAmountFeatures,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              if (_limitReached)
                FilledButton.tonal(
                  onPressed: _confirmReset,
                  child: const Text('Repor o FINTRACK'),
                )
              else
                PinPad(onCompleted: _onCompleted, enabled: !waiting),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
