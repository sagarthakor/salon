import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/day_of_week.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/branch_working_hour_entry.dart';
import '../providers/owner_branch_providers.dart';

class BranchWorkingHoursScreen extends ConsumerWidget {
  const BranchWorkingHoursScreen({super.key, required this.branchId});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoursAsync = ref.watch(branchWorkingHoursProvider(branchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Working hours')),
      body: hoursAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load working hours.',
          onRetry: () => ref.invalidate(branchWorkingHoursProvider(branchId)),
        ),
        data: (hours) => _WorkingHoursEditor(branchId: branchId, existing: hours),
      ),
    );
  }
}

class _WorkingHoursEditor extends ConsumerStatefulWidget {
  const _WorkingHoursEditor({required this.branchId, required this.existing});

  final String branchId;
  final List<BranchWorkingHourEntry> existing;

  @override
  ConsumerState<_WorkingHoursEditor> createState() => _WorkingHoursEditorState();
}

class _WorkingHoursEditorState extends ConsumerState<_WorkingHoursEditor> {
  late List<BranchWorkingHourEntry> _days;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _days = List.generate(7, (day) {
      final matches = widget.existing.where((h) => h.dayOfWeek == day);
      return matches.isNotEmpty ? matches.first : BranchWorkingHourEntry(dayOfWeek: day, isOpen: false);
    });
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final entry = _days[index];
    final current = isStart ? entry.openingTime : entry.closingTime;
    final initial = current != null
        ? TimeOfDay(hour: int.parse(current.split(':')[0]), minute: int.parse(current.split(':')[1]))
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _days[index] = isStart ? entry.copyWith(openingTime: formatted) : entry.copyWith(closingTime: formatted);
    });
  }

  Future<void> _save() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(ownerBranchRepositoryProvider).updateWorkingHours(widget.branchId, _days);
      ref.invalidate(branchWorkingHoursProvider(widget.branchId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Working hours updated.')));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: 7,
            itemBuilder: (context, index) {
              final entry = _days[index];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dayOfWeekLabel(index), style: Theme.of(context).textTheme.titleSmall),
                          Switch(
                            value: entry.isOpen,
                            onChanged: (value) => setState(() {
                              _days[index] = value
                                  ? entry.copyWith(
                                      isOpen: true,
                                      openingTime: entry.openingTime ?? '09:00',
                                      closingTime: entry.closingTime ?? '20:00',
                                    )
                                  : BranchWorkingHourEntry(dayOfWeek: index, isOpen: false);
                            }),
                          ),
                        ],
                      ),
                      if (entry.isOpen)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _pickTime(index, true),
                                child: Text(entry.openingTime ?? 'Start'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _pickTime(index, false),
                                child: Text(entry.closingTime ?? 'End'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: PrimaryButton(label: 'Save', isLoading: _isSubmitting, onPressed: _save),
        ),
      ],
    );
  }
}
