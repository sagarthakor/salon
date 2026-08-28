import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/membership_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class MembershipReportScreen extends StatelessWidget {
  const MembershipReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<MembershipReport>(
      title: 'Membership',
      provider: membershipReportProvider,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Total plans', value: '${report.totalPlans}'),
              ReportStatCard(label: 'Active', value: '${report.activeMemberships}'),
              ReportStatCard(label: 'Expired', value: '${report.expiredMemberships}'),
              ReportStatCard(label: 'Cancelled', value: '${report.cancelledMemberships}'),
              ReportStatCard(label: 'Membership revenue', value: '₹${report.membershipRevenue}', icon: Icons.currency_rupee),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Popular plans', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (report.byPlan.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.byPlan.map((r) => ListTile(
            dense: true,
            title: Text((r['plan_name'] ?? '—').toString()),
            trailing: Text('${r['memberships']}'),
          )),
        ],
      ),
    );
  }
}
