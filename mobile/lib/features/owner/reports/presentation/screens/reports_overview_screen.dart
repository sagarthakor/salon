import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../data/models/dashboard_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class ReportsOverviewScreen extends StatelessWidget {
  const ReportsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<DashboardReportSummary>(
      title: 'Overview',
      provider: dashboardReportProvider,
      showBranchFilter: true,
      builder: (context, summary) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('${summary.rangeFrom} to ${summary.rangeTo}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Total bookings', value: '${summary.bookingCount('total')}', icon: Icons.event_note),
              ReportStatCard(label: 'Completed', value: '${summary.bookingCount('completed')}'),
              ReportStatCard(label: 'Cancelled', value: '${summary.bookingCount('cancelled')}'),
              ReportStatCard(label: 'No-show', value: '${summary.bookingCount('no_show')}'),
              ReportStatCard(label: 'Revenue', value: '₹${summary.netRevenue}', icon: Icons.currency_rupee),
              ReportStatCard(label: 'Active staff', value: '${summary.activeStaff}', icon: Icons.people),
              ReportStatCard(label: 'Total customers', value: '${summary.totalCustomers}', icon: Icons.groups),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Next appointment', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          summary.nextAppointment == null
              ? const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('No upcoming appointments.')))
              : Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available),
                    title: Text('${summary.nextAppointment!['booking_date']} at ${summary.nextAppointment!['start_time']}'),
                    subtitle: Text((summary.nextAppointment!['customer_name'] as String?) ?? summary.nextAppointment!['status'] as String),
                  ),
                ),
        ],
      ),
    );
  }
}
