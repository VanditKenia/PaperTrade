import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/storage_error.dart';
import '../../../domain/models/stock.dart';
import '../../../domain/models/trade.dart';
import '../../../domain/trade_errors.dart';
import '../../portfolio/portfolio_provider.dart';
import '../../watchlist/watchlist_provider.dart';

Future<void> showOrderSheet(
  BuildContext context, {
  required Stock stock,
  required TradeSide side,
}) => showModalBottomSheet<void>(
  context: context,
  // Lets the sheet grow above the keyboard instead of being covered by it.
  isScrollControlled: true,
  builder: (_) => OrderSheet(stock: stock, side: side),
);

/// Buy/Sell form with a live preview (UI_UX.md §3.4). These checks are for
/// UX only; PortfolioEngine re-checks everything when the trade executes.
class OrderSheet extends ConsumerStatefulWidget {
  const OrderSheet({super.key, required this.stock, required this.side});

  final Stock stock;
  final TradeSide side;

  @override
  ConsumerState<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<OrderSheet> {
  final _qty = TextEditingController(text: '1');
  bool _submitting = false;
  String? _submitError; // set when the engine or the save rejects a trade

  bool get _isBuy => widget.side == TradeSide.buy;
  int get _quantity => int.tryParse(_qty.text) ?? 0;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _setQuantity(int q) {
    _qty.value = TextEditingValue(
      text: '$q',
      selection: TextSelection.collapsed(offset: '$q'.length),
    );
    setState(() => _submitError = null);
  }

  /// [priceCents] is the price on screen when Confirm was tapped, so the
  /// fill matches what the user saw.
  Future<void> _confirm(int priceCents) async {
    final symbol = widget.stock.symbol;
    final quantity = _quantity;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final portfolio = ref.read(portfolioProvider.notifier);
    setState(() => _submitting = true);

    final Trade trade;
    try {
      trade = _isBuy
          ? await portfolio.buy(symbol, quantity, priceCents: priceCents)
          : await portfolio.sell(symbol, quantity, priceCents: priceCents);
    } on TradeError catch (e) {
      _fail(tradeErrorMessage(e));
      return;
    } on StorageError catch (e, stack) {
      if (kDebugMode) debugPrint('Saving trade failed: $e\n$stack');
      _fail(
        kDebugMode ? 'Could not save: ${e.cause}' : 'Could not save the trade',
      );
      return;
    } catch (e) {
      // A bug, not a user problem: unblock the sheet, then rethrow so it is
      // reported with its real stack instead of being hidden.
      _fail(kDebugMode ? '$e' : 'Something went wrong. Try again');
      rethrow;
    }

    // The trade is saved. Nothing below is inside the try: an error here
    // must never say "Could not save", or the user would buy twice.
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(_tradeSummary(trade))));
    // Fire-and-forget: the trade is done, no reason to wait on a vibration.
    unawaited(HapticFeedback.mediumImpact());
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _submitError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final symbol = widget.stock.symbol;
    final price = ref.watch(latestPriceProvider(symbol));
    final cash = ref.watch(portfolioProvider.select((p) => p.wallet.cashCents));
    final holding = ref.watch(
      portfolioProvider.select((p) => p.holdings[symbol]),
    );
    final owned = holding?.quantity ?? 0;

    final qty = _quantity;
    final total = qty * (price ?? 0);
    final maxQty = price == null ? 0 : (_isBuy ? cash ~/ price : owned);
    final cashAfter = _isBuy ? cash - total : cash + total;
    final validation = price == null
        ? 'Waiting for price…'
        : qty < 1
        ? 'Enter a quantity of at least 1'
        : _isBuy && total > cash
        ? 'Not enough cash'
        : !_isBuy && qty > owned
        ? 'You own only $owned ${owned == 1 ? 'share' : 'shares'}'
        : null;
    final message = validation ?? _submitError;
    final canConfirm = validation == null && !_submitting;

    Widget row(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: tabularFigures.copyWith(color: color)),
        ],
      ),
    );

    return Padding(
      // Keeps the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_isBuy ? 'Buy' : 'Sell'} $symbol',
                style: text.titleLarge,
              ),
              const SizedBox(height: 16),
              row('Market price', price == null ? '—' : formatCents(price)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Quantity',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    tooltip: 'Decrease quantity',
                    onPressed: qty > 1 ? () => _setQuantity(qty - 1) : null,
                  ),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      style: tabularFigures,
                      keyboardType: TextInputType.number,
                      // Digits only, max 7 (SECURITY.md §4): no minus,
                      // decimals or pasted text can reach the engine.
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(7),
                      ],
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (_) => setState(() => _submitError = null),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Increase quantity',
                    onPressed: qty < 9999999
                        ? () => _setQuantity(qty + 1)
                        : null,
                  ),
                  ActionChip(
                    label: const Text('Max'),
                    onPressed: maxQty > 0 ? () => _setQuantity(maxQty) : null,
                  ),
                ],
              ),
              SizedBox(
                height: 24,
                child: message == null
                    ? null
                    : Text(
                        message,
                        textAlign: TextAlign.end,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.loss,
                        ),
                      ),
              ),
              const Divider(height: 24),
              if (_isBuy) ...[
                row('Estimated cost', formatCents(total)),
                row('Cash available', formatCents(cash)),
              ] else ...[
                row('Estimated proceeds', formatCents(total)),
                if (holding != null && price != null)
                  row(
                    'Estimated realized P&L',
                    formatSignedCents((price - holding.avgCostCents) * qty),
                    color: changeColor(price - holding.avgCostCents),
                  ),
              ],
              row('Cash after', formatCents(cashAfter)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: canConfirm ? () => _confirm(price!) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text('Confirm ${_isBuy ? 'Buy' : 'Sell'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tradeSummary(Trade t) {
  final verb = t.side == TradeSide.buy ? 'Bought' : 'Sold';
  final pnl = t.realizedPnlCents;
  return '$verb ${t.quantity} ${t.symbol} @ ${formatCents(t.priceCents)}'
      '${pnl == null ? '' : ' · P&L ${formatSignedCents(pnl)}'}';
}

String tradeErrorMessage(TradeError e) => switch (e) {
  InsufficientFunds() => 'Not enough cash',
  InsufficientShares() => "You don't own enough shares",
  InvalidQuantity() => 'Enter a quantity of at least 1',
  PriceUnavailable() => 'Waiting for price…',
};
