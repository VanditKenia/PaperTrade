import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'features/alerts/alerts_provider.dart';
import 'features/history/history_screen.dart';
import 'features/portfolio/order_matcher_provider.dart';
import 'features/portfolio/portfolio_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stats/stats_provider.dart';
import 'features/watchlist/price_subscriptions_provider.dart';
import 'features/watchlist/watchlist_screen.dart';

/// Selected bottom-nav tab. A provider (not widget state) so other screens
/// can switch tabs, e.g. Portfolio's empty state → Watchlist.
final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(
  TabIndexNotifier.new,
);

class TabIndexNotifier extends Notifier<int> {
  static const watchlist = 0;

  @override
  int build() => watchlist;

  void select(int index) => state = index;
}

/// Bottom navigation: Watchlist · Portfolio · History · Settings.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _screens = [
    WatchlistScreen(),
    PortfolioScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    // Keeps WebSocket subscriptions in sync for as long as the app runs.
    ref.watch(priceSubscriptionsProvider);
    // Fills open limit/stop orders on live ticks while the app runs.
    ref.watch(orderMatcherProvider);
    // Portfolio value snapshots for the Stats chart.
    ref.watch(snapshotRecorderProvider);
    // Fires price alerts while the app is open; the snackbar is shown here
    // because the monitor has no BuildContext.
    ref.watch(alertMonitorProvider);
    ref.listen(lastTriggeredAlertProvider, (_, alert) {
      if (alert == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alertMessage(alert)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
    return Scaffold(
      // IndexedStack keeps every tab alive, so each keeps its scroll position
      // when you switch away and back (UI_UX.md §5).
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ref.read(tabIndexProvider.notifier).select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Watchlist',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Portfolio',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
