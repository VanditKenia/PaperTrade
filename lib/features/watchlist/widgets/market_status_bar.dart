import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../data/price_stream_service.dart';
import '../watchlist_provider.dart';

/// "● Live   Market open" row under the Watchlist title (UI_UX.md §3.1).
class MarketStatusBar extends ConsumerWidget {
  const MarketStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = Theme.of(context).textTheme.labelMedium;
    final status = ref.watch(connectionStatusProvider).value;
    final marketOpen = ref.watch(marketOpenProvider).value;

    final connection = switch (status) {
      ConnectionStatus.live => Row(
        spacing: 6,
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.gain),
          Text('Live', style: style),
        ],
      ),
      ConnectionStatus.reconnecting => Row(
        spacing: 6,
        children: [
          const SizedBox.square(
            dimension: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          Text(
            'Reconnecting…',
            style: style?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      // Offline has its own banner; connecting is too brief to mention.
      _ => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        spacing: 16,
        children: [
          connection,
          if (marketOpen != null)
            Text(
              marketOpen ? 'Market open' : 'Market closed',
              style: style?.copyWith(
                color: marketOpen ? AppColors.gain : AppColors.warning,
              ),
            ),
        ],
      ),
    );
  }
}
