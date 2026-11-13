import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';

/// Simple line of prices in arrival order. The x axis is the point index,
/// not time: ticks arrive irregularly, and an even spacing reads better.
class PriceChart extends StatelessWidget {
  const PriceChart({
    super.key,
    required this.pointsCents,
    required this.color,
    this.prevCloseCents = 0,
  });

  final List<int> pointsCents;
  final Color color;
  final int prevCloseCents; // 0 = unknown, no reference line

  @override
  Widget build(BuildContext context) {
    // Doubles are fine here: they're only pixel positions, not money.
    final spots = [
      for (var i = 0; i < pointsCents.length; i++)
        FlSpot(i.toDouble(), pointsCents[i] / 100),
    ];
    final low = pointsCents.reduce(min) / 100;
    final high = pointsCents.reduce(max) / 100;
    // Headroom above and below; also stops a flat line (low == high) from
    // collapsing the axis to zero height.
    final pad = max((high - low) * 0.1, 0.01);
    final minY = low - pad;
    final maxY = high + pad;
    final prevClose = prevCloseCents / 100;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        // Prev close is a reference, not data: skip it when it's outside the
        // zoomed range rather than stretching the axis to fit it.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (prevCloseCents > 0 && prevClose >= minY && prevClose <= maxY)
              HorizontalLine(
                y: prevClose,
                color: AppColors.textSecondary,
                strokeWidth: 1,
                dashArray: const [4, 4],
              ),
          ],
        ),
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: color,
            barWidth: 2,
            isCurved: true,
            // Without this, curves can overshoot past the real high/low.
            preventCurveOverShooting: true,
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
