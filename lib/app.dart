import 'package:material_ui/material_ui.dart';

import 'app_shell.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/setup/setup_error_screen.dart';

class PaperTradeApp extends StatelessWidget {
  const PaperTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperTrade',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      // A missing key is a setup mistake, not a crash: show how to fix it.
      home: hasApiKey ? const AppShell() : const SetupErrorScreen(),
    );
  }
}
