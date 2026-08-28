import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/availability.dart';
import '../providers/booking_flow_controller.dart';
import '../providers/booking_flow_state.dart';
import '../providers/booking_providers.dart';
import 'booking_flow_scaffold.dart';

/// Step 2: date, optional specific-staff preference, and slot — all driven by
/// `GET /branches/{branch}/availability`. No slot is ever computed locally.
class BookingScheduleScreen extends ConsumerWidget {
  const BookingScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowState = ref.watch(bookingFlowControllerProvider);
    final controller = ref.read(bookingFlowControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose date & time')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Date', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _DateStrip(selected: flowState.date, onSelected: controller.setDate),
          const SizedBox(height: AppSpacing.lg),
          Text('Staff', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _StaffSelector(flowState: flowState, controller: controller),
          const SizedBox(height: AppSpacing.lg),
          Text('Available times', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _SlotArea(flowState: flowState, controller: controller),
        ],
      ),
      bottomNavigationBar: BookingFlowBottomBar(
        summaryLabel: flowState.selectedSlot == null
            ? 'Select a time slot'
            : '${flowState.date != null ? toApiDate(flowState.date!) : ''} · ${toDisplayTime(flowState.selectedSlot!.startTime)}',
        buttonLabel: 'Next',
        onPressed: flowState.selectedSlot != null ? () => context.push('/booking/summary') : null,
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
          final isSelected = selected != null &&
              selected!.year == day.year &&
              selected!.month == day.month &&
              selected!.day == day.day;
          return ChoiceChip(
            label: SizedBox(
              width: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_weekdayLabel(day.weekday)),
                  Text(day.day.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(day),
          );
        },
      ),
    );
  }

  String _weekdayLabel(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
}

class _StaffSelector extends StatelessWidget {
  const _StaffSelector({required this.flowState, required this.controller});

  final BookingFlowState flowState;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final staffOptions = flowState.availability?.staff ?? const <StaffOption>[];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          label: const Text('Any available staff'),
          selected: flowState.staffMode == StaffSelectionMode.any,
          onSelected: (_) => controller.setStaffMode(StaffSelectionMode.any),
        ),
        for (final staff in staffOptions)
          ChoiceChip(
            label: Text(staff.name),
            selected: flowState.staffMode == StaffSelectionMode.specific && flowState.selectedStaffId == staff.id,
            onSelected: (_) => controller.selectStaff(staff.id),
          ),
        if (staffOptions.isEmpty && flowState.date != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('Staff options appear once a date is selected.'),
          ),
      ],
    );
  }
}

class _SlotArea extends StatelessWidget {
  const _SlotArea({required this.flowState, required this.controller});

  final BookingFlowState flowState;
  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    if (flowState.date == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text('Choose a date to see available times.'),
      );
    }
    if (flowState.isLoadingAvailability) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xl), child: LoadingView());
    }
    if (flowState.availabilityError != null) {
      return ErrorView(message: flowState.availabilityError!, onRetry: controller.loadAvailability);
    }
    final slots = flowState.availability?.slots ?? const [];
    if (slots.isEmpty) {
      return const EmptyView(
        icon: Icons.event_busy,
        message: 'No time slots are available for this date. Please try another date.',
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: slots.map((slot) {
        final isSelected = flowState.selectedSlot?.startTime == slot.startTime;
        return ChoiceChip(
          label: Text(toDisplayTime(slot.startTime)),
          selected: isSelected,
          onSelected: (_) => controller.selectSlot(slot),
        );
      }).toList(),
    );
  }
}
