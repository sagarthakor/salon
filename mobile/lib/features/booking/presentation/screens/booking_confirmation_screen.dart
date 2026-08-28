import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../providers/booking_providers.dart';

/// Final step: shows the real, backend-assigned booking id/status/total —
/// never a client-generated confirmation number.
class BookingConfirmationScreen extends ConsumerWidget {
  const BookingConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingFlowControllerProvider).createdBooking;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Booking requested',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your salon will confirm this appointment shortly.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (booking != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Booking ID: ${booking.id}'),
                        const SizedBox(height: 4),
                        Text('Date: ${booking.bookingDate} at ${booking.startTime}'),
                        const SizedBox(height: 4),
                        Text('Status: ${booking.status.label}'),
                        const SizedBox(height: 4),
                        Text('Total: ₹${booking.total}'),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              if (booking != null)
                OutlinedButton(
                  onPressed: () {
                    ref.read(bookingFlowControllerProvider.notifier).reset();
                    context.go('/home');
                    context.push('/bookings/${booking.id}');
                  },
                  child: const Text('View booking'),
                ),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton(
                onPressed: () {
                  ref.read(bookingFlowControllerProvider.notifier).reset();
                  context.go('/home');
                },
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
