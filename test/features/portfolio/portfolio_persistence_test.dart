import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papertrade/data/local_store.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/features/portfolio/portfolio_provider.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papertrade_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  /// A fresh container over the same Hive box, like a new app launch.
  Future<ProviderContainer> launch() async {
    final box = await Hive.openBox<dynamic>('papertrade');
    return ProviderContainer.test(
      overrides: [localStoreProvider.overrideWithValue(LocalStore(box))],
    );
  }

  test('trades made through the provider survive a restart', () async {
    var app = await launch();
    final portfolio = app.read(portfolioProvider.notifier);
    await portfolio.buy('AAPL', 5, priceCents: 18942);
    await portfolio.sell('AAPL', 2, priceCents: 18942);
    final before = app.read(portfolioProvider);

    app.dispose();
    await Hive.close();
    app = await launch();
    final after = app.read(portfolioProvider);

    expect(after.wallet.cashCents, before.wallet.cashCents);
    expect(after.holdings['AAPL']!.quantity, 3);
    expect(after.holdings['AAPL']!.avgCostCents, 18942);
    expect(after.trades.map((t) => t.side), [TradeSide.buy, TradeSide.sell]);
    expect(after.trades.map((t) => t.id), before.trades.map((t) => t.id));
  });
}
