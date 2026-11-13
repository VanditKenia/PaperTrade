import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/api_errors.dart';
import '../../domain/models/quote.dart';
import '../../domain/models/stock.dart';
import '../watchlist/watchlist_provider.dart';
import 'stock_detail_provider.dart';
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(stock.name, style: secondary),
          const SizedBox(height: 8),
          Text(
            price == null ? '—' : formatCents(price),
            style: text.displaySmall?.merge(tabularFigures),
          ),
          if (price != null && prevClose > 0)
            Text(
              '${formatChange(change, prevClose)} today',
              style: text.bodyLarge
                  ?.merge(tabularFigures)
                  .copyWith(color: changeColor(change)),
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
        ],
      ),
      bottomNavigationBar: const _TradeBar(),
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

/// Sticky Buy/Sell bar. Placeholder until trading arrives in Step 5.
class _TradeBar extends StatelessWidget {
  const _TradeBar();

  @override
  Widget build(BuildContext context) {
    void comingSoon() => ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Trading is coming soon')));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: OutlinedButton(
                // Disabled: no holdings exist until Step 5 (UI_UX.md §3.3).
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('SELL'),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: comingSoon,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('BUY'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
