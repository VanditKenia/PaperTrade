import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local_store.dart';

Future<void> main() async {
  // Needed before Hive can find the app's documents directory.
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const PaperTradeApp(),
    ),
  );
}
