import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../booking/data/models/booking.dart';
import '../../../../booking/data/models/booking_status.dart';
import '../../../../booking/presentation/providers/booking_providers.dart';
import '../providers/owner_booking_providers.dart';

class OwnerBookingDetailsScreen extends ConsumerStatefulWidget {
  const OwnerBookingDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<OwnerBookingDetailsScreen> createState() => _OwnerBookingDetailsScreenState();
}

class _OwnerBookingDetailsScreenState extends ConsumerState<OwnerBookingDetailsScreen> {
  bool _isActing = false;

  Future<void> _transition(BookingStatus target) async {
    setState(() => _isActing = true);
    try {
      final repository = ref.read(bookingRepositoryProvider);
      if (target == BookingStatus.confirmed) {
        await repository.confirmBooking(widget.bookingId);
      } else if (target == BookingStatus.cancelled) {
        final reason = await _promptReason();
        if (reason == null) {
          setState(() => _isActing = false);
          return;
        }
        await repository.ownerCancelBooking(widget.bookingId, reason: reason);
      } else {
        await repository.updateBookingStatus(widget.bookingId, status: target.apiValue);
      }
      ref.invalidate(ownerBookingDetailsProvider(widget.bookingId));
      ref.invalidate(ownerBookingsControllerProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking updated to ${target.label}.')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<String?> _promptReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep booking')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Cancel booking')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(ownerBookingDetailsProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: bookingAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this booking.',
          onRetry: () => ref.invalidate(ownerBookingDetailsProvider(widget.bookingId)),
        ),
        data: (booking) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _DetailCard(booking: booking),
            const SizedBox(height: AppSpacing.md),
            if (booking.items.isNotEmpty) _ItemsCard(booking: booking),
            const SizedBox(height: AppSpacing.md),
            if (booking.statusHistory.isNotEmpty) _HistoryCard(booking: booking),
            const SizedBox(height: AppSpacing.lg),
            if (booking.status.nextActions.isNotEmpty) ...[
              Text('Actions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: booking.status.nextActions
                    .map((action) => FilledButton.tonal(
                          onPressed: _isActing ? null : () => _transition(action),
                          child: Text(action.label),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (booking.status.isUpcoming)
              OutlinedButton.icon(
                onPressed: () => context.push('/owner/bookings/${widget.bookingId}/reschedule'),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Reschedule'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Booking #${booking.id.substring(0, 8)}', style: Theme.of(context).textTheme.titleMedium),
                Chip(label: Text(booking.status.label)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (booking.customer != null) ...[
              Text('Customer: ${booking.customer!.name}'),
              Text('Phone: ${booking.customer!.phone}'),
            ],
            Text('${booking.bookingDate} · ${booking.startTime} – ${booking.endTime}'),
            if (booking.discount > 0) ...[
              Text('Subtotal: ₹${booking.subtotal}'),
              if (booking.couponDiscount > 0) Text('Coupon (${booking.couponCode ?? ''}): -₹${booking.couponDiscount}'),
              if (booking.membershipDiscount > 0) Text('Membership: -₹${booking.membershipDiscount}'),
              if (booking.loyaltyDiscount > 0) Text('Loyalty (${booking.loyaltyPointsRedeemed} pts): -₹${booking.loyaltyDiscount}'),
            ],
            Text('Total: ₹${booking.total}'),
            if (booking.notes != null && booking.notes!.isNotEmpty) Text('Notes: ${booking.notes}'),
            if (booking.cancellationReason != null) Text('Cancellation reason: ${booking.cancellationReason}'),
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Services', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final item in booking.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${item.serviceName} · ${item.staffName ?? 'Staff'} (${item.startTime}–${item.endTime})')),
                    Text('₹${item.servicePrice}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status history', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final entry in booking.statusHistory)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${entry.fromStatus?.label ?? 'Created'} → ${entry.toStatus.label}${entry.reason != null ? ' (${entry.reason})' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
