import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/revenue_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_bar_chart.dart';
import '../widgets/report_line_chart.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class RevenueReportScreen extends StatelessWidget {
  const RevenueReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<RevenueReport>(
      title: 'Revenue',
      provider: revenueReportProvider,
      showBranchFilter: true,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Completed bookings', value: '${report.summary.completedBookings}'),
              ReportStatCard(label: 'Gross value', value: '₹${report.summary.grossBookingValue}'),
              ReportStatCard(label: 'Discount', value: '₹${report.summary.discount}'),
              ReportStatCard(label: 'Net revenue', value: '₹${report.summary.netRevenue}', icon: Icons.currency_rupee),
              ReportStatCard(label: 'Avg. booking value', value: '₹${report.summary.averageBookingValue}'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Revenue trend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          report.series.isEmpty
              ? const EmptyView(message: 'No data for selected period.')
              : ReportLineChart(series: report.series, metricKey: 'revenue'),
          const SizedBox(height: AppSpacing.lg),
          Text('By branch', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          report.byBranch.isEmpty
              ? const EmptyView(message: 'No data for selected period.')
              : ReportBarChart(entries: [for (final r in report.byBranch) ((r['branch_name'] ?? '—') as String, double.tryParse(r['revenue'].toString()) ?? 0)]),
          const SizedBox(height: AppSpacing.lg),
          Text('By staff', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(context, report.byStaff, 'staff_name', 'net_revenue'),
          const SizedBox(height: AppSpacing.lg),
          Text('By service', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(context, report.byService, 'service_name', 'net_value'),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context, List<Map<String, dynamic>> rows, String labelKey, String valueKey) {
    if (rows.isEmpty) {
      return const [EmptyView(message: 'No data for selected period.')];
    }

    return rows.map((r) => Card(
      child: ListTile(
        title: Text((r[labelKey] ?? '—').toString()),
        subtitle: Text('${r['bookings']} bookings'),
        trailing: Text('₹${r[valueKey]}', style: Theme.of(context).textTheme.titleSmall),
      ),
    )).toList();
  }
}
