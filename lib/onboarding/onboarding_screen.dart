import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../design/backdrop.dart';
import '../design/country_photos.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../home/account_form.dart';
import '../security/session.dart';

/// Onboarding em três passos curtos: nome, moeda principal, primeira conta.
/// O PIN já foi criado antes, porque é ele que liberta a chave da base cifrada.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _steps = 3;

  int _step = 0;
  final _name = TextEditingController();
  String? _nameError;
  Currency _currency = Currency.aoa;
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _nextFromName() {
    final name = NameRules.clean(_name.text);
    setState(() {
      _nameError = name == null ? 'Escreva o seu nome.' : null;
      if (name != null) _step = 1;
    });
  }

  Future<void> _finish(Account account) async {
    final name = NameRules.clean(_name.text)!;
    try {
      await ref.read(sessionProvider.notifier).completeOnboarding(
            Profile(name: name, mainCurrency: _currency),
            account,
          );
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'Não foi possível guardar. Tente de novo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (title, subtitle, body) = switch (_step) {
      0 => (
          'Como se chama?',
          'Bem-vindo ao FINTRACK. Vamos preparar tudo em menos de um minuto.',
          _NameStep(controller: _name, error: _nameError, onDone: _nextFromName),
        ),
      1 => (
          'Moeda principal',
          'Os totais aparecem nesta moeda. Pode ter contas noutras moedas.',
          _CurrencyStep(
            selected: _currency,
            onChanged: (c) => setState(() => _currency = c),
          ),
        ),
      _ => (
          'Primeira conta',
          'Pode ser o banco, a carteira ou o dinheiro em casa. Depois junta as outras.',
          AccountForm(
            defaultCurrency: _currency,
            allowCurrencyChoice: false,
            submitLabel: 'Começar',
            onSubmit: _finish,
          ),
        ),
    };

    // No passo da moeda, o fundo mostra uma maravilha da região escolhida.
    final countryPhoto = photosFor(_currency).firstOrNull?.asset;
    final asset = switch (_step) {
      0 => FtImage.savings.asset,
      1 => countryPhoto ?? FtImage.shopping.asset,
      _ => FtImage.payment.asset,
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: FtBackdrop.asset(
        asset: asset,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: _step == 0
              ? null
              : IconButton(
                  tooltip: 'Voltar',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _step--),
                ),
          automaticallyImplyLeading: false,
          title: Text('Passo ${_step + 1} de $_steps'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: (_step + 1) / _steps),
          ),
        ),
        // O botão de avançar fica sempre visível, ao alcance do polegar.
        bottomNavigationBar: _step == 2
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(FtSpace.md),
                  child: FilledButton(
                    onPressed: _step == 0 ? _nextFromName : () => setState(() => _step = 2),
                    child: const Text('Continuar'),
                  ),
                ),
              ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(FtSpace.lg),
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: FtSpace.sm),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FtSpace.lg),
              body,
              if (_saveError != null) ...[
                const SizedBox(height: FtSpace.md),
                Text(_saveError!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({required this.controller, required this.error, required this.onDone});

  final TextEditingController controller;
  final String? error;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('profile-name'),
          controller: controller,
          autofocus: true,
          maxLength: NameRules.maxLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onDone(),
          decoration: InputDecoration(
            labelText: 'Nome',
            errorText: error,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _CurrencyStep extends StatelessWidget {
  const _CurrencyStep({required this.selected, required this.onChanged});

  final Currency selected;
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<Currency>(
          groupValue: selected,
          onChanged: (c) {
            if (c != null) onChanged(c);
          },
          child: Column(
            children: [
              for (final c in Currency.supported)
                RadioListTile<Currency>(
                  value: c,
                  title: Text(currencyName(c)),
                  subtitle: Text('${c.code} · ${c.symbol} · ${currencyRegion(c)}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
