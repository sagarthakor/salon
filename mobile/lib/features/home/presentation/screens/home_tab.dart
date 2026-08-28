import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../booking/data/models/booking.dart';
import '../../../booking/presentation/providers/booking_providers.dart';
import '../../../salon/data/models/branch.dart';
import '../../../salon/data/models/customer_salon.dart';
import '../../../salon/presentation/providers/salon_providers.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final salonsAsync = ref.watch(mySalonsProvider);
    final upcomingAsync = ref.watch(upcomingBookingProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Hi, ${user?.name.split(' ').first ?? 'there'}')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mySalonsProvider);
          ref.invalidate(upcomingBookingProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('Upcoming appointment', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            upcomingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (booking) => booking == null
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No upcoming appointments yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : _UpcomingBookingCard(booking: booking),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Book with your salon', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            salonsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: LoadingView(),
              ),
              error: (error, _) => ErrorView(
                message: 'Could not load your salons.',
                onRetry: () => ref.invalidate(mySalonsProvider),
              ),
              data: (salons) => salons.isEmpty
                  ? const EmptyView(
                      icon: Icons.storefront_outlined,
                      message:
                          "You're not registered as a customer at any salon yet.\nAsk your salon to add you as a customer.",
                    )
                  : Column(
                      children: salons.map((salon) => _SalonCard(salon: salon)).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalonCard extends ConsumerWidget {
  const _SalonCard({required this.salon});

  final CustomerSalon salon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              salon.salon?.name ?? salon.tenantSlug,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...salon.branches.map((branch) => _BranchTile(branch: branch)),
          ],
        ),
      ),
    );
  }
}

class _BranchTile extends ConsumerWidget {
  const _BranchTile({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.storefront),
      title: Text(branch.name),
      subtitle: branch.address.isEmpty ? null : Text(branch.address.singleLine),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        ref.read(selectedBranchProvider.notifier).state = branch;
        context.push('/booking/services');
      },
    );
  }
}

class _UpcomingBookingCard extends StatelessWidget {
  const _UpcomingBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available),
        title: Text('${booking.bookingDate} at ${booking.startTime}'),
        subtitle: Text(booking.status.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => GoRouter.of(context).push('/bookings/${booking.id}'),
      ),
    );
  }
}
