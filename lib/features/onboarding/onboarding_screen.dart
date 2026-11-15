import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../data/storage_error.dart';
import '../../domain/models/wallet.dart';
import '../portfolio/portfolio_provider.dart';
import 'widgets/starting_balance_picker.dart';

/// First launch only: pick the starting balance (APP_FLOW.md §2). Saving it
/// flips needsOnboardingProvider, and the app moves on to the Watchlist.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int? _cents = defaultStartingCashCents;
  bool _saving = false;

  Future<void> _start(int cents) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(portfolioProvider.notifier).reset(cents);
    } on StorageError {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Try again')),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cents = _cents;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Text('Choose your starting balance', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Virtual money only. You can change it later by resetting your '
              'account in Settings.',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            StartingBalancePicker(
              initialCents: defaultStartingCashCents,
              onChanged: (c) => setState(() => _cents = c),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: cents == null || _saving ? null : () => _start(cents),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Start trading'),
            ),
          ],
        ),
      ),
    );
  }
}
