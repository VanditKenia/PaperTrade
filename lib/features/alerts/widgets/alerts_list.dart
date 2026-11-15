import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../domain/models/price_alert.dart';
import '../alerts_provider.dart';

/// Alerts with delete, newest first. [symbol] limits it to one stock
/// (StockDetail); null lists all (Settings) and shows the symbol.
class AlertsList extends ConsumerWidget {
  const AlertsList({super.key, this.symbol});

  final String? symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final alerts = ref
        .watch(alertsProvider)
        .where((a) => symbol == null || a.symbol == symbol)
        .toList()
        .reversed;
    final secondary = text.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alerts only work while the app is open.', style: secondary),
        if (alerts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No price alerts', style: text.bodyMedium),
          ),
        for (final a in alerts)
          _AlertTile(key: ValueKey(a.id), alert: a, showSymbol: symbol == null),
      ],
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({super.key, required this.alert, required this.showSymbol});

  final PriceAlert alert;
  final bool showSymbol;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(alertsProvider.notifier).delete(alert.id);
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete the alert')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = alert;
    final firedAt = a.triggeredAt;
    final status = firedAt == null
        ? 'Waiting'
        : 'Triggered ${DateFormat.MMMd().add_jm().format(firedAt.toLocal())}'
              '${a.triggeredPriceCents == null ? '' : ' at ${formatCents(a.triggeredPriceCents!)}'}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        firedAt == null ? Icons.notifications_active_outlined : Icons.check,
        color: firedAt == null ? AppColors.accent : AppColors.textSecondary,
      ),
      title: Text(
        '${showSymbol ? '${a.symbol} · ' : ''}${alertCondition(a)}',
        style: tabularFigures,
      ),
      subtitle: Text(
        status,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete alert',
        onPressed: () => _delete(context, ref),
      ),
    );
  }
}
