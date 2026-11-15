import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/order_matcher.dart';
import '../../domain/trade_errors.dart';
import '../watchlist/watchlist_provider.dart';
import 'portfolio_provider.dart';

/// Fills open limit/stop orders when a live tick meets their price.
///
/// Watches prices and reads the portfolio, then hands the tick price to
/// the portfolio notifier. That notifier never reads prices, and nothing
/// reads this provider, so there is no cycle. Kept alive by AppShell:
/// orders only fill while the app is open.
final orderMatcherProvider = Provider<void>((ref) {
  // Orders with a fill already queued; a later snapshot mustn't queue a
  // second fill for the same order while the first is saving.
  final inFlight = <String>{};

  Future<void> fill(String orderId, int priceCents) async {
    final portfolio = ref.read(portfolioProvider.notifier);
    try {
      await portfolio.fillOrder(orderId, priceCents: priceCents);
    } on OrderNotFound {
      // Cancelled by the user while the fill was queued. Nothing to do.
    } on TradeError catch (e) {
      // Can never fill (e.g. a tiny order now worth 0¢): cancel it so its
      // reservation is released instead of retrying on every tick.
      if (kDebugMode) debugPrint('Order $orderId cancelled: $e');
      await portfolio.cancelOrder(orderId).catchError((_) {});
    } catch (e) {
      // Save failed: the order stays open and the next tick retries.
      if (kDebugMode) debugPrint('Filling order $orderId failed: $e');
    } finally {
      inFlight.remove(orderId);
    }
  }

  ref.listen(livePricesProvider, (previous, next) {
    final prices = next.value;
    if (prices == null) return;
    final ticks = OrderMatcher.ticks(previous?.value ?? const {}, prices);
    final orders = ref.read(portfolioProvider).orders;
    for (final (order, price) in OrderMatcher.triggered(orders, ticks)) {
      if (inFlight.add(order.id)) unawaited(fill(order.id, price));
    }
  });
});
