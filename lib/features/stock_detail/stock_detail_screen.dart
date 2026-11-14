import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/animated_number.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/api_errors.dart';
import '../../domain/models/quote.dart';
import '../../domain/models/stock.dart';
import '../../domain/models/trade.dart';
import '../portfolio/portfolio_provider.dart';
import '../watchlist/watchlist_provider.dart';
import '../watchlist/widgets/offline_banner.dart';
import 'stock_detail_provider.dart';
import 'widgets/order_sheet.dart';
import 'widgets/price_chart.dart';

class StockDetailScreen extends ConsumerWidget {
  const StockDetailScreen({super.key, required this.stock});

  final Stock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final symbol = stock.symbol;
    final quote = ref.watch(quoteProvider(symbol));
    final live = ref.watch(livePricesProvider.select((p) => p.value?[symbol]));
    final points = ref.watch(chartPointsProvider(symbol)).visible;
    final watched = ref.watch(
      watchlistProvider.select((l) => l.any((s) => s.symbol == symbol)),
    );

    // Crypto trades 24/7, so the US market's hours don't apply to it.
    final marketClosed =
        !isCrypto(symbol) && ref.watch(marketOpenProvider).value == false;

    final q = quote.value;
    final price = live ?? q?.currentCents;
    final prevClose = q?.prevCloseCents ?? 0;
    final change = price == null || prevClose == 0 ? 0 : price - prevClose;
    final secondary = text.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(symbol),
        actions: [
          IconButton(
            icon: Icon(watched ? Icons.star : Icons.star_border),
            color: watched ? AppColors.warning : null,
            tooltip: watched ? 'Remove from watchlist' : 'Add to watchlist',
            onPressed: () {
              final watchlist = ref.read(watchlistProvider.notifier);
              watched ? watchlist.remove(symbol) : watchlist.add(stock);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(stock.name, style: secondary),
                const SizedBox(height: 8),
                AnimatedNumber(
                  price == null ? '—' : formatCents(price),
                  style: text.displaySmall,
                  alignment: Alignment.centerLeft,
                ),
                if (price != null && prevClose > 0)
                  AnimatedNumber(
                    '${formatChange(change, prevClose)} today',
                    style: text.bodyLarge?.copyWith(color: changeColor(change)),
                    alignment: Alignment.centerLeft,
                  ),
                if (price != null && marketClosed)
                  Text(
                    'Market closed · last price',
                    style: text.labelMedium?.copyWith(color: AppColors.warning),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 200,
                  child: points.isEmpty
                      ? Center(
                          child: quote.isLoading
                              ? const CircularProgressIndicator()
                              : Text('Waiting for price…', style: secondary),
                        )
                      : PriceChart(
                          pointsCents: points,
                          prevCloseCents: prevClose,
                          // Green/red by direction on the day, not the last tick.
                          color: change < 0 ? AppColors.loss : AppColors.gain,
                        ),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text('Live')),
                ),
                const SizedBox(height: 16),
                quote.when(
                  data: (q) => _DayStats(q),
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Text(errorMessage(e), style: secondary),
                ),
                const Divider(height: 32),
                _Position(symbol: symbol, priceCents: price),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _TradeBar(stock: stock, priceCents: price),
    );
  }
}

class _DayStats extends StatelessWidget {
  const _DayStats(this.quote);

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int cents) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            const Spacer(),
            Text(cents > 0 ? formatCents(cents) : '—', style: tabularFigures),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            stat('Open', quote.openCents),
            stat('High', quote.highCents),
          ],
        ),
        Row(
          children: [
            stat('Low', quote.lowCents),
            stat('Prev close', quote.prevCloseCents),
          ],
        ),
      ],
    );
  }
}

class _Position extends ConsumerWidget {
  const _Position({required this.symbol, required this.priceCents});

  final String symbol;
  final int? priceCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final holding = ref.watch(
      portfolioProvider.select((p) => p.holdings[symbol]),
    );
    if (holding == null) {
      return Text(
        'Your position: ${formatQuantity(symbol, 0)}',
        style: text.bodyLarge,
      );
    }
    final qty = holding.quantity;
    final price = priceCents;
    final pnl = price == null ? null : (price - holding.avgCostCents) * qty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          'Your position: ${formatQuantity(symbol, qty)}',
          style: text.bodyLarge,
        ),
        Text.rich(
          TextSpan(
            style: text.labelMedium?.merge(tabularFigures),
            children: [
              TextSpan(
                text: 'Avg cost ${formatCents(holding.avgCostCents)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (pnl != null)
                TextSpan(
                  text: ' · P&L ${formatSignedCents(pnl)}',
                  style: TextStyle(color: changeColor(pnl)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sticky Buy/Sell bar. Both are disabled offline or until a price is
/// known; Sell also needs shares to sell (UI_UX.md §3.3, APP_FLOW.md §5).
class _TradeBar extends ConsumerWidget {
  const _TradeBar({required this.stock, required this.priceCents});

  final Stock stock;
  final int? priceCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owns = ref.watch(
      portfolioProvider.select((p) => p.holdings.containsKey(stock.symbol)),
    );
    final offline = ref.watch(isOfflineProvider);
    final canTrade = priceCents != null && !offline;
    void open(TradeSide side) =>
        showOrderSheet(context, stock: stock, side: side);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!canTrade)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  offline ? 'Offline — trading paused' : 'Waiting for price…',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canTrade && owns
                        ? () => open(TradeSide.sell)
                        : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('SELL'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: canTrade ? () => open(TradeSide.buy) : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('BUY'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
