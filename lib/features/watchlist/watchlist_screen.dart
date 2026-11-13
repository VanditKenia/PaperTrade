import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../domain/models/stock.dart';
import '../search/search_screen.dart';
import 'watchlist_provider.dart';
import 'widgets/price_tile.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  void _openSearch(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));

  Future<void> _refresh(WidgetRef ref, List<Stock> stocks) async {
    for (final s in stocks) {
      ref.invalidate(quoteProvider(s.symbol));
    }
    try {
      // Only waiting so the spinner stays up; quotes newer than 30 s come
      // from the repository cache, which protects the API rate limit.
      await Future.wait([
        for (final s in stocks) ref.read(quoteProvider(s.symbol).future),
      ]);
    } catch (_) {
      // Each tile already shows its own error.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stocks = ref.watch(watchlistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search stocks',
            onPressed: () => _openSearch(context),
          ),
        ],
      ),
      body: stocks.isEmpty
          ? _EmptyState(onSearch: () => _openSearch(context))
          : RefreshIndicator(
              onRefresh: () => _refresh(ref, stocks),
              child: ListView.separated(
                itemCount: stocks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final stock = stocks[i];
                  return Dismissible(
                    key: ValueKey(stock.symbol),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => ref
                        .read(watchlistProvider.notifier)
                        .remove(stock.symbol),
                    background: Container(
                      color: AppColors.loss,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(
                        Icons.delete_outline,
                        semanticLabel: 'Remove',
                      ),
                    ),
                    child: PriceTile(stock: stock),
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.playlist_add,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Your watchlist is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search stocks'),
            ),
          ],
        ),
      ),
    );
  }
}
