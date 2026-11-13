import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud/welcome_screen.dart';
import 'cloud/cloud_controller.dart';
import 'design/tokens.dart';
import 'home/home_screen.dart';
import 'onboarding/onboarding_screen.dart';
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

  final _navigator = GlobalKey<NavigatorState>();

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
      // Ao voltar ao app (e ainda desbloqueado): traz as alterações da nuvem.
      if (ref.read(sessionProvider).status == SessionStatus.unlocked) {
        ref.read(cloudProvider.notifier).syncIfStale();
      }
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
    final signedOut = ref.watch(sessionProvider.select((s) => s.signedOut));

    // Ao bloquear, fecha os ecrãs abertos por cima do inicial (definições,
    // nova conta), para que nada fique visível sobre o ecrã de bloqueio.
    ref.listen(sessionProvider.select((s) => s.status), (previous, next) {
      if (previous != next) {
        _navigator.currentState?.popUntil((route) => route.isFirst);
      }
    });

    return MaterialApp(
      title: 'FINTRACK',
      navigatorKey: _navigator,
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
        SessionStatus.onboarding when signedOut => const WelcomeScreen(),
        SessionStatus.onboarding => const OnboardingScreen(),
        SessionStatus.unlocked => const HomeScreen(),
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
