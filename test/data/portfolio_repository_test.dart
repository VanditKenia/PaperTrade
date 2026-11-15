import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papertrade/data/local_store.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/models/wallet.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/domain/quantity.dart';

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
    expect(s.wallet.cashCents, defaultStartingCashCents);
    expect(s.holdings, isEmpty);
    expect(s.trades, isEmpty);
  });

  test('saved state survives reopening the box', () async {
    final at = DateTime(2026, 11, 14, 10);
    var s = PortfolioEngine.buy(
      repo.load(),
      symbol: 'AAPL',
      quantity: 105000, // 10.5 shares
      priceCents: 10000,
      now: at,
    );
    s = PortfolioEngine.sell(
      s,
      symbol: 'AAPL',
      quantity: 4 * unitsPerShare,
      priceCents: 12000,
      now: at,
    );
    await repo.save(s);
    await box.close();
    box = await Hive.openBox<dynamic>('test');

    final loaded = PortfolioRepository(LocalStore(box)).load();
    expect(loaded.wallet.cashCents, s.wallet.cashCents);
    expect(loaded.holdings['AAPL']!.quantity, 65000);
    expect(loaded.holdings['AAPL']!.costBasisCents, 65000);
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
    expect(s.holdings['AAPL']!.quantity, 10 * unitsPerShare);
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
    expect(repo.load().wallet.cashCents, defaultStartingCashCents);
  });

  test('starting balance is saved and loaded with the rest', () async {
    await repo.save(PortfolioEngine.reset(2500000));
    final s = PortfolioRepository(LocalStore(box)).load();
    expect(s.startingCashCents, 2500000);
    expect(s.wallet.cashCents, 2500000);
  });

  test(r'migration: old data without a start loads as $100,000', () async {
    // Exactly what Step 5–8 builds wrote: no 'start' key.
    await box.put('portfolio', {
      'cash': 9000000,
      'holdings': [
        {'symbol': 'AAPL', 'qty': 10, 'avg': 10000},
      ],
      'trades': <Object>[],
    });
    final s = repo.load();
    expect(s.startingCashCents, defaultStartingCashCents);
    expect(s.wallet.cashCents, 9000000); // the rest is untouched
    expect(s.holdings['AAPL']!.quantity, 10 * unitsPerShare);
  });

  test(
    'migration: old whole-share quantities × 10,000, basis = qty × avg',
    () async {
      // What builds before fractional shares wrote: no 'v', 'avg' per share.
      await box.put('portfolio', {
        'cash': 9000000,
        'start': 10000000,
        'holdings': [
          {'symbol': 'AAPL', 'qty': 3, 'avg': 10500},
        ],
        'trades': [
          {
            'id': 'a',
            'symbol': 'AAPL',
            'side': 'buy',
            'qty': 5,
            'price': 10500,
            'at': 0,
          },
          {
            'id': 'b',
            'symbol': 'AAPL',
            'side': 'sell',
            'qty': 2,
            'price': 12000,
            'at': 1,
            'pnl': 3000,
          },
        ],
      });
      final s = repo.load();
      final h = s.holdings['AAPL']!;
      expect(h.quantity, 30000);
      expect(h.costBasisCents, 31500);
      expect(h.avgCostCents, 10500);
      expect(s.trades.map((t) => t.quantity), [50000, 20000]);
      expect(s.trades.last.realizedPnlCents, 3000);

      // Saving writes the new format; loading it again doesn't migrate twice.
      await repo.save(s);
      final again = repo.load();
      expect(again.holdings['AAPL']!.quantity, 30000);
      expect(again.trades.first.quantity, 50000);
    },
  );

  test('new format: fractional units and basis load as saved', () async {
    await box.put('portfolio', {
      'v': 2,
      'cash': 100,
      'holdings': [
        {'symbol': 'AAPL', 'qty': 1, 'basis': 2},
        {'symbol': 'MSFT', 'qty': 1.5, 'basis': 2}, // not a whole unit
        {'symbol': 'TSLA', 'qty': 5, 'basis': -1},
      ],
      'trades': [
        {
          'id': 'a',
          'symbol': 'AAPL',
          'side': 'buy',
          'qty': 1,
          'price': 20000,
          'at': 0,
        },
      ],
    });
    final s = repo.load();
    expect(s.holdings.keys, ['AAPL']);
    expect(s.holdings['AAPL']!.quantity, 1);
    expect(s.holdings['AAPL']!.costBasisCents, 2);
    expect(s.trades.single.quantity, 1);
  });

  test('a corrupt start falls back to the default', () async {
    for (final bad in <Object?>[0, -5, 'x', 12.5, 10050]) {
      await box.put('portfolio', {'cash': 100, 'start': bad});
      expect(
        repo.load().startingCashCents,
        defaultStartingCashCents,
        reason: '$bad',
      );
    }
  });

  test('open orders and fill types are saved and loaded', () async {
    final at = DateTime(2026, 11, 15, 10);
    var s = PortfolioEngine.buy(
      repo.load(),
      symbol: 'AAPL',
      quantity: 10 * unitsPerShare,
      priceCents: 10000,
      now: at,
    );
    s = PortfolioEngine.placeOrder(
      s,
      symbol: 'AAPL',
      side: TradeSide.sell,
      type: OrderType.stopLoss,
      quantity: 4 * unitsPerShare,
      triggerPriceCents: 9000,
      now: at,
    );
    s = PortfolioEngine.placeOrder(
      s,
      symbol: 'MSFT',
      side: TradeSide.buy,
      type: OrderType.limit,
      quantity: 15000,
      triggerPriceCents: 40000,
      now: at,
    );
    s = PortfolioEngine.fillOrder(
      s,
      orderId: s.orders.first.id,
      priceCents: 8900,
    );
    await repo.save(s);

    final loaded = PortfolioRepository(LocalStore(box)).load();
    final o = loaded.orders.single;
    expect(o.id, s.orders.single.id);
    expect(o.symbol, 'MSFT');
    expect(o.side, TradeSide.buy);
    expect(o.type, OrderType.limit);
    expect(o.quantity, 15000);
    expect(o.triggerPriceCents, 40000);
    expect(o.createdAt, at);
    expect(loaded.reservedCashCents, 60000);
    expect(loaded.trades.map((t) => t.orderType), [
      OrderType.market,
      OrderType.stopLoss,
    ]);
  });

  test('trades without a type load as market; no orders key → none', () async {
    await box.put('portfolio', {
      'v': 2,
      'cash': 100,
      'trades': [
        {
          'id': 'a',
          'symbol': 'AAPL',
          'side': 'buy',
          'qty': 1,
          'price': 1,
          'at': 0,
        },
      ],
    });
    final s = repo.load();
    expect(s.trades.single.orderType, OrderType.market);
    expect(s.orders, isEmpty);
  });

  test('corrupt orders are skipped so they reserve nothing', () async {
    Map<String, Object?> order(Map<String, Object?> change) => {
      'id': 'o',
      'symbol': 'AAPL',
      'side': 'buy',
      'type': 'limit',
      'qty': 1,
      'price': 100,
      'at': 0,
      ...change,
    };
    await box.put('portfolio', {
      'v': 2,
      'cash': 100,
      'orders': [
        order({}),
        order({'type': 'market'}),
        order({'type': 'stopLoss'}), // stop-loss buy isn't a thing
        order({'type': 'teleport'}),
        order({'qty': 0}),
        order({'price': 0}),
        order({'at': null}),
        'junk',
      ],
    });
    expect(repo.load().orders, hasLength(1));
  });

  test('hasSaved: false on first launch, true after a save', () async {
    expect(repo.hasSaved, isFalse);
    await repo.save(PortfolioEngine.reset(100000));
    expect(repo.hasSaved, isTrue);
  });
}
