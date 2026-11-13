import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/country_photos.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../notifications/reminders.dart';
import '../privacy/consent.dart';
import '../profile/profile_screen.dart';
import '../security/pin_pad.dart';
import '../security/session.dart';
import '../legal/legal_screen.dart';
import 'categories_screen.dart';
import 'data_screen.dart';

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
    await ref.read(remindersProvider).cancelAll();
    await ref.read(consentProvider.notifier).set(Consent.notifications, false);
    await ref.read(sessionProvider.notifier).resetApp();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final autoLock = ref.watch(sessionProvider.select((s) => s.autoLock));
    final biometric = ref.watch(sessionProvider.select((s) => s.biometricEnabled));
    final horizon = ref.watch(sessionProvider.select((s) => s.horizon));
    final controller = ref.read(sessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: ListView(
        children: [
          ListTile(
            leading: ProfileAvatar(profile: ref.watch(sessionProvider.select((s) => s.profile))),
            title: const Text('Perfil'),
            subtitle: const Text('Nome, alcunha e fotografia'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categorias'),
            subtitle: const Text('Criar, renomear e arquivar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()),
            ),
          ),
          const Divider(),
          const _PrivacySection(),
          const Divider(),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(FtSpace.md, FtSpace.md, FtSpace.md, FtSpace.xs),
            child: Text('Horizonte do saldo disponível', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FtSpace.md),
            child: Text(
              'Compromissos pendentes até esta data reduzem o saldo disponível.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<AvailableHorizon>(
            groupValue: horizon,
            onChanged: (h) {
              if (h != null) controller.setHorizon(h);
            },
            child: Column(
              children: [
                for (final h in AvailableHorizon.values)
                  RadioListTile<AvailableHorizon>(value: h, title: Text(horizonLabel(h))),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Créditos das fotografias'),
            subtitle: const Text('Unsplash e autor do projeto'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _PhotoCreditsScreen()),
            ),
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
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('Os seus dados'),
            subtitle: const Text('Cópia de segurança cifrada, restauro e exportação'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Política de privacidade'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.privacy)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Termos de utilização'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.terms)),
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

class _PhotoCreditsScreen extends StatelessWidget {
  const _PhotoCreditsScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Créditos das fotografias')),
      body: ListView(
        padding: const EdgeInsets.all(FtSpace.md),
        children: [
          Text(
            'Fotografias do Unsplash (Licença Unsplash) e, para Angola, fornecidas '
            'pelo autor do projeto. Desfocadas e reduzidas para o fundo do FINTRACK.',
            style: theme.textTheme.bodySmall,
          ),
          for (final entry in countryPhotos.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: FtSpace.lg, bottom: FtSpace.xs),
              child: Text(
                '${currencyRegion(Currency.fromCode(entry.key))} · ${entry.key}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final p in entry.value)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.place),
                subtitle: Text(
                  p.unsplashId == null
                      ? 'Fornecida pelo autor do projeto'
                      : 'Unsplash · imagem ${p.unsplashId}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Privacidade e permissões: o que o FINTRACK pode usar, com explicação.
class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  Future<void> _toggleNotifications(BuildContext context, WidgetRef ref, bool on) async {
    final consent = ref.read(consentProvider.notifier);
    final reminders = ref.read(remindersProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      await reminders.cancelAll();
      await consent.set(Consent.notifications, false);
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ConsentSheet(consent: Consent.notifications),
    );
    if (ok != true) return;
    final granted = await reminders.requestPermission();
    if (!granted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('O sistema não autorizou. Pode ativar em Definições do telemóvel › Apps › FINTRACK › Notificações.'),
      ));
      return;
    }
    await consent.set(Consent.notifications, true);
    final data = ref.read(financeProvider).valueOrNull;
    if (data != null) await reminders.reschedule(data);
    messenger.showSnackBar(const SnackBar(content: Text('Lembretes ativados.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final consents = ref.watch(consentProvider);
    final controller = ref.read(consentProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(FtSpace.md, FtSpace.md, FtSpace.md, FtSpace.xs),
          child: Text('Privacidade e permissões', style: theme.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FtSpace.md),
          child: Text(
            'O FINTRACK pede cada acesso só quando é preciso e explica porquê. '
            'Desligar retira o consentimento; da próxima vez volta a perguntar.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Lembretes'),
          subtitle: const Text('Compromissos a vencer e Kixikila, sem valores no ecrã bloqueado.'),
          value: consents[Consent.notifications] ?? false,
          onChanged: (v) => _toggleNotifications(context, ref, v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.photo_library_outlined),
          title: const Text('Fotografias'),
          subtitle: const Text('Só a fotografia que escolher, para o perfil.'),
          value: consents[Consent.photos] ?? false,
          onChanged: (v) => v
              ? showModalBottomSheet<bool>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const ConsentSheet(consent: Consent.photos),
                ).then((ok) => ok == true ? controller.set(Consent.photos, true) : null)
              : controller.set(Consent.photos, false),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.folder_open_outlined),
          title: const Text('Ficheiros'),
          subtitle: const Text('Só o ficheiro que escolher, para importar.'),
          value: consents[Consent.files] ?? false,
          onChanged: (v) => v
              ? showModalBottomSheet<bool>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const ConsentSheet(consent: Consent.files),
                ).then((ok) => ok == true ? controller.set(Consent.files, true) : null)
              : controller.set(Consent.files, false),
        ),
      ],
    );
  }
}
