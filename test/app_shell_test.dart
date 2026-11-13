import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/app.dart';
import 'package:papertrade/app_shell.dart';

void main() {
  testWidgets('tapping a tab switches the visible screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppShell()));

    int shownIndex() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

    expect(shownIndex(), 0);
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await tester.pump();
    expect(shownIndex(), 1);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(shownIndex(), 3);
  });

  // Tests run without --dart-define, so the key is empty.
  testWidgets('missing API key shows the setup error screen', (tester) async {
    await tester.pumpWidget(const PaperTradeApp());

    expect(find.text('API key missing'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });
}
