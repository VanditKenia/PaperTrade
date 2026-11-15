import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/features/settings/settings_screen.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:papertrade/data/alert_repository.dart';

import '../../fakes.dart';

void main() {
  late FakePortfolioRepository repo;

  Future<void> open(WidgetTester tester, {int start = 10000000}) async {
    repo = FakePortfolioRepository(
      PortfolioEngine.buy(
        PortfolioEngine.reset(start),
        symbol: 'AAPL',
        quantity: 5 * unitsPerShare,
        priceCents: 18500,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioRepositoryProvider.overrideWithValue(repo),
          alertRepositoryProvider.overrideWithValue(FakeAlertRepository()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.tap(find.text('Reset account'));
    await tester.pumpAndSettle();
  }

  testWidgets('Cancel leaves the account untouched', (tester) async {
    await open(tester);
    expect(find.text('Reset account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(repo.saved.holdings, isNotEmpty);
  });

  testWidgets('confirming resets cash, holdings and trades', (tester) async {
    await open(tester);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(repo.saved.wallet.cashCents, 10000000);
    expect(repo.saved.holdings, isEmpty);
    expect(repo.saved.trades, isEmpty);
    expect(find.text('Account reset'), findsOneWidget);
  });

  testWidgets('a failed save says so and keeps the data', (tester) async {
    await open(tester);
    repo.failSaves = true;
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Could not reset. Try again'), findsOneWidget);
    expect(repo.saved.holdings, isNotEmpty);
  });

  testWidgets('dialog is pre-filled with the current starting balance', (
    tester,
  ) async {
    await open(tester, start: 2500000);
    expect(find.widgetWithText(TextField, '25000'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(repo.saved.startingCashCents, 2500000);
    expect(repo.saved.wallet.cashCents, 2500000);
  });

  testWidgets('a preset resets to that balance', (tester) async {
    await open(tester);
    await tester.tap(find.text(r'$10K'));
    await tester.pump();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(repo.saved.startingCashCents, 1000000);
    expect(repo.saved.holdings, isEmpty);
  });

  testWidgets('invalid amount disables Reset', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '50');
    await tester.pump();
    expect(find.text(r'Minimum is $100'), findsOneWidget);
    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reset'),
    );
    expect(reset.onPressed, isNull);
    expect(repo.saves, 0);
  });
}
