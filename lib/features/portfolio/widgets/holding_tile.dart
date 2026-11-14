import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../domain/models/holding.dart';
import '../../../domain/models/stock.dart';
import '../../../domain/portfolio_engine.dart';
import '../../stock_detail/stock_detail_screen.dart';
import '../../watchlist/watchlist_provider.dart';

/// One holding: symbol and size on the left, live price and P&L on the
/// right. Watches only its own symbol's price.
class HoldingTile extends ConsumerWidget {
  const HoldingTile({super.key, required this.holding});

  final Holding holding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final symbol = holding.symbol;
    final price = ref.watch(latestPriceProvider(symbol));
    // Holdings only store the symbol; borrow the name from the watchlist.
    final name = ref.watch(
      watchlistProvider.select(
        (l) => l.where((s) => s.symbol == symbol).firstOrNull?.name,
      ),
    );
    final secondary = text.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );

    return ListTile(
      minTileHeight: 64,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StockDetailScreen(
            stock: Stock(symbol: symbol, name: name ?? symbol),
          ),
        ),
      ),
      title: Text(
        symbol,
        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${holding.quantity} sh · avg ${formatCents(holding.avgCostCents)}',
        style: secondary?.merge(tabularFigures),
      ),
      trailing: price == null
          ? Text('—', style: secondary)
          : _PnL(holding: holding, priceCents: price),
    );
  }
}

class _PnL extends StatelessWidget {
  const _PnL({required this.holding, required this.priceCents});

  final Holding holding;
  final int priceCents;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pnl = PortfolioEngine.unrealizedPnl(holding, priceCents);
    final percent = PortfolioEngine.unrealizedPnlPercent(holding, priceCents);
    final arrow = pnl > 0 ? '▲ ' : (pnl < 0 ? '▼ ' : '');

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatCents(priceCents),
          style: text.bodyLarge?.merge(tabularFigures),
        ),
        Text(
          '$arrow${formatSignedCents(pnl)} (${formatPercent(percent)})',
          style: text.labelMedium
              ?.merge(tabularFigures)
              .copyWith(color: changeColor(pnl)),
        ),
      ],
    );
  }
}
