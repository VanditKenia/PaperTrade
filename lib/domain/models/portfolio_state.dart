import 'holding.dart';
import 'trade.dart';
import 'wallet.dart';

/// Everything PortfolioEngine works on. Immutable: the engine returns a new
/// state instead of changing this one.
class PortfolioState {
  PortfolioState({
    required this.wallet,
    Map<String, Holding> holdings = const {},
    List<Trade> trades = const [],
  }) : holdings = Map.unmodifiable(holdings),
       trades = List.unmodifiable(trades);

  PortfolioState.initial()
    : this(wallet: const Wallet(cashCents: startingCashCents));

  final Wallet wallet;
  final Map<String, Holding> holdings; // keyed by symbol
  final List<Trade> trades; // oldest first
}
