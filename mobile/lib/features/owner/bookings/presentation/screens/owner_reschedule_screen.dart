import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/utils/time_format.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../booking/data/models/availability.dart';
import '../../../../booking/data/models/booking.dart';
import '../../../../booking/presentation/providers/booking_providers.dart';
import '../providers/owner_booking_providers.dart';

/// Owner-side equivalent of the customer app's `RescheduleScreen` — same
/// backend contract (existing service/staff composition kept, only
/// date/time revalidated), different base path (`/bookings/{id}/reschedule`
/// via `ownerRescheduleBooking`, never bypassing the cancellation-style
/// window checks a customer would hit — reschedule has no such window).
class OwnerRescheduleScreen extends ConsumerStatefulWidget {
  const OwnerRescheduleScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<OwnerRescheduleScreen> createState() => _OwnerRescheduleScreenState();
}

class _OwnerRescheduleScreenState extends ConsumerState<OwnerRescheduleScreen> {
  DateTime? _date;
  AvailabilitySlot? _selectedSlot;
  AvailabilityResult? _availability;
  bool _isLoadingAvailability = false;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _loadAvailability(Booking booking) async {
    if (_date == null) return;
    setState(() {
      _isLoadingAvailability = true;
      _error = null;
      _selectedSlot = null;
    });
    final serviceIds = booking.items.map((i) => i.serviceId).whereType<String>().toList();
    final staffIds = booking.items.map((i) => i.staffId).toSet();
    final staffId = staffIds.length == 1 ? staffIds.first : null;
    try {
      final result = await ref
          .read(bookingRepositoryProvider)
          .availability(branchId: booking.branchId, date: toApiDate(_date!), serviceIds: serviceIds, staffId: staffId);
      setState(() {
        _availability = result;
        _isLoadingAvailability = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _isLoadingAvailability = false;
        _error = e.message;
      });
    }
  }

  Future<void> _confirm(Booking booking) async {
    if (_date == null || _selectedSlot == null) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref
          .read(bookingRepositoryProvider)
          .ownerRescheduleBooking(booking.id, date: toApiDate(_date!), startTime: _selectedSlot!.startTime);
      ref.invalidate(ownerBookingDetailsProvider(booking.id));
      ref.invalidate(ownerBookingsControllerProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      final message = e.type == ApiErrorType.conflict ? 'That time is no longer available. Please choose another.' : e.message;
      setState(() {
        _isSubmitting = false;
        _error = message;
        _selectedSlot = null;
      });
      await _loadAvailability(booking);
      return;
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(ownerBookingDetailsProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Reschedule')),
      body: bookingAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => const ErrorView(message: 'Could not load this booking.'),
        data: (booking) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_error != null) _ErrorBanner(message: _error!),
            Text('Currently: ${booking.bookingDate} at ${booking.startTime}'),
            const SizedBox(height: AppSpacing.lg),
            Text('New date', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _DateStrip(
              selected: _date,
              onSelected: (day) {
                setState(() => _date = day);
                _loadAvailability(booking);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('New time', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (_date == null)
              const Text('Choose a date to see available times.')
            else if (_isLoadingAvailability)
              const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: LoadingView())
            else if ((_availability?.slots ?? []).isEmpty)
              const EmptyView(icon: Icons.event_busy, message: 'No slots available for this date.')
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _availability!.slots.map((slot) {
                  return ChoiceChip(
                    label: Text(toDisplayTime(slot.startTime)),
                    selected: _selectedSlot?.startTime == slot.startTime,
                    onSelected: (_) => setState(() => _selectedSlot = slot),
                  );
                }).toList(),
              ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Confirm reschedule',
              isLoading: _isSubmitting,
              onPressed: _selectedSlot != null ? () => _confirm(booking) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelected});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(21, (i) => DateTime(today.year, today.month, today.day + i));
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final day = days[index];
          final isSelected =
              selected != null && selected!.year == day.year && selected!.month == day.month && selected!.day == day.day;
          return ChoiceChip(
            label: SizedBox(width: 40, child: Text(day.day.toString(), textAlign: TextAlign.center)),
            selected: isSelected,
            onSelected: (_) => onSelected(day),
          );
        },
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
