import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../security/session.dart';

/// Acessos que o FINTRACK pede ao utilizador.
enum Consent {
  photos('ft.consent.photos'),
  files('ft.consent.files'),
  notifications('ft.consent.notifications');

  const Consent(this.key);
  final String key;
}

class ConsentInfo {
  const ConsentInfo(this.icon, this.title, this.why, this.points);
  final IconData icon;
  final String title;
  final String why;
  final List<String> points;
}

ConsentInfo consentInfo(Consent c) => switch (c) {
      Consent.photos => const ConsentInfo(
          Icons.photo_library_outlined,
          'Fotografias',
          'Para escolher a fotografia do seu perfil.',
          [
            'Abre o seletor de fotografias do sistema: o FINTRACK só recebe a fotografia que escolher, nunca a galeria inteira.',
            'A fotografia é reduzida e guardada apenas neste telemóvel, cifrada.',
            'Pode retirar este acesso em Definições › Privacidade e permissões.',
          ],
        ),
      Consent.files => const ConsentInfo(
          Icons.folder_open_outlined,
          'Ficheiros',
          'Para importar movimentos de um ficheiro CSV ou Excel.',
          [
            'Abre o seletor de ficheiros do sistema: o FINTRACK só lê o ficheiro que escolher.',
            'O conteúdo é lido no telemóvel e nada é gravado sem a sua confirmação.',
            'Pode retirar este acesso em Definições › Privacidade e permissões.',
          ],
        ),
      Consent.notifications => const ConsentInfo(
          Icons.notifications_active_outlined,
          'Notificações',
          'Para lembrar compromissos a vencer e contribuições da Kixikila.',
          [
            'Os avisos nunca mostram valores no ecrã bloqueado.',
            'São agendados neste telemóvel; nada sai para a Internet.',
            'A seguir, o sistema pede a sua autorização. Pode desligar quando quiser.',
          ],
        ),
    };

/// Consentimentos dados, guardados no Keystore/Keychain.
class ConsentController extends Notifier<Map<Consent, bool>> {
  @override
  Map<Consent, bool> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final store = ref.read(secretStoreProvider);
    final values = <Consent, bool>{};
    for (final c in Consent.values) {
      values[c] = await store.read(c.key) == '1';
    }
    state = values;
  }

  bool granted(Consent c) => state[c] ?? false;

  Future<void> set(Consent c, bool value) async {
    final store = ref.read(secretStoreProvider);
    if (value) {
      await store.write(c.key, '1');
    } else {
      await store.delete(c.key);
    }
    state = {...state, c: value};
  }
}

final consentProvider = NotifierProvider<ConsentController, Map<Consent, bool>>(ConsentController.new);

/// Pede consentimento antes de usar um acesso, como no iOS: explica o
/// porquê e o que acontece, e só depois avança. Responde `true` se pode
/// continuar.
Future<bool> ensureConsent(BuildContext context, WidgetRef ref, Consent consent) async {
  final controller = ref.read(consentProvider.notifier);
  final secrets = ref.read(secretStoreProvider);
  if (await secrets.read(consent.key) == '1') return true;
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ConsentSheet(consent: consent),
  );
  if (ok == true) {
    await controller.set(consent, true);
    return true;
  }
  return false;
}

class ConsentSheet extends StatelessWidget {
  const ConsentSheet({super.key, required this.consent});

  final Consent consent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = consentInfo(consent);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(info.icon, size: 30, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: FtSpace.md),
            Text(
              'O FINTRACK quer aceder a ${info.title.toLowerCase()}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: FtSpace.xs),
            Text(info.why, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: FtSpace.lg),
            for (final p in info.points)
              Padding(
                padding: const EdgeInsets.only(bottom: FtSpace.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: FtSpace.sm),
                    Expanded(
                      child: Text(
                        p,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: FtSpace.md),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continuar')),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Agora não')),
          ],
        ),
      ),
    );
  }
}
