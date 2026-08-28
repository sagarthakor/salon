import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/day_of_week.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/staff_schedule.dart';
import '../providers/staff_providers.dart';

class StaffBreaksScreen extends ConsumerWidget {
  const StaffBreaksScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breaksAsync = ref.watch(staffBreaksProvider(staffId));

    return Scaffold(
      appBar: AppBar(title: const Text('Breaks')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: breaksAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load breaks.',
          onRetry: () => ref.invalidate(staffBreaksProvider(staffId)),
        ),
        data: (breaks) {
          if (breaks.isEmpty) {
            return const EmptyView(icon: Icons.free_breakfast_outlined, message: 'No breaks added yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: breaks.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final b = breaks[index];
              return Card(
                child: ListTile(
                  title: Text(dayOfWeekLabel(b.dayOfWeek)),
                  subtitle: Text('${b.startTime} – ${b.endTime}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await ref.read(staffRepositoryProvider).deleteBreak(staffId, b.id);
                        ref.invalidate(staffBreaksProvider(staffId));
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
                  onTap: () => _showForm(context, ref, existing: b),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, {StaffBreakEntry? existing}) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => _BreakForm(staffId: staffId, existing: existing));
  }
}

class _BreakForm extends ConsumerStatefulWidget {
  const _BreakForm({required this.staffId, this.existing});

  final String staffId;
  final StaffBreakEntry? existing;

  @override
  ConsumerState<_BreakForm> createState() => _BreakFormState();
}

class _BreakFormState extends ConsumerState<_BreakForm> {
  int _dayOfWeek = 1;
  TimeOfDay _start = const TimeOfDay(hour: 13, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 14, minute: 0);
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _dayOfWeek = widget.existing!.dayOfWeek;
      _start = _parse(widget.existing!.startTime);
      _end = _parse(widget.existing!.endTime);
    }
  }

  TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _format(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final repository = ref.read(staffRepositoryProvider);
      if (widget.existing == null) {
        await repository.createBreak(widget.staffId, dayOfWeek: _dayOfWeek, startTime: _format(_start), endTime: _format(_end));
      } else {
        await repository.updateBreak(
          widget.staffId,
          widget.existing!.id,
          dayOfWeek: _dayOfWeek,
          startTime: _format(_start),
          endTime: _format(_end),
        );
      }
      ref.invalidate(staffBreaksProvider(widget.staffId));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'Add break' : 'Edit break', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          DropdownButtonFormField<int>(
            initialValue: _dayOfWeek,
            decoration: const InputDecoration(labelText: 'Day'),
            items: List.generate(7, (d) => DropdownMenuItem(value: d, child: Text(dayOfWeekLabel(d)))),
            onChanged: (v) => setState(() => _dayOfWeek = v ?? 1),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _start);
                    if (picked != null) setState(() => _start = picked);
                  },
                  child: Text('Start: ${_format(_start)}'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _end);
                    if (picked != null) setState(() => _end = picked);
                  },
                  child: Text('End: ${_format(_end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting ? const CircularProgressIndicator() : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
