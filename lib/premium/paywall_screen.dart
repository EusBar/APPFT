import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/backdrop.dart';
import '../design/tokens.dart';
import 'billing.dart';
import 'premium.dart';

/// Página de subscrição: o que inclui, preços da loja e restauro.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature});

  /// Função que levou o utilizador até aqui (para o título).
  final PremiumFeature? feature;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selected = PremiumIds.yearly;

  static const _benefits = [
    (Icons.forum_outlined, 'Pergunte ao FINTRACK', 'Respostas na hora sobre gastos, saldos e prazos.'),
    (Icons.monitor_heart_outlined, 'Pulso financeiro', 'A nota do seu mês, com o porquê de cada ponto.'),
    (Icons.show_chart_rounded, 'Tendências e observações', 'Curvas de 6 meses, ritmo, projeções e alertas.'),
    (Icons.bolt_rounded, 'Smart Entry', 'Escreva ou cole o SMS do banco: o movimento prepara-se sozinho.'),
    (Icons.picture_as_pdf_outlined, 'Relatórios em PDF', 'Relatórios do mês prontos a partilhar.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final p = ref.watch(premiumProvider);
    ref.listen(premiumProvider.select((s) => s.message), (_, m) {
      if (m != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    });

    final monthly = p.products.where((x) => !x.yearly).firstOrNull;
    final yearly = p.products.where((x) => x.yearly).firstOrNull;
    final saving = monthly != null && yearly != null && monthly.rawPrice > 0
        ? (100 - yearly.rawPrice * 100 / (monthly.rawPrice * 12)).round()
        : null;

    return FtBackdrop(
      image: FtImage.analytics,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.xl),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [colors.aiAccent, theme.colorScheme.primary]),
                boxShadow: [BoxShadow(color: colors.aiAccent.withValues(alpha: 0.45), blurRadius: 30)],
              ),
              child: const Icon(Icons.workspace_premium_rounded, size: 34, color: Colors.white),
            ),
            const SizedBox(height: FtSpace.md),
            Text('FINTRACK Premium', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: FtSpace.xs),
            Text(
              widget.feature == null
                  ? 'A inteligência do FINTRACK, sem limites.'
                  : '${widget.feature!.label} faz parte do Premium.',
              style: theme.textTheme.bodyLarge,
            ),
            if (p.subscribed) ...[
              const SizedBox(height: FtSpace.md),
              _Pill(color: colors.income, text: 'Premium ativo. Obrigado por apoiar o FINTRACK!'),
            ] else if (p.inTrial) ...[
              const SizedBox(height: FtSpace.md),
              _Pill(
                color: colors.aiAccent,
                text: 'Experiência grátis: ${p.trialDaysLeft} ${p.trialDaysLeft == 1 ? 'dia' : 'dias'} restantes.',
              ),
            ],
            const SizedBox(height: FtSpace.lg),
            for (final (icon, title, text) in _benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: FtSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.aiAccent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: colors.aiAccent, size: 20),
                    ),
                    const SizedBox(width: FtSpace.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(text, style: muted),
                      ]),
                    ),
                  ],
                ),
              ),
            Row(children: [
              Icon(Icons.lock_outline, size: 16, color: colors.income),
              const SizedBox(width: FtSpace.xs),
              Expanded(
                child: Text(
                  'Sempre grátis: PIN, biometria, cifra, AI Guard, cópias de segurança e sincronização.',
                  style: muted,
                ),
              ),
            ]),
            const SizedBox(height: FtSpace.lg),
            if (!p.storeAvailable)
              Container(
                padding: const EdgeInsets.all(FtSpace.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(FtRadius.lg),
                ),
                child: Text(
                  'As subscrições ficam disponíveis quando o FINTRACK estiver na Google Play e na App Store. '
                  'Até lá, todas as funções Premium estão abertas durante a experiência grátis.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else if (!p.subscribed) ...[
              for (final prod in [?yearly, ?monthly])
                Padding(
                  padding: const EdgeInsets.only(bottom: FtSpace.sm),
                  child: _PlanCard(
                    product: prod,
                    selected: _selected == prod.id,
                    badge: prod.yearly && saving != null && saving > 0 ? 'Poupe $saving%' : null,
                    onTap: () => setState(() => _selected = prod.id),
                  ),
                ),
              const SizedBox(height: FtSpace.sm),
              FilledButton(
                key: const Key('paywall-buy'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: p.busy ? null : () => ref.read(premiumProvider.notifier).buy(_selected),
                child: p.busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Continuar'),
              ),
              const SizedBox(height: FtSpace.sm),
              Text(
                'Renova automaticamente. Cancele quando quiser nas subscrições da Google Play ou da App Store.',
                style: muted,
                textAlign: TextAlign.center,
              ),
            ],
            if (p.storeAvailable)
              TextButton(
                onPressed: p.busy ? null : () => ref.read(premiumProvider.notifier).restore(),
                child: const Text('Restaurar compras'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.product, required this.selected, required this.onTap, this.badge});

  final PremiumProduct product;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(FtRadius.lg),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(FtSpace.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: selected ? 0.95 : 0.7),
          borderRadius: BorderRadius.circular(FtRadius.lg),
          border: Border.all(color: selected ? colors.aiAccent : theme.colorScheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? colors.aiAccent : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: FtSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.yearly ? 'Anual' : 'Mensal', style: theme.textTheme.titleMedium),
              Text('${product.price} / ${product.yearly ? 'ano' : 'mês'}', style: theme.textTheme.bodyMedium),
            ]),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colors.income, borderRadius: BorderRadius.circular(20)),
              child: Text(badge!, style: theme.textTheme.labelMedium?.copyWith(color: Colors.black)),
            ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      );
}

/// Mostra [child] com Premium (ou na experiência grátis); senão, um convite.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({super.key, required this.feature, required this.child, this.teaser});

  final PremiumFeature feature;
  final Widget child;

  /// Texto curto do que a função faz, mostrado no convite.
  final String? teaser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(premiumProvider);
    if (!p.loaded || p.unlocked) return child;
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    return InkWell(
      key: Key('locked-${feature.name}'),
      borderRadius: BorderRadius.circular(28),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PaywallScreen(feature: feature)),
      ),
      child: Container(
        padding: const EdgeInsets.all(FtSpace.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.aiAccent.withValues(alpha: 0.16), theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.75)],
          ),
          border: Border.all(color: colors.aiAccent.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(Icons.workspace_premium_rounded, color: colors.aiAccent, size: 30),
          const SizedBox(width: FtSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(feature.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (teaser != null) Text(teaser!, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text('Desbloquear com Premium →',
                  style: theme.textTheme.labelLarge?.copyWith(color: colors.aiAccent, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}
