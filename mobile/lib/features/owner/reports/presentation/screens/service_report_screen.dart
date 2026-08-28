import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/service_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class ServiceReportScreen extends StatelessWidget {
  const ServiceReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<ServiceReport>(
      title: 'Services',
      provider: serviceReportProvider,
      showBranchFilter: true,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Services booked', value: '${report.totalServicesBooked}'),
              ReportStatCard(label: 'Total bookings', value: '${report.totalBookings}'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Most booked services', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.services.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.services.map((r) => Card(
            child: ListTile(
              title: Text((r['service_name'] ?? '—').toString()),
              subtitle: Text('${r['bookings']} bookings · ${r['completed_bookings']} completed · avg ₹${r['average_price']}'),
              trailing: Text('₹${r['net_value']}', style: Theme.of(context).textTheme.titleSmall),
            ),
          )),
          const SizedBox(height: AppSpacing.lg),
          Text('By category', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.byCategory.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.byCategory.map((r) => ListTile(
            dense: true,
            title: Text((r['category_name'] ?? '—').toString()),
            subtitle: Text('${((r['percent_of_service_bookings'] as num? ?? 0) * 100).toStringAsFixed(1)}% of bookings'),
            trailing: Text('₹${r['revenue']}'),
          )),
        ],
      ),
    );
  }
}
