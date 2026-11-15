import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papertrade/data/local_store.dart';
import 'package:papertrade/data/value_history_repository.dart';
import 'package:papertrade/domain/value_history.dart';

void main() {
  late Directory dir;
  late Box<dynamic> box;
  late ValueHistoryRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papertrade_history');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('test');
    repo = ValueHistoryRepository(LocalStore(box));
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('nothing saved loads as empty', () {
    expect(repo.load(), isEmpty);
  });

  test('snapshots survive reopening the box', () async {
    final t = DateTime(2026, 11, 15, 10);
    await repo.save([
      ValueSnapshot(time: t, valueCents: 10000000),
      ValueSnapshot(
        time: t.add(const Duration(minutes: 5)),
        valueCents: 10012345,
      ),
    ]);
    await box.close();
    box = await Hive.openBox<dynamic>('test');

    final loaded = ValueHistoryRepository(LocalStore(box)).load();
    expect(loaded.map((s) => s.valueCents), [10000000, 10012345]);
    expect(loaded.first.time, t);
  });

  test('skips bad entries; accepts whole-number doubles (web)', () async {
    await box.put('valueHistory', [
      [1000, 500],
      [2000.0, 600.0],
      [3000, 1.5],
      ['x', 1],
      [1],
      'junk',
    ]);
    expect(repo.load().map((s) => s.valueCents), [500, 600]);
  });

  test('a non-list value loads as empty', () async {
    await box.put('valueHistory', {'not': 'a list'});
    expect(repo.load(), isEmpty);
  });
}
