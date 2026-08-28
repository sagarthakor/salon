import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/branch_working_hour_entry.dart';
import '../providers/owner_branch_providers.dart';

class BranchHolidaysScreen extends ConsumerWidget {
  const BranchHolidaysScreen({super.key, required this.branchId});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidaysAsync = ref.watch(branchHolidaysProvider(branchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: holidaysAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load holidays.',
          onRetry: () => ref.invalidate(branchHolidaysProvider(branchId)),
        ),
        data: (holidays) {
          if (holidays.isEmpty) {
            return const EmptyView(icon: Icons.event_available, message: 'No holidays added yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: holidays.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final holiday = holidays[index];
              return Card(
                child: ListTile(
                  title: Text(holiday.name),
                  subtitle: Text(holiday.holidayDate),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await ref.read(ownerBranchRepositoryProvider).deleteHoliday(branchId, holiday.id);
                        ref.invalidate(branchHolidaysProvider(branchId));
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
                  onTap: () => _showForm(context, ref, existing: holiday),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, {BranchHolidayEntry? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HolidayForm(branchId: branchId, existing: existing),
    );
  }
}

class _HolidayForm extends ConsumerStatefulWidget {
  const _HolidayForm({required this.branchId, this.existing});

  final String branchId;
  final BranchHolidayEntry? existing;

  @override
  ConsumerState<_HolidayForm> createState() => _HolidayFormState();
}

class _HolidayFormState extends ConsumerState<_HolidayForm> {
  late final _nameController = TextEditingController(text: widget.existing?.name);
  DateTime? _date;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _date = parseApiDate(widget.existing!.holidayDate);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_date == null || _nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name and select a date.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final repository = ref.read(ownerBranchRepositoryProvider);
      if (widget.existing == null) {
        await repository.createHoliday(widget.branchId, holidayDate: toApiDate(_date!), name: _nameController.text.trim());
      } else {
        await repository.updateHoliday(
          widget.branchId,
          widget.existing!.id,
          holidayDate: toApiDate(_date!),
          name: _nameController.text.trim(),
        );
      }
      ref.invalidate(branchHolidaysProvider(widget.branchId));
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
          Text(widget.existing == null ? 'Add holiday' : 'Edit holiday', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: _pickDate,
            child: Text(_date != null ? toApiDate(_date!) : 'Select date'),
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
