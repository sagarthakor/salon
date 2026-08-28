import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/dashboard_summary.dart';
import '../providers/dashboard_providers.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    // .select() narrows the rebuild trigger to just the user's identity —
    // this screen only reads the name, so an unrelated AuthState change
    // (e.g. a transient loading flag elsewhere) shouldn't rebuild it.
    final user = ref.watch(authControllerProvider.select((state) => state.user));

    return Scaffold(
      appBar: AppBar(title: Text('Hi, ${user?.name.split(' ').first ?? 'there'}')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
        child: summaryAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(message: 'Could not load the dashboard.', onRetry: () => ref.invalidate(dashboardSummaryProvider)),
              ),
            ],
          ),
          data: (summary) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text("Today's bookings", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _BookingCountsGrid(summary: summary),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(child: _StatCard(icon: Icons.currency_rupee, label: 'Revenue today', value: '₹${summary.revenueToday}')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.people,
                      label: 'Active staff',
                      value: '${summary.activeStaff}',
                      subtitle: summary.staffOnLeaveToday > 0 ? '${summary.staffOnLeaveToday} on leave today' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.groups,
                      label: 'Customers',
                      value: '${summary.totalCustomers}',
                      subtitle: summary.newCustomersThisMonth > 0 ? '+${summary.newCustomersThisMonth} this month' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Container()),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Next appointment', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              summary.nextAppointment == null
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text('No upcoming appointments.', style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    )
                  : Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_available),
                        title: Text('${summary.nextAppointment!.bookingDate} at ${summary.nextAppointment!.startTime}'),
                        subtitle: Text(summary.nextAppointment!.customerName ?? summary.nextAppointment!.status),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/owner/bookings/${summary.nextAppointment!.id}'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingCountsGrid extends StatelessWidget {
  const _BookingCountsGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('Total', summary.totalBookingsToday),
      ('Pending', summary.countFor('pending')),
      ('Confirmed', summary.countFor('confirmed')),
      ('In service', summary.countFor('in_service')),
      ('Completed', summary.countFor('completed')),
      ('Cancelled', summary.countFor('cancelled')),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: entries
          .map((e) => SizedBox(width: 100, child: _StatCard(label: e.$1, value: '${e.$2}')))
          .toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({this.icon, required this.label, required this.value, this.subtitle});

  final IconData? icon;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}
