import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/day_of_week.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../owner/staff/data/models/staff_schedule.dart';
import '../../../owner/staff/presentation/providers/staff_providers.dart';

/// My Schedule — working hours, breaks, and leave, view-only. The backend
/// only authorizes a staff member to *view* these (`Gate::authorize('view',
/// ...)` on each `index()`); every write endpoint requires `managedTenant()`
/// (owner/super-admin only — see STAFF_APP_ARCHITECTURE.md), so there is no
/// edit UI here — that would show controls that always fail with 403.
class StaffScheduleScreen extends ConsumerWidget {
  const StaffScheduleScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workingHoursAsync = ref.watch(staffWorkingHoursProvider(staffId));
    final breaksAsync = ref.watch(staffBreaksProvider(staffId));
    final leavesAsync = ref.watch(staffLeavesProvider(staffId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Schedule')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffWorkingHoursProvider(staffId));
          ref.invalidate(staffBreaksProvider(staffId));
          ref.invalidate(staffLeavesProvider(staffId));
        },
        child: workingHoursAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(message: 'Could not load your schedule.', onRetry: () => ref.invalidate(staffWorkingHoursProvider(staffId))),
              ),
            ],
          ),
          data: (workingHours) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text('Working hours', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Column(
                  children: (List.of(workingHours)..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek)))
                      .map((entry) => _WorkingHourTile(entry: entry))
                      .toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Breaks', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              breaksAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Could not load breaks.'),
                data: (breaks) => breaks.isEmpty
                    ? const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('No breaks set.')))
                    : Card(child: Column(children: breaks.map((b) => _BreakTile(entry: b)).toList())),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Leave', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              leavesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Could not load leave.'),
                data: (leaves) => leaves.isEmpty
                    ? const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('No leave on record.')))
                    : Card(child: Column(children: leaves.map((l) => _LeaveTile(entry: l)).toList())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkingHourTile extends StatelessWidget {
  const _WorkingHourTile({required this.entry});

  final StaffWorkingHourEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(dayOfWeekLabel(entry.dayOfWeek)),
      trailing: entry.isWorking && entry.startTime != null && entry.endTime != null
          ? Text('${toDisplayTime(entry.startTime!)} – ${toDisplayTime(entry.endTime!)}')
          : Text('Off', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
}

class _BreakTile extends StatelessWidget {
  const _BreakTile({required this.entry});

  final StaffBreakEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(dayOfWeekLabel(entry.dayOfWeek)),
      trailing: Text('${toDisplayTime(entry.startTime)} – ${toDisplayTime(entry.endTime)}'),
    );
  }
}

class _LeaveTile extends StatelessWidget {
  const _LeaveTile({required this.entry});

  final StaffLeaveEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(entry.startDate == entry.endDate ? entry.startDate : '${entry.startDate} – ${entry.endDate}'),
      subtitle: entry.reason != null ? Text(entry.reason!) : null,
      trailing: Chip(label: Text(entry.status)),
    );
  }
}
