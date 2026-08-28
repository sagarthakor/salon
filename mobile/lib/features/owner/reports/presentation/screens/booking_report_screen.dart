import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/booking_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_line_chart.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class BookingReportScreen extends StatelessWidget {
  const BookingReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<BookingReport>(
      title: 'Bookings',
      provider: bookingReportProvider,
      showBranchFilter: true,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Total', value: '${report.summary.total}'),
              ReportStatCard(label: 'Completed', value: '${report.summary.countFor('completed')}'),
              ReportStatCard(label: 'Cancelled', value: '${report.summary.countFor('cancelled')}'),
              ReportStatCard(label: 'No-show', value: '${report.summary.countFor('no_show')}'),
              ReportStatCard(label: 'Cancellation rate', value: '${(report.summary.cancellationRate * 100).toStringAsFixed(1)}%'),
              ReportStatCard(label: 'No-show rate', value: '${(report.summary.noShowRate * 100).toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Booking trend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          report.series.isEmpty
              ? const EmptyView(message: 'No data for selected period.')
              : ReportLineChart(series: report.series, metricKey: 'total'),
          const SizedBox(height: AppSpacing.lg),
          Text('By branch', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.byBranch.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.byBranch.map((r) => Card(
            child: ListTile(
              title: Text((r['branch_name'] ?? '—').toString()),
              subtitle: Text('${r['completed']} completed · ${r['cancelled']} cancelled · ${r['no_show']} no-show'),
              trailing: Text('${r['total']}', style: Theme.of(context).textTheme.titleSmall),
            ),
          )),
          const SizedBox(height: AppSpacing.lg),
          Text('Cancellation reasons', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.cancellationReasons.isEmpty) const EmptyView(message: 'No cancellations in this period.'),
          ...report.cancellationReasons.map((r) => ListTile(
            dense: true,
            title: Text((r['reason'] ?? '—').toString()),
            trailing: Text('${r['count']}'),
          )),
        ],
      ),
    );
  }
}
