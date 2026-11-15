import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/models/price_point.dart';
import '../../domain/models/trade.dart';
import '../stock_detail/widgets/price_chart.dart';
import '../watchlist/widgets/offline_banner.dart';
import 'stats_provider.dart';

/// Performance numbers and portfolio value over time (UI_UX.md §3.5b).
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final s = ref.watch(performanceStatsProvider);
    const secondary = TextStyle(color: AppColors.textSecondary);

    Widget stat(String label, String value, {Color? color}) => ListTile(
      dense: true,
      title: Text(label, style: secondary),
      trailing: Text(
        value,
        style: text.bodyLarge?.merge(tabularFigures).copyWith(color: color),
      ),
    );

    String money(int? cents) => cents == null ? '—' : formatSignedCents(cents);
    String trade(Trade? t) => t == null
        ? '—'
        : '${formatSignedCents(t.realizedPnlCents!)} · ${t.symbol}';

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const _ValueChartCard(),
                if (s.tradeCount == 0)
                  const _Hint(
                    'No trades yet — stats appear after your first '
                    'trade.',
                  )
                else if (s.sellCount == 0)
                  const _Hint(
                    'Win rate and P&L stats appear after your first '
                    'sell.',
                  ),
                stat(
                  'Realized P&L',
                  formatSignedCents(s.totalRealizedPnlCents),
                  color: changeColor(s.totalRealizedPnlCents),
                ),
                stat('Trades', '${s.tradeCount}'),
                stat(
                  'Win rate',
                  s.winRate == null
                      ? '—'
                      : '${s.winRate!.toStringAsFixed(1)}% '
                            '(${s.winCount}/${s.sellCount})',
                ),
                stat(
                  'Average win',
                  money(s.averageWinCents),
                  color: s.averageWinCents == null ? null : AppColors.gain,
                ),
                stat(
                  'Average loss',
                  money(s.averageLossCents),
                  color: s.averageLossCents == null ? null : AppColors.loss,
                ),
                stat(
                  'Best trade',
                  trade(s.bestTrade),
                  color: s.bestTrade == null
                      ? null
                      : changeColor(s.bestTrade!.realizedPnlCents!),
                ),
                stat(
                  'Worst trade',
                  trade(s.worstTrade),
                  color: s.worstTrade == null
                      ? null
                      : changeColor(s.worstTrade!.realizedPnlCents!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueChartCard extends ConsumerWidget {
  const _ValueChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final history = ref.watch(valueHistoryProvider);
    final points = [
      for (final s in history)
        PricePoint(time: s.time, priceCents: s.valueCents),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Portfolio value', style: text.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              // A line needs two points.
              child: points.length < 2
                  ? Center(
                      child: Text(
                        'Not enough data yet — the chart fills in as you '
                        'trade and keep the app open.',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : PriceChart(
                      points: points,
                      color: changeColor(
                        points.last.priceCents - points.first.priceCents,
                      ),
                      formatTime: (t) =>
                          DateFormat.yMMMd().add_jm().format(t.toLocal()),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
    ),
  );
}
