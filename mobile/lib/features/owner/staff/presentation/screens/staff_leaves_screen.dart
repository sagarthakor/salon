import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/staff_schedule.dart';
import '../providers/staff_providers.dart';

class StaffLeavesScreen extends ConsumerWidget {
  const StaffLeavesScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leavesAsync = ref.watch(staffLeavesProvider(staffId));

    return Scaffold(
      appBar: AppBar(title: const Text('Leave')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: leavesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load leave.',
          onRetry: () => ref.invalidate(staffLeavesProvider(staffId)),
        ),
        data: (leaves) {
          if (leaves.isEmpty) {
            return const EmptyView(icon: Icons.beach_access_outlined, message: 'No leave recorded yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: leaves.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final leave = leaves[index];
              return Card(
                child: ListTile(
                  title: Text(leave.startDate == leave.endDate ? leave.startDate : '${leave.startDate} – ${leave.endDate}'),
                  subtitle: Text(leave.reason ?? 'No reason given'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(label: Text(leave.status)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          try {
                            await ref.read(staffRepositoryProvider).deleteLeave(staffId, leave.id);
                            ref.invalidate(staffLeavesProvider(staffId));
                          } on ApiException catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () => _showForm(context, ref, existing: leave),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, {StaffLeaveEntry? existing}) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => _LeaveForm(staffId: staffId, existing: existing));
  }
}

class _LeaveForm extends ConsumerStatefulWidget {
  const _LeaveForm({required this.staffId, this.existing});

  final String staffId;
  final StaffLeaveEntry? existing;

  @override
  ConsumerState<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends ConsumerState<_LeaveForm> {
  late final _reasonController = TextEditingController(text: widget.existing?.reason);
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _startDate = parseApiDate(widget.existing!.startDate);
      _endDate = parseApiDate(widget.existing!.endDate);
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        _endDate ??= picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Select a start and end date.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final repository = ref.read(staffRepositoryProvider);
      if (widget.existing == null) {
        await repository.createLeave(
          widget.staffId,
          startDate: toApiDate(_startDate!),
          endDate: toApiDate(_endDate!),
          reason: _reasonController.text.trim(),
        );
      } else {
        await repository.updateLeave(
          widget.staffId,
          widget.existing!.id,
          startDate: toApiDate(_startDate!),
          endDate: toApiDate(_endDate!),
          reason: _reasonController.text.trim(),
        );
      }
      ref.invalidate(staffLeavesProvider(widget.staffId));
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
          Text(widget.existing == null ? 'Add leave' : 'Edit leave', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(true),
                  child: Text(_startDate != null ? toApiDate(_startDate!) : 'Start date'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(false),
                  child: Text(_endDate != null ? toApiDate(_endDate!) : 'End date'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _reasonController, decoration: const InputDecoration(labelText: 'Reason (optional)')),
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
