import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papertrade/data/local_store.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/models/wallet.dart';
import 'package:papertrade/domain/portfolio_engine.dart';

void main() {
  late Directory dir;
  late Box<dynamic> box;
  late PortfolioRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papertrade_test');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('test');
    repo = PortfolioRepository(LocalStore(box));
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test(r'first launch starts with $100,000 and nothing else', () {
    final s = repo.load();
    expect(s.wallet.cashCents, startingCashCents);
    expect(s.holdings, isEmpty);
    expect(s.trades, isEmpty);
  });

  test('saved state survives reopening the box', () async {
    final at = DateTime(2026, 11, 14, 10);
    var s = PortfolioEngine.buy(
      repo.load(),
      symbol: 'AAPL',
      quantity: 10,
      priceCents: 10000,
      now: at,
    );
    s = PortfolioEngine.sell(
      s,
      symbol: 'AAPL',
      quantity: 4,
      priceCents: 12000,
      now: at,
    );
    await repo.save(s);
    await box.close();
    box = await Hive.openBox<dynamic>('test');

    final loaded = PortfolioRepository(LocalStore(box)).load();
    expect(loaded.wallet.cashCents, s.wallet.cashCents);
    expect(loaded.holdings['AAPL']!.quantity, 6);
    expect(loaded.holdings['AAPL']!.avgCostCents, 10000);
    expect(loaded.trades, hasLength(2));
    final sell = loaded.trades.last;
    expect(sell.side, TradeSide.sell);
    expect(sell.priceCents, 12000);
    expect(sell.realizedPnlCents, 8000);
    expect(sell.executedAt, at);
    expect(sell.id, s.trades.last.id);
    expect(loaded.trades.first.realizedPnlCents, isNull);
  });

  test('accepts whole-number doubles (how web can return ints)', () async {
    await box.put('portfolio', {
      'cash': 9900000.0,
      'holdings': [
        {'symbol': 'AAPL', 'qty': 10.0, 'avg': 10000.0},
      ],
      'trades': [],
    });
    final s = repo.load();
    expect(s.wallet.cashCents, 9900000);
    expect(s.holdings['AAPL']!.quantity, 10);
  });

  test('skips corrupt holdings and trades; never a fractional cent', () async {
    await box.put('portfolio', {
      'cash': 5000000,
      'holdings': [
        {'symbol': 'AAPL', 'qty': 1, 'avg': 100.5},
        {'symbol': 'MSFT', 'qty': 0, 'avg': 100},
        'junk',
        {'symbol': 'TSLA', 'qty': 2, 'avg': 20000},
      ],
      'trades': [
        {'id': 'x', 'symbol': 'TSLA', 'side': 'hold', 'qty': 1, 'price': 1},
      ],
    });
    final s = repo.load();
    expect(s.wallet.cashCents, 5000000);
    expect(s.holdings.keys, ['TSLA']);
    expect(s.trades, isEmpty);
  });

  test('unreadable cash falls back to a fresh account', () async {
    await box.put('portfolio', {'cash': 'lots'});
    expect(repo.load().wallet.cashCents, startingCashCents);
  });
}
