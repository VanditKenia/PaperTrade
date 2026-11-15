import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../domain/models/price_point.dart';

/// Line of money values (prices, or portfolio value on Stats) with a
/// touch/drag crosshair. The x axis is the point index, not time: markets
/// close overnight and on weekends, and spacing by time would leave big
/// empty gaps (and live ticks arrive irregularly).
class PriceChart extends StatelessWidget {
  const PriceChart({
    super.key,
    required this.points,
    required this.color,
    required this.formatTime,
  });

  final List<PricePoint> points;
  final Color color;
  final String Function(DateTime) formatTime; // tooltip time label

  @override
  Widget build(BuildContext context) {
    // Doubles are fine here: they're only pixel positions, not money.
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].priceCents / 100),
    ];
    final cents = points.map((p) => p.priceCents);
    final low = cents.reduce(min) / 100;
    final high = cents.reduce(max) / 100;
    // Headroom above and below; also stops a flat line (low == high) from
    // collapsing the axis to zero height.
    final pad = max((high - low) * 0.1, 0.01);

    return LineChart(
      LineChartData(
        minY: low - pad,
        maxY: high + pad,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (_, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                const FlLine(
                  color: AppColors.textSecondary,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                FlDotData(
                  getDotPainter: (_, _, _, _) =>
                      FlDotCirclePainter(radius: 4, color: color),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceAlt,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  // Money comes from the int cents, not the double y.
                  '${formatCents(points[spot.spotIndex].priceCents)}\n',
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  children: [
                    TextSpan(
                      text: formatTime(points[spot.spotIndex].time),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
