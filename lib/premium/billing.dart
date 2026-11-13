import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Um plano à venda na loja (preço já no formato e moeda do utilizador).
class PremiumProduct {
  const PremiumProduct({required this.id, required this.price, required this.rawPrice, required this.yearly});

  final String id;
  final String price;
  final double rawPrice;
  final bool yearly;
}

enum BillingStatus { purchased, restored, pending, canceled, error }

class BillingEvent {
  const BillingEvent(this.productId, this.status, {this.message});
  final String productId;
  final BillingStatus status;
  final String? message;
}

/// Google Play / App Store, atrás de uma interface simples (e testável).
abstract interface class Billing {
  Future<bool> available();
  Future<List<PremiumProduct>> products();
  Future<void> buy(String productId);
  Future<void> restore();
  Stream<BillingEvent> get events;
}

/// Identificadores das subscrições, iguais na Google Play e na App Store.
abstract final class PremiumIds {
  static const monthly = 'fintrack_premium_monthly';
  static const yearly = 'fintrack_premium_yearly';
  static const all = {monthly, yearly};
}

class StoreBilling implements Billing {
  StoreBilling() {
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object _) {});
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  final _events = StreamController<BillingEvent>.broadcast();
  final Map<String, ProductDetails> _details = {};
  // ignore: unused_field
  late final StreamSubscription<List<PurchaseDetails>> _sub;

  @override
  Stream<BillingEvent> get events => _events.stream;

  @override
  Future<bool> available() => _iap.isAvailable();

  @override
  Future<List<PremiumProduct>> products() async {
    final r = await _iap.queryProductDetails(PremiumIds.all);
    for (final d in r.productDetails) {
      _details[d.id] = d;
    }
    return [
      for (final d in r.productDetails)
        PremiumProduct(id: d.id, price: d.price, rawPrice: d.rawPrice, yearly: d.id == PremiumIds.yearly),
    ];
  }

  @override
  Future<void> buy(String productId) async {
    final d = _details[productId];
    if (d == null) throw StateError('Produto indisponível');
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: d));
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      final status = switch (p.status) {
        PurchaseStatus.purchased => BillingStatus.purchased,
        PurchaseStatus.restored => BillingStatus.restored,
        PurchaseStatus.pending => BillingStatus.pending,
        PurchaseStatus.canceled => BillingStatus.canceled,
        PurchaseStatus.error => BillingStatus.error,
      };
      _events.add(BillingEvent(p.productID, status, message: p.error?.message));
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }
}

/// Para testes e enquanto não há loja: compra imediata.
@visibleForTesting
class MemoryBilling implements Billing {
  final _events = StreamController<BillingEvent>.broadcast();
  bool storeAvailable = true;
  List<PremiumProduct> catalog = const [
    PremiumProduct(id: PremiumIds.monthly, price: '1 500,00 Kz', rawPrice: 1500, yearly: false),
    PremiumProduct(id: PremiumIds.yearly, price: '12 000,00 Kz', rawPrice: 12000, yearly: true),
  ];
  final List<String> bought = [];

  @override
  Stream<BillingEvent> get events => _events.stream;

  @override
  Future<bool> available() async => storeAvailable;

  @override
  Future<List<PremiumProduct>> products() async => storeAvailable ? catalog : const [];

  @override
  Future<void> buy(String productId) async {
    bought.add(productId);
    _events.add(BillingEvent(productId, BillingStatus.purchased));
  }

  @override
  Future<void> restore() async {
    for (final id in bought) {
      _events.add(BillingEvent(id, BillingStatus.restored));
    }
  }
}

final billingProvider = Provider<Billing>((ref) => StoreBilling());
