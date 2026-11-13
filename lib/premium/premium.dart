import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/session.dart';
import 'billing.dart';

/// O que o Premium desbloqueia. A segurança (PIN, biometria, cifra, AI Guard,
/// cópias e sincronização) é sempre grátis.
enum PremiumFeature {
  ask('Pergunte ao FINTRACK'),
  pulse('Pulso financeiro'),
  trends('Tendências e observações'),
  smartEntry('Smart Entry'),
  pdf('Relatórios em PDF');

  const PremiumFeature(this.label);
  final String label;
}

class PremiumState {
  const PremiumState({
    this.loaded = false,
    this.until,
    this.productId,
    this.trialEnds,
    this.storeAvailable = false,
    this.products = const [],
    this.busy = false,
    this.message,
  });

  final bool loaded;

  /// Fim do período pago confirmado pela loja.
  final DateTime? until;
  final String? productId;

  /// Fim da experiência grátis.
  final DateTime? trialEnds;
  final bool storeAvailable;
  final List<PremiumProduct> products;
  final bool busy;
  final String? message;

  bool get subscribed => until != null && DateTime.now().isBefore(until!);
  bool get inTrial => !subscribed && trialEnds != null && DateTime.now().isBefore(trialEnds!);
  bool get unlocked => subscribed || inTrial;

  int get trialDaysLeft {
    final end = trialEnds;
    if (end == null || !inTrial) return 0;
    return (end.difference(DateTime.now()).inHours / 24).ceil();
  }

  PremiumState copyWith({
    bool? loaded,
    DateTime? until,
    String? productId,
    DateTime? trialEnds,
    bool? storeAvailable,
    List<PremiumProduct>? products,
    bool? busy,
    String? message,
    bool clearMessage = false,
  }) =>
      PremiumState(
        loaded: loaded ?? this.loaded,
        until: until ?? this.until,
        productId: productId ?? this.productId,
        trialEnds: trialEnds ?? this.trialEnds,
        storeAvailable: storeAvailable ?? this.storeAvailable,
        products: products ?? this.products,
        busy: busy ?? this.busy,
        message: clearMessage ? null : message ?? this.message,
      );
}

class PremiumController extends Notifier<PremiumState> {
  static const trialDays = 14;
  static const _kTrialStart = 'premium.trialStart';
  static const _kUntil = 'premium.until';
  static const _kProduct = 'premium.product';

  StreamSubscription<BillingEvent>? _sub;

  @override
  PremiumState build() {
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_load);
    return const PremiumState();
  }

  Billing get _billing => ref.read(billingProvider);

  Future<void> _load() async {
    // Guardado no cofre do sistema (Keychain/Keystore), fora da base de dados.
    final secrets = ref.read(secretStoreProvider);
    var start = int.tryParse(await secrets.read(_kTrialStart) ?? '');
    if (start == null) {
      start = DateTime.now().millisecondsSinceEpoch;
      await secrets.write(_kTrialStart, '$start');
    }
    final until = int.tryParse(await secrets.read(_kUntil) ?? '');
    state = state.copyWith(
      loaded: true,
      trialEnds: DateTime.fromMillisecondsSinceEpoch(start).add(const Duration(days: trialDays)),
      until: until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
      productId: await secrets.read(_kProduct),
    );
    _sub = _billing.events.listen(_onEvent);
    try {
      final ok = await _billing.available();
      final products = ok ? await _billing.products() : const <PremiumProduct>[];
      state = state.copyWith(storeAvailable: ok && products.isNotEmpty, products: products);
      // Renova a confirmação da subscrição em silêncio.
      if (ok && state.until != null) await _billing.restore();
    } catch (_) {
      state = state.copyWith(storeAvailable: false);
    }
  }

  Future<void> _onEvent(BillingEvent e) async {
    switch (e.status) {
      case BillingStatus.purchased:
      case BillingStatus.restored:
        // Validade local até à próxima confirmação da loja (com margem).
        final days = e.productId == PremiumIds.yearly ? 370 : 35;
        final until = DateTime.now().add(Duration(days: days));
        final secrets = ref.read(secretStoreProvider);
        await secrets.write(_kUntil, '${until.millisecondsSinceEpoch}');
        await secrets.write(_kProduct, e.productId);
        state = state.copyWith(
          until: until,
          productId: e.productId,
          busy: false,
          message: e.status == BillingStatus.purchased ? 'Bem-vindo ao FINTRACK Premium!' : 'Subscrição restaurada.',
        );
      case BillingStatus.pending:
        state = state.copyWith(busy: true, message: 'Pagamento pendente. Assim que for confirmado, o Premium abre.');
      case BillingStatus.canceled:
        state = state.copyWith(busy: false, clearMessage: true);
      case BillingStatus.error:
        state = state.copyWith(busy: false, message: e.message ?? 'Não foi possível concluir a compra.');
    }
  }

  Future<void> buy(String productId) async {
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await _billing.buy(productId);
    } catch (_) {
      state = state.copyWith(busy: false, message: 'Não foi possível abrir a loja. Tente de novo.');
    }
  }

  Future<void> restore() async {
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await _billing.restore();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!state.subscribed) state = state.copyWith(message: 'Não encontrámos nenhuma subscrição nesta conta da loja.');
    } catch (_) {
      state = state.copyWith(message: 'Não foi possível contactar a loja.');
    } finally {
      state = state.copyWith(busy: false);
    }
  }
}

final premiumProvider = NotifierProvider<PremiumController, PremiumState>(PremiumController.new);
