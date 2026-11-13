import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/api_errors.dart';
import '../../../domain/models/stock.dart';
import '../../stock_detail/stock_detail_screen.dart';
import '../watchlist_provider.dart';

/// One watchlist row: symbol and name on the left, price and day change on
/// the right. Shows the live price when one has arrived, otherwise the quote.
class PriceTile extends ConsumerWidget {
  const PriceTile({super.key, required this.stock});

  final Stock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // select() narrows the whole price map down to this symbol's price, so
    // this tile rebuilds only when *its* price changes, not on every tick of
    // every other symbol.
    final live = ref.watch(
      livePricesProvider.select((prices) => prices.value?[stock.symbol]),
    );
    final quote = ref.watch(quoteProvider(stock.symbol));
    final q = quote.value;

    return ListTile(
      minTileHeight: 64,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StockDetailScreen(stock: stock),
        ),
      ),
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
      trailing: live != null || q != null
          ? _Price(
              priceCents: live ?? q!.currentCents,
              prevCloseCents: q?.prevCloseCents ?? 0,
            )
          : quote.isLoading
          ? const _PriceSkeleton()
          : SizedBox(
              width: 140,
              child: Text(
                errorMessage(quote.error ?? const UnknownError()),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
    );
  }
}

/// Price plus change vs previous close, with a 300 ms tint when it ticks.
class _Price extends StatefulWidget {
  const _Price({required this.priceCents, required this.prevCloseCents});

  final int priceCents;
  final int prevCloseCents; // 0 = unknown, change line hidden

  @override
  State<_Price> createState() => _PriceState();
}

class _PriceState extends State<_Price> with SingleTickerProviderStateMixin {
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  Color _flashColor = AppColors.gain;

  @override
  void didUpdateWidget(_Price old) {
    super.didUpdateWidget(old);
    if (widget.priceCents != old.priceCents) {
      _flashColor = widget.priceCents > old.priceCents
          ? AppColors.gain
          : AppColors.loss;
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final price = widget.priceCents;
    final prevClose = widget.prevCloseCents;
    final change = price - prevClose;

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          // Fades from a 30% tint back to transparent over the 300 ms.
          color: _flash.isAnimating
              ? _flashColor.withValues(alpha: 0.3 * (1 - _flash.value))
              : null,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatCents(price),
              style: text.bodyLarge?.merge(tabularFigures),
            ),
            if (prevClose > 0)
              Text(
                formatChange(change, prevClose),
                style: text.labelMedium
                    ?.merge(tabularFigures)
                    .copyWith(color: changeColor(change)),
              ),
          ],
        ),
      ),
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
