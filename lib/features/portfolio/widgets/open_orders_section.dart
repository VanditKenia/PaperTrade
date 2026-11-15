import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../domain/models/pending_order.dart';
import '../../../domain/models/trade.dart';
import '../../../domain/trade_errors.dart';
import '../../stock_detail/widgets/order_sheet.dart';
import '../portfolio_provider.dart';

/// Open limit/stop orders with Cancel (UI_UX.md §3.5). Hidden when none.
class OpenOrdersSection extends ConsumerWidget {
  const OpenOrdersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final orders = ref.watch(portfolioProvider.select((p) => p.orders));
    if (orders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text('Open orders', style: text.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(
            'Orders only execute while the app is open.',
            style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        for (final o in orders) _OrderTile(key: ValueKey(o.id), order: o),
        const Divider(height: 24),
      ],
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({super.key, required this.order});

  final PendingOrder order;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(portfolioProvider.notifier).cancelOrder(order.id);
      messenger.showSnackBar(const SnackBar(content: Text('Order cancelled')));
    } on TradeError catch (e) {
      // Usually: it filled a moment before the tap.
      messenger.showSnackBar(SnackBar(content: Text(tradeErrorMessage(e))));
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not cancel the order')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final o = order;
    final reserves = o.side == TradeSide.buy
        ? formatCents(o.reservedCashCents)
        : formatQuantity(o.symbol, o.quantity);

    return ListTile(
      title: Text(
        '${orderLabel(o.side, o.type)} ${formatShares(o.quantity)} '
        '${o.symbol} @ ${formatCents(o.triggerPriceCents)}',
        style: text.bodyLarge?.merge(tabularFigures),
      ),
      subtitle: Text(
        'Reserves $reserves',
        style: text.labelMedium
            ?.merge(tabularFigures)
            .copyWith(color: AppColors.textSecondary),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel order',
        onPressed: () => _cancel(context, ref),
      ),
    );
  }
}
