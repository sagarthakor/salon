import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/branch_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_bar_chart.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class BranchReportScreen extends StatelessWidget {
  const BranchReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<BranchReport>(
      title: 'Branches',
      provider: branchReportProvider,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Branches', value: '${report.totalBranches}'),
              ReportStatCard(label: 'Total bookings', value: '${report.totalBookings}'),
              ReportStatCard(label: 'Total revenue', value: '₹${report.totalRevenue}'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Revenue by branch', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          report.branches.isEmpty
              ? const EmptyView(message: 'No data for selected period.')
              : ReportBarChart(entries: [for (final r in report.branches) ((r['branch_name'] ?? '—') as String, double.tryParse(r['revenue'].toString()) ?? 0)]),
          const SizedBox(height: AppSpacing.lg),
          ...report.branches.map((r) => Card(
            child: ListTile(
              title: Text((r['branch_name'] ?? '—').toString()),
              subtitle: Text(
                '${r['bookings']} bookings · '
                '${((r['completion_rate'] as num? ?? 0) * 100).toStringAsFixed(0)}% completed · '
                '${((r['cancellation_rate'] as num? ?? 0) * 100).toStringAsFixed(0)}% cancelled',
              ),
              trailing: Text('₹${r['revenue']}', style: Theme.of(context).textTheme.titleSmall),
            ),
          )),
        ],
      ),
    );
  }
}
