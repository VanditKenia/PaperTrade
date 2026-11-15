import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_shell.dart';
import '../../core/animated_number.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../stats/stats_screen.dart';
import '../watchlist/widgets/offline_banner.dart';
import 'portfolio_provider.dart';
import 'widgets/holding_tile.dart';
import 'widgets/open_orders_section.dart';

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(
      portfolioProvider.select((p) => p.holdings.values.toList()),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: 'Stats',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const _SummaryCard(),
                const OpenOrdersSection(),
                if (holdings.isEmpty)
                  const _EmptyState()
                else
                  for (final h in holdings) ...[
                    HoldingTile(key: ValueKey(h.symbol), holding: h),
                    const Divider(height: 1),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header with totals. Its own widget, so live price changes rebuild just
/// this card and the affected tiles, not the whole list.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final s = ref.watch(portfolioSummaryProvider);
    final returnColor = changeColor(s.totalReturnCents);
    final arrow = s.totalReturnCents > 0
        ? '▲ '
        : (s.totalReturnCents < 0 ? '▼ ' : '');
    const label = TextStyle(color: AppColors.textSecondary);

    Widget stat(String name, int cents) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: text.labelMedium?.merge(label)),
          AnimatedNumber(
            formatCents(cents),
            style: text.bodyLarge,
            alignment: Alignment.centerLeft,
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total value', style: text.labelMedium?.merge(label)),
            AnimatedNumber(
              formatCents(s.portfolioValueCents),
              style: text.displaySmall,
              alignment: Alignment.centerLeft,
            ),
            AnimatedNumber(
              '$arrow${formatSignedCents(s.totalReturnCents)} '
              '(${formatPercent(s.totalReturnPercent)}) total return',
              style: text.bodyLarge?.copyWith(color: returnColor),
              alignment: Alignment.centerLeft,
            ),
            Text(
              'Starting balance ${formatCents(s.startingCashCents)}',
              style: text.labelMedium?.merge(label).merge(tabularFigures),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                stat('Cash', s.cashCents),
                stat('Invested', s.investedCents),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(
            Icons.pie_chart_outline,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No holdings yet — buy your first stock',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => ref
                .read(tabIndexProvider.notifier)
                .select(TabIndexNotifier.watchlist),
            child: const Text('Go to Watchlist'),
          ),
        ],
      ),
    );
  }
}
