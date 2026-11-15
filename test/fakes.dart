import 'package:papertrade/data/alert_repository.dart';
import 'package:papertrade/data/notification_service.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/storage_error.dart';
import 'package:papertrade/data/twelve_data_api.dart';
import 'package:papertrade/data/value_history_repository.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/price_alert.dart';
import 'package:papertrade/domain/models/price_point.dart';
import 'package:papertrade/domain/value_history.dart';

/// Stand-in proxy host for API client tests (never contacted).
final testProxy = Uri.https('proxy.test');

/// In-memory portfolio storage for widget tests (no Hive).
class FakePortfolioRepository implements PortfolioRepository {
  FakePortfolioRepository([PortfolioState? initial])
    : saved = initial ?? PortfolioState.initial();

  PortfolioState saved;
  int saves = 0;
  bool failSaves = false;
  // Most tests are a returning user; onboarding tests set this to false.
  @override
  bool hasSaved = true;

  @override
  PortfolioState load() => saved;

  @override
  Future<void> save(PortfolioState state) async {
    if (failSaves) throw StorageError(StateError('disk full'));
    saves++;
    saved = state;
    hasSaved = true;
  }
}

/// In-memory price alerts (no Hive).
class FakeAlertRepository implements AlertRepository {
  FakeAlertRepository([this.saved = const []]);

  List<PriceAlert> saved;
  int saves = 0;
  bool failSaves = false;

  @override
  List<PriceAlert> load() => saved;

  @override
  Future<void> save(List<PriceAlert> alerts) async {
    if (failSaves) throw StorageError(StateError('disk full'));
    saves++;
    saved = alerts;
  }
}

/// Records notifications instead of showing them.
class FakeNotificationService implements NotificationService {
  final shown = <String>[];
  int permissionRequests = 0;

  @override
  Future<void> show(int id, String title, String body) async => shown.add(body);

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }
}

/// In-memory value snapshots (no Hive).
class FakeValueHistoryRepository implements ValueHistoryRepository {
  FakeValueHistoryRepository([this.saved = const []]);

  List<ValueSnapshot> saved;
  int saves = 0;

  @override
  List<ValueSnapshot> load() => saved;

  @override
  Future<void> save(List<ValueSnapshot> history) async {
    saves++;
    saved = history;
  }
}

/// Twelve Data stand-in: records calls instead of hitting the network.
class FakeTwelveDataApi implements TwelveDataApi {
  final calls = <(String, String, int)>[];
  List<PricePoint> points = [
    PricePoint(time: DateTime.utc(2026, 11, 13), priceCents: 100),
  ];
  Object? error;

  @override
  Future<List<PricePoint>> timeSeries(
    String symbol, {
    required String interval,
    required int outputSize,
  }) async {
    calls.add((symbol, interval, outputSize));
    if (error case final e?) throw e;
    return points;
  }
}
