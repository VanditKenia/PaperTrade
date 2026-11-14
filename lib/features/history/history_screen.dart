import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_shell.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/models/trade.dart';
import 'history_provider.dart';

/// Every executed trade, grouped by day (UI_UX.md §3.6).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(tradeHistoryProvider);
    final header = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: days.isEmpty
          ? const _EmptyState()
          : ListView(
              children: [
                for (final d in days) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      DateFormat.yMMMEd().format(d.day),
                      style: header,
                    ),
                  ),
                  for (final t in d.trades) _TradeRow(trade: t),
                ],
              ],
            ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final Trade trade;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isBuy = trade.side == TradeSide.buy;
    final pnl = trade.realizedPnlCents;

    return ListTile(
      leading: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: (isBuy ? AppColors.accent : AppColors.warning).withValues(
            alpha: 0.2,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(
          isBuy ? 'BUY' : 'SELL',
          textAlign: TextAlign.center,
          style: text.labelMedium?.copyWith(
            color: isBuy ? AppColors.accent : AppColors.warning,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        '${trade.quantity} ${trade.symbol} @ ${formatCents(trade.priceCents)}',
        style: text.bodyLarge?.merge(tabularFigures),
      ),
      subtitle: Text(
        DateFormat.jm().format(trade.executedAt.toLocal()),
        style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
      trailing: pnl == null
          ? null
          : Text(
              formatSignedCents(pnl),
              style: text.bodyLarge
                  ?.merge(tabularFigures)
                  .copyWith(color: changeColor(pnl)),
            ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No trades yet',
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
      ),
    );
  }
}
