import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/market_repository.dart';
import '../../domain/models/stock.dart';

/// Search results. `null` data means idle (nothing typed yet). autoDispose
/// resets the search each time the screen is closed.
final searchProvider =
    AsyncNotifierProvider.autoDispose<SearchNotifier, List<Stock>?>(
      SearchNotifier.new,
    );

class SearchNotifier extends AsyncNotifier<List<Stock>?> {
  static const debounce = Duration(milliseconds: 400);

  Timer? _timer;
  String query = '';

  @override
  List<Stock>? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void setQuery(String text) {
    query = text.trim();
    _timer?.cancel();
    if (query.isEmpty) {
      state = const AsyncData(null);
      return;
    }
    // Wait until typing pauses: "nvidia" costs 1 API call, not 6.
    _timer = Timer(debounce, search);
  }

  Future<void> search() async {
    final q = query;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(marketRepositoryProvider).search(q),
    );
    // If the text changed while waiting, a newer search owns the state; a
    // slow old response must not overwrite it.
    if (ref.mounted && q == query) state = result;
  }
}
