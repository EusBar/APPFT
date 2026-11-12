import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/tokens.dart';
import 'security/create_pin_screen.dart';
import 'security/lock_screen.dart';
import 'security/session.dart';

void main() {
  runApp(const ProviderScope(child: FintrackApp()));
}

class FintrackApp extends ConsumerStatefulWidget {
  const FintrackApp({super.key});

  @override
  ConsumerState<FintrackApp> createState() => _FintrackAppState();
}

class _FintrackAppState extends ConsumerState<FintrackApp>
    with WidgetsBindingObserver {
  /// Verdadeiro enquanto o app não está em primeiro plano: tapa o conteúdo
  /// no alternador de apps.
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(sessionProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      session.onForeground();
      setState(() => _obscured = false);
    } else {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
        session.onBackground();
      }
      setState(() => _obscured = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(sessionProvider.select((s) => s.status));

    return MaterialApp(
      title: 'FINTRACK',
      debugShowCheckedModeBanner: false,
      theme: buildFintrackTheme(Brightness.light),
      darkTheme: buildFintrackTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          if (_obscured) const _PrivacyCover(),
        ],
      ),
      home: switch (status) {
        SessionStatus.loading => const _LoadingScreen(),
        SessionStatus.needsPin => const CreatePinScreen(),
        SessionStatus.locked => const LockScreen(),
        SessionStatus.unlocked => const FoundationScreen(),
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Center(
          child: Text(
            'FINTRACK',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ecrã provisório depois do desbloqueio. Ainda não há contas nem movimentos:
/// mostra só um valor de exemplo para demonstrar o formato e o modo discreto.
class FoundationScreen extends ConsumerWidget {
  const FoundationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final discreet = ref.watch(sessionProvider.select((s) => s.discreet));
    final session = ref.read(sessionProvider.notifier);
    const sample = Money(123456789, Currency.aoa);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FINTRACK'),
        actions: [
          IconButton(
            tooltip: discreet ? 'Mostrar valores' : 'Ocultar valores',
            icon: Icon(discreet ? Icons.visibility_off : Icons.visibility),
            onPressed: session.toggleDiscreet,
          ),
          IconButton(
            tooltip: 'Bloquear',
            icon: const Icon(Icons.lock_outline),
            onPressed: session.lock,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Money. Under Control.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FtSpace.xl),
              Text(
                'Exemplo de formato (não é um saldo real)',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.estimate,
                ),
              ),
              const SizedBox(height: FtSpace.xs),
              GestureDetector(
                onDoubleTap: session.toggleDiscreet,
                child: Text(
                  discreet ? '••••••' : sample.format(),
                  semanticsLabel: discreet ? 'Valor oculto' : null,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: ftAmountFeatures,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: FtSpace.sm),
              Text(
                'Toque duas vezes no valor para o ocultar.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Versão 0.2.0 · Fundação',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
