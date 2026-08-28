import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/loyalty_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class LoyaltyReportScreen extends StatelessWidget {
  const LoyaltyReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<LoyaltyReport>(
      title: 'Loyalty',
      provider: loyaltyReportProvider,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Points earned', value: '${report.pointsEarned}'),
              ReportStatCard(label: 'Points redeemed', value: '${report.pointsRedeemed}'),
              ReportStatCard(label: 'Points expired', value: '${report.pointsExpired}'),
              ReportStatCard(label: 'Adjusted', value: '${report.pointsAdjusted}'),
              ReportStatCard(label: 'Outstanding', value: '${report.outstandingPoints}', icon: Icons.stars),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.transactions.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.transactions.map((r) => ListTile(
            dense: true,
            title: Text((r['type'] ?? '—').toString()),
            subtitle: Text((r['description'] ?? '').toString()),
            trailing: Text('${r['points']}'),
          )),
        ],
      ),
    );
  }
}
