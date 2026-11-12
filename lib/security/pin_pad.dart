import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';

/// Teclado numérico com os 6 indicadores do PIN.
///
/// Chama [onCompleted] ao sexto dígito e limpa-se quando a chamada termina.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted, this.enabled = true});

  final Future<void> Function(String pin) onCompleted;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  bool get _active => widget.enabled && !_busy;

  Future<void> _press(String digit) async {
    if (!_active || _pin.length >= PinPolicy.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length < PinPolicy.length) return;

    setState(() => _busy = true);
    try {
      await widget.onCompleted(_pin);
    } finally {
      if (mounted) {
        setState(() {
          _pin = '';
          _busy = false;
        });
      }
    }
  }

  void _backspace() {
    if (!_active || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget row(List<Widget> keys) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: keys,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${_pin.length} de ${PinPolicy.length} dígitos introduzidos',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < PinPolicy.length; i++)
                AnimatedContainer(
                  duration: FtMotion.fast,
                  margin: const EdgeInsets.symmetric(horizontal: FtSpace.sm),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: i < _pin.length ? scheme.primary : scheme.outline,
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: FtSpace.xl,
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
        ),
        AnimatedOpacity(
          duration: FtMotion.fast,
          opacity: _active ? 1 : 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final digits in const ['123', '456', '789'])
                row([
                  for (final d in digits.split(''))
                    _Key(label: d, onTap: () => _press(d)),
                ]),
              row([
                const SizedBox(width: _Key.extent, height: _Key.extent),
                _Key(label: '0', onTap: () => _press('0')),
                _Key(
                  icon: Icons.backspace_outlined,
                  semanticLabel: 'Apagar último dígito',
                  onTap: _backspace,
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.semanticLabel, required this.onTap});

  static const extent = 80.0;

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: extent,
      height: extent,
      child: Padding(
        padding: const EdgeInsets.all(FtSpace.xs),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFeatures: ftAmountFeatures,
                      ),
                    )
                  : Icon(icon, semanticLabel: semanticLabel),
            ),
          ),
        ),
      ),
    );
  }
}
