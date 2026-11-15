import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/animated_number.dart';
import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/api_errors.dart';
import '../../../domain/models/chart_range.dart';
import '../../../domain/models/stock.dart';
import '../stock_detail_provider.dart';
import 'price_chart.dart';

/// Change for the selected range, the chart, and the 1D · 1W · 1M · 6M · 1Y
/// chips (UI_UX.md §3.3).
class RangeChart extends ConsumerStatefulWidget {
  const RangeChart({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<RangeChart> createState() => _RangeChartState();
}

class _RangeChartState extends ConsumerState<RangeChart> {
  ChartRange _range = ChartRange.day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = text.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    final symbol = widget.symbol;
    final key = (symbol: symbol, range: _range);
    final history = ref.watch(historyProvider(key));
    // Watched on every range, not just 1D: this keeps the symbol subscribed
    // and the ticks collecting while the user looks at other ranges.
    final ticks = ref.watch(liveTicksProvider(symbol));
    final points = chartPoints(_range, history.value ?? const [], ticks);

    final error = history.hasError ? history.error : null;
    // Retrying can't fix a missing key or an unsupported symbol.
    final canRetry = error != null && error is! HistoryUnavailableError;
    Widget errorRow() => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Text(errorMessage(error!), style: secondary)),
        if (canRetry)
          TextButton(
            onPressed: ref.read(historyProvider(key).notifier).reload,
            child: const Text('Retry'),
          ),
      ],
    );

    final first = points.firstOrNull?.priceCents;
    final change = points.length < 2 ? null : points.last.priceCents - first!;
    final caption = _range == ChartRange.day && isCrypto(symbol)
        ? 'past 24 hours'
        : _range.caption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed height so the chart doesn't jump while the change loads.
        SizedBox(
          height: 24,
          child: change == null
              ? null
              : AnimatedNumber(
                  '${formatChange(change, first!)} $caption',
                  style: text.bodyLarge?.copyWith(color: changeColor(change)),
                  alignment: Alignment.centerLeft,
                ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: points.isNotEmpty
              ? PriceChart(
                  points: points,
                  // By the range's direction, not the last tick.
                  color: (change ?? 0) < 0 ? AppColors.loss : AppColors.gain,
                  formatTime: (t) => _formatTime(_range, t),
                )
              : history.isLoading
              ? const _ChartSkeleton()
              : error != null
              ? Center(child: errorRow())
              : Center(
                  child: Text('No chart data for this range', style: secondary),
                ),
        ),
        // 1D can still draw live ticks when history failed: say so below.
        if (error != null && points.isNotEmpty) errorRow(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final r in ChartRange.values)
              ChoiceChip(
                label: Text(r.label),
                selected: r == _range,
                onSelected: (_) => setState(() => _range = r),
              ),
          ],
        ),
      ],
    );
  }
}

String _formatTime(ChartRange range, DateTime t) => switch (range) {
  ChartRange.day => DateFormat.jm().format(t.toLocal()),
  ChartRange.week => DateFormat('EEE h:mm a').format(t.toLocal()),
  // Daily/weekly bars are dates, not moments: keep them in UTC so a
  // "Nov 11" bar doesn't show as Nov 10 west of Greenwich.
  _ => DateFormat.yMMMd().format(t),
};

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading chart',
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
