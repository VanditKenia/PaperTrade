import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../alerts/widgets/alerts_list.dart';
import '../../data/storage_error.dart';
import '../onboarding/widgets/starting_balance_picker.dart';
import '../portfolio/portfolio_provider.dart';

/// Reset account, data source note, app version (UI_UX.md §3.7).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = ref.read(portfolioProvider).startingCashCents;
    final cents = await showDialog<int>(
      context: context,
      builder: (_) => _ResetDialog(initialCents: current),
    );
    // Cancel, or tapping outside the dialog, returns null.
    if (cents == null) return;

    try {
      await ref.read(portfolioProvider.notifier).reset(cents);
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
    final startingCash = ref.watch(
      portfolioProvider.select((p) => p.startingCashCents),
    );

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
              'Started with ${formatCents(startingCash)} · pick a new '
              'balance, clear all trades',
              style: secondary.merge(tabularFigures),
            ),
            onTap: () => _confirmReset(context, ref),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Price alerts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const AlertsList(),
              ],
            ),
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

/// Confirm dialog with a starting-balance picker. Pops with the new amount
/// in cents, or null on Cancel.
class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.initialCents});

  final int initialCents;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  late int? _cents = widget.initialCents;

  @override
  Widget build(BuildContext context) {
    final cents = _cents;
    return AlertDialog(
      title: const Text('Reset account?'),
      // Scrolls if the keyboard leaves too little room.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This deletes all holdings and trade history. This cannot be '
              'undone.',
            ),
            const SizedBox(height: 16),
            StartingBalancePicker(
              initialCents: widget.initialCents,
              onChanged: (c) => setState(() => _cents = c),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: cents == null ? null : () => Navigator.pop(context, cents),
          style: TextButton.styleFrom(foregroundColor: AppColors.loss),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
