import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

/// Shown instead of the app when FINNHUB_API_KEY was not passed at build time.
class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const secondary = TextStyle(color: AppColors.textSecondary);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.key_off, size: 48, color: AppColors.warning),
              const SizedBox(height: 16),
              Text('API key missing', style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'PaperTrade needs a free Finnhub API key (finnhub.io) to load '
                'market data. Run the app with:',
                style: text.bodyLarge?.merge(secondary),
              ),
              const SizedBox(height: 16),
              const _Command(
                'flutter run --dart-define=FINNHUB_API_KEY=your_key',
              ),
              const SizedBox(height: 16),
              Text(
                'Or copy env.example.json to env.json, add your key, and run:',
                style: text.bodyLarge?.merge(secondary),
              ),
              const SizedBox(height: 16),
              const _Command('flutter run --dart-define-from-file=env.json'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Command extends StatelessWidget {
  const _Command(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: SelectableText(
        command,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}
