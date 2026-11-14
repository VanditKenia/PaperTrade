import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/storage_error.dart';
import '../../domain/models/wallet.dart';
import '../portfolio/portfolio_provider.dart';

/// Reset account, data source note, app version (UI_UX.md §3.7).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset account?'),
        content: Text(
          'This deletes all holdings and trade history and sets cash back '
          'to ${formatCents(startingCashCents)}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.loss),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    // Tapping outside the dialog returns null: treat it as Cancel.
    if (confirmed != true) return;

    try {
      await ref.read(portfolioProvider.notifier).reset();
    } on StorageError {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reset. Try again')),
      );
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Account reset')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const secondary = TextStyle(color: AppColors.textSecondary);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.restart_alt, color: AppColors.loss),
            title: const Text(
              'Reset account',
              style: TextStyle(color: AppColors.loss),
            ),
            subtitle: Text(
              'Back to ${formatCents(startingCashCents)} cash, no trades',
              style: secondary.merge(tabularFigures),
            ),
            onTap: () => _confirmReset(context, ref),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(
              'Market data by Finnhub. Prices may be delayed. '
              'Virtual money only.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.tag),
            title: Text('App version'),
            trailing: Text(appVersion, style: secondary),
          ),
        ],
      ),
    );
  }
}
