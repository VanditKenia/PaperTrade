import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/storage_error.dart';
import '../../../domain/models/pending_order.dart';
import '../../../domain/models/stock.dart';
import '../../../domain/models/trade.dart';
import '../../../domain/portfolio_engine.dart';
import '../../../domain/quantity.dart';
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

// What the field accepts (SECURITY.md §4): digits and one dot, so no minus,
// letters or pasted text can reach the engine. Shares: 7 digits + 4
// decimals; dollars: 9 digits + cents.
final _sharesInput = RegExp(r'^\d{0,7}(\.\d{0,4})?$');
final _dollarsInput = RegExp(r'^\d{0,9}(\.\d{0,2})?$');
const _maxUnits = 99999999999; // 9,999,999.9999 shares

class _OrderSheetState extends ConsumerState<OrderSheet> {
  final _input = TextEditingController(text: '1');
  final _priceInput = TextEditingController(); // limit / stop price
  OrderType _type = OrderType.market;
  bool _amountMode = false; // the field holds dollars instead of shares
  bool _submitting = false;
  String? _submitError; // set when the engine or the save rejects a trade

  bool get _isBuy => widget.side == TradeSide.buy;
  bool get _isMarket => _type == OrderType.market;

  @override
  void dispose() {
    _input.dispose();
    _priceInput.dispose();
    super.dispose();
  }

  /// A new limit/stop order starts at the current price, a sensible
  /// starting point to adjust from.
  void _setType(OrderType type, int? marketPrice) {
    if (_isMarket && type != OrderType.market && marketPrice != null) {
      _priceInput.text =
          '${marketPrice ~/ 100}.${'${marketPrice % 100}'.padLeft(2, '0')}';
    }
    setState(() {
      _type = type;
      _submitError = null;
    });
  }

