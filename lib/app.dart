import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app_shell.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/portfolio/portfolio_provider.dart';
import 'features/setup/setup_error_screen.dart';

class PaperTradeApp extends StatelessWidget {
  const PaperTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperTrade',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      // A missing proxy URL is a setup mistake, not a crash: show how to
      // fix it.
      home: hasProxy ? const _Home() : const SetupErrorScreen(),
    );
  }
}

/// Starting-balance screen until a portfolio is saved, then the app.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(needsOnboardingProvider)
      ? const OnboardingScreen()
      : const AppShell();
}
