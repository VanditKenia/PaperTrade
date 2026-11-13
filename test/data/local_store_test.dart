import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papertrade/data/local_store.dart';
import 'package:papertrade/domain/models/stock.dart';

void main() {
  late Directory dir;
  late Box<dynamic> box;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papertrade_test');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('test');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('first launch returns the default watchlist', () {
    expect(LocalStore(box).loadWatchlist().map((s) => s.symbol), [
      'AAPL',
      'MSFT',
      'GOOGL',
      'AMZN',
      'TSLA',
      'BINANCE:BTCUSDT',
    ]);
  });

  test('saved watchlist survives reopening the box', () async {
    await LocalStore(
      box,
    ).saveWatchlist(const [Stock(symbol: 'NVDA', name: 'NVIDIA CORP')]);
    await box.close();
    box = await Hive.openBox<dynamic>('test');

    final loaded = LocalStore(box).loadWatchlist();
    expect(loaded.single.symbol, 'NVDA');
    expect(loaded.single.name, 'NVIDIA CORP');
  });

  test('an emptied watchlist stays empty (no re-seeding)', () async {
    await LocalStore(box).saveWatchlist(const []);
    expect(LocalStore(box).loadWatchlist(), isEmpty);
  });

  test('corrupt entries are skipped', () async {
    await box.put('watchlist', [
      {'symbol': 'AAPL', 'name': 'Apple Inc'},
      {'symbol': 1},
      'junk',
    ]);
    expect(LocalStore(box).loadWatchlist().map((s) => s.symbol), ['AAPL']);
  });
}
