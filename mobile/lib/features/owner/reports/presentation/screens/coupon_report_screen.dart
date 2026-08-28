import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/coupon_report.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_scaffold.dart';
import '../widgets/report_stat_card.dart';

class CouponReportScreen extends StatelessWidget {
  const CouponReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportScaffold<CouponReport>(
      title: 'Coupons',
      provider: couponReportProvider,
      builder: (context, report) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ReportStatGrid(
            cards: [
              ReportStatCard(label: 'Coupons used', value: '${report.couponsUsed}'),
              ReportStatCard(label: 'Times used', value: '${report.totalTimesUsed}'),
              ReportStatCard(label: 'Discount given', value: '₹${report.totalDiscountGiven}'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (report.coupons.isEmpty) const EmptyView(message: 'No data for selected period.'),
          ...report.coupons.map((r) {
            final usageRate = r['usage_rate'];

            return Card(
              child: ListTile(
                title: Text((r['code'] ?? '—').toString()),
                subtitle: Text(
                  '${r['times_used']} uses · ${r['unique_customers']} customers'
                  '${usageRate != null ? ' · ${((usageRate as num) * 100).toStringAsFixed(0)}% of limit' : ''}',
                ),
                trailing: Text('₹${r['discount_given']}', style: Theme.of(context).textTheme.titleSmall),
              ),
            );
          }),
        ],
      ),
    );
  }
}
