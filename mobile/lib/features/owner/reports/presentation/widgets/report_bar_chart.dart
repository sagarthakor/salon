import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A simple horizontal comparison chart (branch/staff/service revenue,
/// branch comparison, etc.) — always starts its value axis at 0 (see
/// instruction #30: "Do not create charts with misleading scales").
class ReportBarChart extends StatelessWidget {
  const ReportBarChart({super.key, required this.entries, this.color});

  /// (label, value) pairs, already sorted by the caller.
  final List<(String, double)> entries;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final barColor = color ?? Theme.of(context).colorScheme.primary;
    final maxValue = entries.map((e) => e.$2).fold<double>(0, (a, b) => b > a ? b : a);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                  final label = entries[index].$1;

                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label.length > 10 ? '${label.substring(0, 9)}…' : label,
                      style: Theme.of(context).textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < entries.length; i++)
              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: entries[i].$2, color: barColor, width: 18)]),
          ],
        ),
      ),
    );
  }
}
