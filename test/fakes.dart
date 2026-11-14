import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/storage_error.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';

/// In-memory portfolio storage for widget tests (no Hive).
class FakePortfolioRepository implements PortfolioRepository {
  FakePortfolioRepository([PortfolioState? initial])
    : saved = initial ?? PortfolioState.initial();

  PortfolioState saved;
  int saves = 0;
  bool failSaves = false;

  @override
  PortfolioState load() => saved;

  @override
  Future<void> save(PortfolioState state) async {
    if (failSaves) throw StorageError(StateError('disk full'));
    saves++;
    saved = state;
  }
}
