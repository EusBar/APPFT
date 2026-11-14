import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/cloud_api.dart';
import '../cloud/cloud_controller.dart';
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
    // Ao entrar numa conta, a subscrição guardada no servidor vale aqui também.
    ref.listen(cloudProvider.select((c) => c.email), (_, email) {
      if (email != null) _refreshFromServer();
    });
    return const PremiumState();
  }

  Future<void> _refreshFromServer() async {
    try {
      final sub = await ref.read(cloudProvider.notifier).serverSubscription();
      if (sub == null) return;
      await _remember(sub.productId, sub.expiresAt);
    } catch (_) {
      // Sem rede: vale a última confirmação guardada.
    }
  }

  Future<void> _remember(String productId, DateTime until) async {
    final secrets = ref.read(secretStoreProvider);
    await secrets.write(_kUntil, '${until.millisecondsSinceEpoch}');
    await secrets.write(_kProduct, productId);
    state = state.copyWith(until: until, productId: productId);
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
        DateTime? until;
        var productId = e.productId;
        final data = e.data;
        if (ref.read(cloudProvider).signedIn && data != null && data.isNotEmpty) {
          // O servidor pergunta à loja se a compra é verdadeira e até quando.
          try {
            final sub = await ref.read(cloudProvider.notifier).verifyPurchase(e.platform, data);
            if (sub == null) {
              state = state.copyWith(busy: false, message: 'A loja não confirmou esta compra.');
              return;
            }
            until = sub.expiresAt;
            productId = sub.productId;
          } on CloudException catch (x) {
            if (x.code != 'not_configured') {
              state = state.copyWith(busy: false, message: x.message);
              return;
            }
          }
        }
        // Sem servidor ligado à loja: validade local até à próxima confirmação.
        until ??= DateTime.now().add(Duration(days: e.productId == PremiumIds.yearly ? 370 : 35));
        await _remember(productId, until);
        state = state.copyWith(
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
