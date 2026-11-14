import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../watchlist_provider.dart';

/// Amber "Offline" strip at the top of price screens (UI_UX.md §4). Takes
/// no space while online.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isOfflineProvider)) return const SizedBox.shrink();
    return Semantics(
      // Screen readers announce it when it appears.
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: AppColors.warning,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(
          spacing: 8,
          children: [
            Icon(Icons.cloud_off, size: 18, color: AppColors.bg),
            Text(
              'Offline — showing last prices',
              style: TextStyle(
                color: AppColors.bg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
