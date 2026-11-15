import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papertrade/data/alert_repository.dart';
import 'package:papertrade/data/local_store.dart';
import 'package:papertrade/domain/models/price_alert.dart';

void main() {
  late Directory dir;
  late Box<dynamic> box;
  late AlertRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papertrade_alerts');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('test');
    repo = AlertRepository(LocalStore(box));
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('nothing saved loads as empty', () {
    expect(repo.load(), isEmpty);
  });

  test('waiting and triggered alerts survive reopening the box', () async {
    final at = DateTime(2026, 11, 15, 10);
    final waiting = PriceAlert(
      id: 'a',
      symbol: 'AAPL',
      direction: AlertDirection.above,
      targetCents: 20000,
      createdAt: at,
    );
    final fired = PriceAlert(
      id: 'b',
      symbol: 'TSLA',
      direction: AlertDirection.below,
      targetCents: 15000,
      createdAt: at,
    ).triggered(14990, at.add(const Duration(hours: 1)));
    await repo.save([waiting, fired]);
    await box.close();
    box = await Hive.openBox<dynamic>('test');

    final loaded = AlertRepository(LocalStore(box)).load();
    expect(loaded.map((a) => a.id), ['a', 'b']);
    expect(loaded.first.isTriggered, isFalse);
    expect(loaded.first.direction, AlertDirection.above);
    expect(loaded.first.targetCents, 20000);
    expect(loaded.first.createdAt, at);
    expect(loaded.last.isTriggered, isTrue);
    expect(loaded.last.triggeredPriceCents, 14990);
    expect(loaded.last.triggeredAt, at.add(const Duration(hours: 1)));
  });

  test('skips corrupt alerts', () async {
    Map<String, Object?> alert(Map<String, Object?> change) => {
      'id': 'x',
      'symbol': 'AAPL',
      'dir': 'above',
      'target': 100,
      'at': 0,
      ...change,
    };
    await box.put('alerts', [
      alert({}),
      alert({'dir': 'sideways'}),
      alert({'target': 0}),
      alert({'target': 1.5}),
      alert({'at': null}),
      alert({'symbol': 7}),
      'junk',
    ]);
    expect(repo.load(), hasLength(1));
  });
}
