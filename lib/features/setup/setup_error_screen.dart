import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

/// Shown instead of the app when PROXY_BASE_URL is missing or not a bare
/// https URL. The app has no API keys; they live in the proxy (proxy/).
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
              const Icon(Icons.cloud_off, size: 48, color: AppColors.warning),
              const SizedBox(height: 16),
              Text('Proxy URL missing', style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'PaperTrade loads market data through its Cloudflare Worker '
                '(see proxy/README.md). Run the app with the Worker URL:',
                style: text.bodyLarge?.merge(secondary),
              ),
              const SizedBox(height: 16),
              const _Command(
                'flutter run --dart-define=PROXY_BASE_URL='
                'https://papertrade-proxy.<name>.workers.dev',
              ),
              const SizedBox(height: 16),
              Text(
                'Or copy env.example.json to env.json, set PROXY_BASE_URL '
                '(https only), and run:',
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
