import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/app_shell.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/features/portfolio/portfolio_screen.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';

import '../../fakes.dart';

Widget app(PortfolioState portfolio, {int? livePrice}) => ProviderScope(
  overrides: [
    portfolioRepositoryProvider.overrideWithValue(
      FakePortfolioRepository(portfolio),
    ),
    watchlistProvider.overrideWithBuild((_, _) => const []),
    latestPriceProvider('AAPL').overrideWithValue(livePrice),
  ],
  child: const MaterialApp(home: PortfolioScreen()),
);

void main() {
  testWidgets(r'first launch: $100,000 cash and an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(app(PortfolioState.initial()));
    expect(find.text(r'$100,000.00'), findsNWidgets(2)); // total + cash
    expect(find.text('No holdings yet — buy your first stock'), findsOneWidget);
    expect(find.text('Go to Watchlist'), findsOneWidget);
  });

  testWidgets('holding shows live P&L and totals use the live price', (
    tester,
  ) async {
    final owns = PortfolioEngine.buy(
      PortfolioState.initial(),
      symbol: 'AAPL',
      quantity: 10,
      priceCents: 10000,
    );
    await tester.pumpWidget(app(owns, livePrice: 9500));

    expect(find.text(r'10 sh · avg $100.00'), findsOneWidget);
    expect(find.text(r'$95.00'), findsOneWidget);
    expect(find.text(r'▼ -$50.00 (-5.00%)'), findsOneWidget);
    expect(find.text(r'$99,950.00'), findsOneWidget); // 99,000 + 950
    expect(find.text(r'▼ -$50.00 (-0.05%) total return'), findsOneWidget);
  });

  testWidgets('"Go to Watchlist" switches to the Watchlist tab', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        portfolioRepositoryProvider.overrideWithValue(
          FakePortfolioRepository(),
        ),
      ],
    );
    container.read(tabIndexProvider.notifier).select(1);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PortfolioScreen()),
      ),
    );
    await tester.tap(find.text('Go to Watchlist'));
    expect(container.read(tabIndexProvider), TabIndexNotifier.watchlist);
  });
}
