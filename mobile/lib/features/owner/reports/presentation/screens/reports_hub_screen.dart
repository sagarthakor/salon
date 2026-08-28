import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';

/// Entry point for Phase 13 — reached from the Owner App's More tab (see
/// instruction #48: reports live under More/Dashboard, not their own bottom
/// tab). Lists every report section; each keeps the shared date-range/branch
/// filter from `reportFilterProvider` as the owner moves between them.
class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _ReportTile(icon: Icons.dashboard_outlined, title: 'Overview', subtitle: 'Bookings, revenue, and activity for the selected period', onTap: () => context.push('/owner/reports/overview')),
          _ReportTile(icon: Icons.payments_outlined, title: 'Revenue', subtitle: 'Gross value, discounts, and net revenue', onTap: () => context.push('/owner/reports/revenue')),
          _ReportTile(icon: Icons.event_note_outlined, title: 'Bookings', subtitle: 'Status breakdown, trend, cancellations', onTap: () => context.push('/owner/reports/bookings')),
          _ReportTile(icon: Icons.groups_outlined, title: 'Customers', subtitle: 'New, returning, and top customers', onTap: () => context.push('/owner/reports/customers')),
          _ReportTile(icon: Icons.content_cut_outlined, title: 'Services', subtitle: 'Most booked services and categories', onTap: () => context.push('/owner/reports/services')),
          _ReportTile(icon: Icons.badge_outlined, title: 'Staff performance', subtitle: 'Bookings, revenue, and utilization per staff', onTap: () => context.push('/owner/reports/staff')),
          _ReportTile(icon: Icons.storefront_outlined, title: 'Branches', subtitle: 'Compare bookings and revenue across branches', onTap: () => context.push('/owner/reports/branches')),
          _ReportTile(icon: Icons.sell_outlined, title: 'Coupons', subtitle: 'Usage and discount given per coupon', onTap: () => context.push('/owner/reports/coupons')),
          _ReportTile(icon: Icons.workspace_premium_outlined, title: 'Membership', subtitle: 'Active/expired plans and membership revenue', onTap: () => context.push('/owner/reports/memberships')),
          _ReportTile(icon: Icons.stars_outlined, title: 'Loyalty', subtitle: 'Points earned, redeemed, and outstanding', onTap: () => context.push('/owner/reports/loyalty')),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
