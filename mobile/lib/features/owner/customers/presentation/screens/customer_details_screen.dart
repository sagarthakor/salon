import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../bookings/presentation/providers/owner_bookings_controller.dart';
import '../../../bookings/presentation/providers/owner_booking_providers.dart';
import '../providers/owner_customer_providers.dart';

class CustomerDetailsScreen extends ConsumerWidget {
  const CustomerDetailsScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(ownerCustomerDetailsProvider(customerId));
    final summaryAsync = ref.watch(ownerCustomerSummaryProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => context.push('/owner/customers/$customerId/edit')),
        ],
      ),
      body: customerAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this customer.',
          onRetry: () => ref.invalidate(ownerCustomerDetailsProvider(customerId)),
        ),
        data: (customer) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(customer.name, style: Theme.of(context).textTheme.titleMedium),
                        Chip(label: Text(customer.status)),
                      ],
                    ),
                    Text('Phone: ${customer.phone}'),
                    if (customer.email != null) Text('Email: ${customer.email}'),
                    if (customer.gender != null) Text('Gender: ${customer.gender}'),
                    if (customer.address != null) Text('Address: ${customer.address}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            summaryAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(error is ApiException ? error.message : 'Could not load summary.'),
              data: (summary) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatRow(label: 'Total visits', value: '${summary.totalVisits}'),
                      _StatRow(label: 'Completed', value: '${summary.completedAppointments}'),
                      _StatRow(label: 'Cancelled', value: '${summary.cancelledAppointments}'),
                      _StatRow(label: 'No-shows', value: '${summary.noShowCount}'),
                      _StatRow(label: 'Total spent', value: '₹${summary.totalSpent}'),
                      _StatRow(label: 'Last visit', value: summary.lastVisitAt ?? 'Never'),
                      _StatRow(
                        label: 'Upcoming',
                        value: summary.upcomingAppointment != null
                            ? '${summary.upcomingAppointment!.bookingDate} ${summary.upcomingAppointment!.startTime}'
                            : 'None',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_note),
                title: const Text('View bookings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ref.read(ownerBookingsControllerProvider.notifier).setFilters(OwnerBookingFilters(customerId: customerId));
                  context.push('/owner/bookings');
                },
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: const Text('Internal notes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/owner/customers/$customerId/notes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
      ),
    );
  }
}
