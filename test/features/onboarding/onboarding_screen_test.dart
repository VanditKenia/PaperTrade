import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/features/onboarding/onboarding_screen.dart';
import 'package:papertrade/features/portfolio/portfolio_provider.dart';

import '../../fakes.dart';

void main() {
  late FakePortfolioRepository repo;
  late ProviderContainer container;

  Future<void> open(WidgetTester tester) async {
    repo = FakePortfolioRepository()..hasSaved = false; // first launch
    container = ProviderContainer.test(
      overrides: [portfolioRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
  }

  FilledButton start(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Start trading'),
  );

  ChoiceChip chip(WidgetTester tester, String label) =>
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

  testWidgets(r'defaults to $100K; Start saves it and ends onboarding', (
    tester,
  ) async {
    await open(tester);
    expect(container.read(needsOnboardingProvider), isTrue);
    expect(chip(tester, r'$100K').selected, isTrue);

    await tester.tap(find.text('Start trading'));
    await tester.pumpAndSettle();
    expect(repo.saved.startingCashCents, 10000000);
    expect(repo.saved.wallet.cashCents, 10000000);
    expect(container.read(needsOnboardingProvider), isFalse);
  });

  testWidgets('a preset chip fills the field and is used', (tester) async {
    await open(tester);
    await tester.tap(find.text(r'$1M'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '1000000'), findsOneWidget);
    expect(chip(tester, r'$1M').selected, isTrue);
    expect(chip(tester, r'$100K').selected, isFalse);

    await tester.tap(find.text('Start trading'));
    await tester.pumpAndSettle();
    expect(repo.saved.wallet.cashCents, 100000000);
  });

  testWidgets('custom amount: validated inline, Start disabled while invalid', (
    tester,
  ) async {
    await open(tester);
    final field = find.byType(TextField);

    await tester.enterText(field, '');
    await tester.pump();
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(start(tester).onPressed, isNull);

    await tester.enterText(field, '99');
    await tester.pump();
    expect(find.text(r'Minimum is $100'), findsOneWidget);
    expect(start(tester).onPressed, isNull);

    await tester.enterText(field, '10000001');
    await tester.pump();
    expect(find.text(r'Maximum is $10,000,000'), findsOneWidget);
    expect(start(tester).onPressed, isNull);

    // Digits only: a decimal point or minus can't get in.
    await tester.enterText(field, '-2.5');
    await tester.pump();
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);

    await tester.enterText(field, '2500');
    await tester.pump();
    expect(find.textContaining('imum'), findsNothing);
    expect(chip(tester, r'$1K').selected, isFalse); // no preset matches
    await tester.tap(find.text('Start trading'));
    await tester.pumpAndSettle();
    expect(repo.saved.startingCashCents, 250000);
  });
}
