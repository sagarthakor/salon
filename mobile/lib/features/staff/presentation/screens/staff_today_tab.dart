import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../booking/data/models/booking.dart';
import '../../../booking/data/models/booking_status.dart';
import '../../../owner/staff/presentation/providers/staff_providers.dart';
import '../../data/staff_working_status.dart';
import '../providers/staff_booking_providers.dart';

/// The staff app's landing tab — today's date, a real-time working status,
/// today's appointment counts, and a timeline of today's bookings. Every
/// number here is derived from real, already-fetched backend data (today's
/// bookings plus this staff member's own working hours/breaks/leave); see
/// STAFF_APP_ARCHITECTURE.md for why there is no separate "staff dashboard"
/// backend endpoint — none was needed.
class StaffTodayTab extends ConsumerWidget {
  const StaffTodayTab({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(staffTodayBookingsProvider(staffId));
    final workingHoursAsync = ref.watch(staffWorkingHoursProvider(staffId));
    final breaksAsync = ref.watch(staffBreaksProvider(staffId));
    final leavesAsync = ref.watch(staffLeavesProvider(staffId));
    final user = ref.watch(authControllerProvider).user;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text('Hi, ${user?.name.split(' ').first ?? 'there'}')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffTodayBookingsProvider(staffId));
          ref.invalidate(staffWorkingHoursProvider(staffId));
          ref.invalidate(staffBreaksProvider(staffId));
          ref.invalidate(staffLeavesProvider(staffId));
        },
        child: bookingsAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(
                  message: 'Could not load today\'s appointments.',
                  onRetry: () => ref.invalidate(staffTodayBookingsProvider(staffId)),
                ),
              ),
            ],
          ),
          data: (bookings) {
            final completed = bookings.where((b) => b.status == BookingStatus.completed).length;
            final cancelledOrNoShow = bookings.where((b) => b.status == BookingStatus.cancelled || b.status == BookingStatus.noShow).length;
            final remaining = bookings.length - completed - cancelledOrNoShow;
            Booking? next;
            for (final booking in bookings) {
              if (booking.status.isActive && booking.startTime.compareTo(_nowHHmm(now)) >= 0) {
                next = booking;
                break;
              }
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                workingHoursAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (workingHours) => breaksAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (breaks) => leavesAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (leaves) {
                        final status = deriveStaffWorkingStatus(now: now, workingHours: workingHours, breaks: breaks, leaves: leaves);
                        return _WorkingStatusBanner(status: status);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _CountCard(label: 'Total today', value: '${bookings.length}')),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _CountCard(label: 'Completed', value: '$completed')),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _CountCard(label: 'Remaining', value: '$remaining')),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Next appointment', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (next == null)
                  const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('No more appointments today.')))
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_available),
                      title: Text('${toDisplayTime(next.startTime)} · ${next.items.map((i) => i.serviceName).join(', ')}'),
                      subtitle: Text(next.customer?.name ?? 'Walk-in'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/staff/appointments/${next!.id}'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text("Today's timeline", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (bookings.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('No appointments today.')))
                else
                  ...bookings.map((booking) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _TimelineTile(booking: booking),
                  )),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _nowHHmm(DateTime now) => '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

class _WorkingStatusBanner extends StatelessWidget {
  const _WorkingStatusBanner({required this.status});

  final StaffWorkingStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      StaffWorkingStatus.workingNow => scheme.primaryContainer,
      StaffWorkingStatus.onBreak => scheme.tertiaryContainer,
      StaffWorkingStatus.offToday || StaffWorkingStatus.onLeave => scheme.surfaceContainerHighest,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10),
          const SizedBox(width: AppSpacing.sm),
          Text(status.label, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: SizedBox(width: 56, child: Text(toDisplayTime(booking.startTime), style: Theme.of(context).textTheme.labelMedium)),
        title: Text(booking.items.map((i) => i.serviceName).join(', ')),
        subtitle: Text(booking.customer?.name ?? 'Walk-in'),
        trailing: Chip(label: Text(booking.status.label)),
        onTap: () => context.push('/staff/appointments/${booking.id}'),
      ),
    );
  }
}
