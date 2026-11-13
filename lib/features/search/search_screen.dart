import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../data/api_errors.dart';
import '../../domain/models/stock.dart';
import '../stock_detail/stock_detail_screen.dart';
import '../watchlist/watchlist_provider.dart';
import 'search_provider.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          maxLength: 50,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search stocks',
            counterText: '',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: notifier.setQuery,
        ),
      ),
      body: results.when(
        data: (stocks) => switch (stocks) {
          null => const _Message('Search by name or symbol'),
          [] => _Message("No results for '${notifier.query}'"),
          _ => ListView.separated(
            itemCount: stocks.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _ResultRow(stocks[i]),
          ),
        },
        loading: () => const _LoadingRows(),
        error: (e, _) => _Message(
          errorMessage(e),
          action: TextButton(
            onPressed: notifier.search,
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow(this.stock);

  final Stock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // select() so a row rebuilds only when its own star changes.
    final watched = ref.watch(
      watchlistProvider.select((l) => l.any((s) => s.symbol == stock.symbol)),
    );
    final watchlist = ref.read(watchlistProvider.notifier);

    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StockDetailScreen(stock: stock),
        ),
      ),
      title: Text(
        stock.symbol,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        stock.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: IconButton(
        icon: Icon(watched ? Icons.star : Icons.star_border),
        color: watched ? AppColors.warning : AppColors.textSecondary,
        tooltip: watched ? 'Remove from watchlist' : 'Add to watchlist',
        onPressed: () =>
            watched ? watchlist.remove(stock.symbol) : watchlist.add(stock),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

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
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 6; i++)
          ListTile(
            title: Align(alignment: Alignment.centerLeft, child: bar(56)),
            subtitle: Align(alignment: Alignment.centerLeft, child: bar(160)),
          ),
      ],
    );
  }
}