  void _setText(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Always switches to shares: an exact quantity can't be off by the
  /// rounding of a dollar amount (used by Max and the steppers).
  void _setQuantity(int units) {
    _setText(formatShares(units));
    setState(() {
      _amountMode = false;
      _submitError = null;
    });
  }

  /// Switching to shares keeps the quantity the amount converted to;
  /// switching to dollars starts empty.
  void _setMode(bool amountMode, int units) {
    if (amountMode == _amountMode) return;
    _setText(amountMode || units < 1 ? '' : formatShares(units));
    setState(() {
      _amountMode = amountMode;
      _submitError = null;
    });
  }

  /// [quantity] and [priceCents] are what was on screen when Confirm was
  /// tapped, so the fill matches what the user saw. For a limit/stop order
  /// [priceCents] is the limit/stop price instead.
  Future<void> _confirm(int quantity, int priceCents) async {
    final symbol = widget.stock.symbol;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final portfolio = ref.read(portfolioProvider.notifier);
    setState(() => _submitting = true);

    final String summary;
    try {
      if (!_isMarket) {
        summary = _orderSummary(
          await portfolio.placeOrder(
            symbol: symbol,
            side: widget.side,
            type: _type,
            quantity: quantity,
            triggerPriceCents: priceCents,
          ),
        );
      } else {
        summary = _tradeSummary(
          _isBuy
              ? await portfolio.buy(symbol, quantity, priceCents: priceCents)
              : await portfolio.sell(symbol, quantity, priceCents: priceCents),
        );
      }
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
    messenger.showSnackBar(SnackBar(content: Text(summary)));
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
    final offline = ref.watch(isOfflineProvider);
    // Trading stays allowed while closed, at the last price (APP_FLOW.md §5).
    final marketClosed =
        !isCrypto(symbol) && ref.watch(marketOpenProvider).value == false;
    // Available = not reserved by open orders (TRD.md §4).
    final cash = ref.watch(
      portfolioProvider.select((p) => p.availableCashCents),
    );
    final holding = ref.watch(
      portfolioProvider.select((p) => p.holdings[symbol]),
    );
    final owned = holding?.quantity ?? 0;
    final available = ref.watch(
      portfolioProvider.select((p) => p.availableQuantity(symbol)),
    );

    // Market orders are priced at the market; limit/stop orders at the
    // price typed in, which is also the worst case they can fill at.
    final trigger = _isMarket ? null : parseDollars(_priceInput.text);
    final orderPrice = _isMarket ? price : trigger;
    final priceLabel = _type == OrderType.stopLoss
        ? 'Stop price'
        : 'Limit price';

    final entered =
        (_amountMode ? parseDollars(_input.text) : parseShares(_input.text)) ??
        0;
    // Amount mode needs a price to know how many shares the dollars buy.
    final qty = !_amountMode
        ? entered
        : orderPrice == null || orderPrice < 1
        ? 0
        : unitsForAmount(entered, orderPrice);
    final total = orderPrice == null ? 0 : costCents(qty, orderPrice);
    final maxQty = !_isBuy
        ? available
        : orderPrice == null || orderPrice < 1
        ? 0
        : maxAffordableUnits(cash, orderPrice);
    final pnl = holding != null && orderPrice != null && qty <= owned
        ? PortfolioEngine.realizedPnl(holding, qty, orderPrice)
        : null;
    final cashAfter = _isBuy ? cash - total : cash + total;
    final validation = offline
        ? 'Offline — trading paused'
        : _isMarket && price == null
        ? 'Waiting for price…'
        : !_isMarket && (trigger == null || trigger < 1)
        ? 'Enter a ${priceLabel.toLowerCase()}'
        : qty < 1
        ? 'Minimum quantity is 0.0001'
        : total < 1
        ? r'Order value must be at least $0.01'
        : _isBuy && total > cash
        ? 'Not enough cash'
        : !_isBuy && qty > available
        ? (available == owned
              ? 'You own only ${formatQuantity(symbol, owned)}'
              : 'Only ${formatQuantity(symbol, available)} available '
                    '(rest in open orders)')
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
        // Scrolls on short screens, e.g. with the keyboard and price field.
        child: SingleChildScrollView(
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
                row(
                  marketClosed ? 'Last price (market closed)' : 'Market price',
                  price == null ? '—' : formatCents(price),
                ),
                const SizedBox(height: 8),
                SegmentedButton<OrderType>(
                  segments: [
                    const ButtonSegment(
                      value: OrderType.market,
                      label: Text('Market'),
                    ),
                    const ButtonSegment(
                      value: OrderType.limit,
                      label: Text('Limit'),
                    ),
                    if (!_isBuy)
                      const ButtonSegment(
                        value: OrderType.stopLoss,
                        label: Text('Stop-loss'),
                      ),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setType(s.single, price),
                ),
                if (!_isMarket) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        priceLabel,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          key: const ValueKey('trigger-price'),
                          controller: _priceInput,
                          textAlign: TextAlign.center,
                          style: tabularFigures,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            TextInputFormatter.withFunction(
                              (old, value) => _dollarsInput.hasMatch(value.text)
                                  ? value
                                  : old,
                            ),
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixText: r'$',
                          ),
                          onChanged: (_) => setState(() => _submitError = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_triggerRule(widget.side, _type)} '
                    'Orders only execute while the app is open.',
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Quantity')),
                    ButtonSegment(value: true, label: Text(r'Amount ($)')),
                  ],
                  selected: {_amountMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setMode(s.single, qty),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _amountMode ? 'Amount' : 'Quantity',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    if (!_amountMode)
                      IconButton(
                        icon: const Icon(Icons.remove),
                        tooltip: 'Decrease quantity',
                        onPressed: qty > unitsPerShare
                            ? () => _setQuantity(qty - unitsPerShare)
                            : null,
                      ),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _input,
                        textAlign: TextAlign.center,
                        style: tabularFigures,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // Rejects the whole edit if the result isn't valid.
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (old, value) =>
                                (_amountMode ? _dollarsInput : _sharesInput)
                                    .hasMatch(value.text)
                                ? value
                                : old,
                          ),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: _amountMode ? r'$' : null,
                        ),
                        onChanged: (_) => setState(() => _submitError = null),
                      ),
                    ),
                    if (!_amountMode)
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: 'Increase quantity',
                        onPressed: qty + unitsPerShare <= _maxUnits
                            ? () => _setQuantity(qty + unitsPerShare)
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
                if (_amountMode) row('Quantity', formatQuantity(symbol, qty)),
                if (_isBuy) ...[
                  row(
                    _isMarket ? 'Estimated cost' : 'Cash reserved',
                    formatCents(total),
                  ),
                  row('Cash available', formatCents(cash)),
                ] else ...[
                  row('Estimated proceeds', formatCents(total)),
                  if (pnl != null)
                    row(
                      'Estimated realized P&L',
                      formatSignedCents(pnl),
                      color: changeColor(pnl),
                    ),
                ],
                row('Cash after', formatCents(cashAfter)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: canConfirm
                      ? () => _confirm(qty, orderPrice!)
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    _isMarket
                        ? 'Confirm ${_isBuy ? 'Buy' : 'Sell'}'
                        : 'Place ${_isBuy ? 'Buy' : 'Sell'} order',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _tradeSummary(Trade t) {
  final verb = t.side == TradeSide.buy ? 'Bought' : 'Sold';
  final pnl = t.realizedPnlCents;
  return '$verb ${formatShares(t.quantity)} ${t.symbol} @ ${formatCents(t.priceCents)}'
      '${pnl == null ? '' : ' · P&L ${formatSignedCents(pnl)}'}';
}

/// "Limit buy 5 AAPL @ $180.00 placed".
String _orderSummary(PendingOrder o) =>
    '${orderLabel(o.side, o.type)} ${formatShares(o.quantity)} ${o.symbol} '
    '@ ${formatCents(o.triggerPriceCents)} placed';

/// "Limit buy", "Limit sell", "Stop-loss".
String orderLabel(TradeSide side, OrderType type) => switch (type) {
  OrderType.market => side == TradeSide.buy ? 'Market buy' : 'Market sell',
  OrderType.limit => side == TradeSide.buy ? 'Limit buy' : 'Limit sell',
  OrderType.stopLoss => 'Stop-loss',
};

String _triggerRule(TradeSide side, OrderType type) => switch (type) {
  OrderType.stopLoss => 'Sells when the price falls to or below the stop.',
  _ when side == TradeSide.buy =>
    'Buys when the price is at or below the limit.',
  _ => 'Sells when the price is at or above the limit.',
};

String tradeErrorMessage(TradeError e) => switch (e) {
  InsufficientFunds() => 'Not enough cash',
  InsufficientShares() => "You don't own that many",
  InvalidQuantity() => 'Minimum quantity is 0.0001',
  PriceUnavailable() => 'Waiting for price…',
  OrderTooSmall() => r'Order value must be at least $0.01',
  InvalidOrderPrice() => 'Enter a valid price',
  OrderNotFound() => 'Order is no longer open',
  OrderNotTriggered() => 'Price not reached',
};
