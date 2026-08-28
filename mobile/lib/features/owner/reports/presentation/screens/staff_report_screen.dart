import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/staff_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class StaffReportScreen extends StatelessWidget {
  const StaffReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<StaffReport>(
      title: 'Staff performance',
      provider: staffReportProvider,
      showBranchFilter: true,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Total staff', value: '${report.totalStaff}'),
              ReportStatCard(label: 'Active staff', value: '${report.activeStaff}'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (report.staff.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.staff.map((r) {
            final utilization = r['utilization_percent'];

            return Card(
              child: ListTile(
                title: Text((r['staff_name'] ?? '—').toString()),
                subtitle: Text(
                  '${r['assigned_bookings']} assigned · ${r['completed_bookings']} completed · '
                  '${((r['completion_rate'] as num? ?? 0) * 100).toStringAsFixed(0)}% completion'
                  '${utilization != null ? ' · ${(utilization as num).toStringAsFixed(0)}% utilized' : ''}',
                ),
                trailing: Text('₹${r['net_revenue']}', style: Theme.of(context).textTheme.titleSmall),
                isThreeLine: false,
              ),
            );
          }),
        ],
      ),
    );
  }
}
