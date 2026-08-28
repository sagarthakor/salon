import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/booking.dart';
import '../providers/booking_providers.dart';

class BookingDetailsScreen extends ConsumerStatefulWidget {
  const BookingDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends ConsumerState<BookingDetailsScreen> {
  bool _isCancelling = false;

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _CancelDialog(),
    );
    if (reason == null) return;
    setState(() => _isCancelling = true);
    try {
      await ref.read(bookingRepositoryProvider).cancelBooking(widget.bookingId, reason: reason);
      ref.invalidate(bookingDetailsProvider(widget.bookingId));
      ref.invalidate(myBookingsControllerProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingDetailsProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: bookingAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this booking.',
          onRetry: () => ref.invalidate(bookingDetailsProvider(widget.bookingId)),
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
            if (booking.status.isUpcoming) ...[
              OutlinedButton.icon(
                onPressed: () => context.push('/bookings/${booking.id}/reschedule'),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Reschedule'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _isCancelling ? null : _cancel,
                icon: _isCancelling
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_outlined),
                label: const Text('Cancel booking'),
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              ),
            ],
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
            Text('${booking.bookingDate} · ${booking.startTime} – ${booking.endTime}'),
            const SizedBox(height: AppSpacing.xs),
            Text('Total: ₹${booking.total}'),
            if (booking.notes != null && booking.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Notes: ${booking.notes}'),
            ],
            if (booking.cancellationReason != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Cancellation reason: ${booking.cancellationReason}'),
            ],
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
                    Expanded(
                      child: Text('${item.serviceName} · ${item.staffName ?? 'Staff'} '
                          '(${item.startTime}–${item.endTime})'),
                    ),
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
                  '${entry.fromStatus?.label ?? 'Created'} → ${entry.toStatus.label}'
                  '${entry.reason != null ? ' (${entry.reason})' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel booking?'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Reason (optional)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep booking')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Cancel booking'),
        ),
      ],
    );
  }
}
