import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/models/report_series_point.dart';

/// Renders one metric of a backend-computed time series as a line chart.
/// Flutter never buckets or sums anything here — every point/value already
/// came from `ReportSeriesBuilder` on the backend (zero-filled, grouped by
/// day/week/month). The Y axis always starts at 0 so the chart can't imply a
/// trend more dramatic than the real numbers.
class ReportLineChart extends StatelessWidget {
  const ReportLineChart({super.key, required this.series, required this.metricKey, this.color});

  final List<ReportSeriesPoint> series;
  final String metricKey;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return const SizedBox.shrink();
    }
    final lineColor = color ?? Theme.of(context).colorScheme.primary;
    final spots = [
      for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i].valueFor(metricKey).toDouble()),
    ];
    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => b > a ? b : a);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (series.length / 5).clamp(1, series.length).toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= series.length) return const SizedBox.shrink();
                  final date = series[index].date;

                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(date.length >= 10 ? date.substring(5) : date, style: Theme.of(context).textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: lineColor.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}
