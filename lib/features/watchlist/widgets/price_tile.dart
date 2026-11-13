import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/api_errors.dart';
import '../../../domain/models/quote.dart';
import '../../../domain/models/stock.dart';
import '../watchlist_provider.dart';

/// One watchlist row: symbol and name on the left, price and day change on
/// the right. Watches only its own symbol's quote.
class PriceTile extends ConsumerWidget {
  const PriceTile({super.key, required this.stock});

  final Stock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final quote = ref.watch(quoteProvider(stock.symbol));

    return ListTile(
      minTileHeight: 64,
      title: Text(
        stock.symbol,
        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        stock.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
      trailing: quote.when(
        data: (q) => _Price(q),
        loading: () => const _PriceSkeleton(),
        error: (e, _) => SizedBox(
          width: 140,
          child: Text(
            errorMessage(e),
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price(this.quote);

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final change = quote.changeCents;
    // Arrow and sign as well as color, so gains/losses aren't color-only.
    final (color, arrow, sign) = change > 0
        ? (AppColors.gain, '▲ ', '+')
        : change < 0
        ? (AppColors.loss, '▼ ', '-')
        : (AppColors.textSecondary, '', '');

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatCents(quote.currentCents),
          style: text.bodyLarge?.merge(tabularFigures),
        ),
        Text(
          '$arrow$sign${formatCents(change.abs())} '
          '(${formatPercent(quote.changePercent)})',
          style: text.labelMedium?.merge(tabularFigures).copyWith(color: color),
        ),
      ],
    );
  }
}

class _PriceSkeleton extends StatelessWidget {
  const _PriceSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
      width: width,
      height: 14,
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 6,
      children: [bar(72), bar(96)],
    );
  }
}
