import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/price_stream_service.dart';
import '../portfolio/portfolio_provider.dart';
import 'watchlist_provider.dart';

/// Keeps the WebSocket subscribed to watchlist + held symbols. Held symbols
/// stay subscribed after leaving the watchlist, so P&L keeps updating.
///
/// Lives apart from the price providers on purpose: this watches the
/// portfolio, and the portfolio's consumers read prices. Nothing reads this
/// back, so no cycle. Kept alive by AppShell.
final priceSubscriptionsProvider = Provider<void>((ref) {
  final service = ref.watch(priceStreamServiceProvider);
  ref.listen(
    watchlistProvider,
    (_, stocks) => service.setSymbols(stocks.map((s) => s.symbol)),
    fireImmediately: true,
  );
  ref.listen(
    portfolioProvider.select((p) => p.holdings.keys.toList()),
    (_, symbols) => service.setSymbols(symbols, source: 'holdings'),
    fireImmediately: true,
  );
});
