import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/customer_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_line_chart.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class CustomerReportScreen extends StatelessWidget {
  const CustomerReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<CustomerReport>(
      title: 'Customers',
      provider: customerReportProvider,
      showBranchFilter: true,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Total customers', value: '${report.summary.totalCustomers}'),
              ReportStatCard(label: 'New', value: '${report.summary.newCustomers}'),
              ReportStatCard(label: 'Returning', value: '${report.summary.returningCustomers}'),
              ReportStatCard(label: 'Active', value: '${report.summary.activeCustomers}'),
              ReportStatCard(
                label: 'Repeat booking rate',
                value: report.summary.repeatBookingRate != null ? '${(report.summary.repeatBookingRate! * 100).toStringAsFixed(1)}%' : '—',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('New customers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          report.series.isEmpty
              ? const EmptyView(message: 'No data for selected period.')
              : ReportLineChart(series: report.series, metricKey: 'new_customers'),
          const SizedBox(height: AppSpacing.lg),
          Text('Top customers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.topCustomers.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.topCustomers.map((r) => Card(
            child: ListTile(
              title: Text((r['customer_name'] ?? 'Customer').toString()),
              subtitle: Text('${r['completed_bookings']} completed · last visit ${r['last_visit'] ?? '—'}'),
              trailing: Text('₹${r['total_spend']}', style: Theme.of(context).textTheme.titleSmall),
            ),
          )),
        ],
      ),
    );
  }
}
