import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/customer_note_entry.dart';
import '../providers/owner_customer_providers.dart';

/// Owner/super-admin only on the backend (`Gate::authorize('manage', ...)`);
/// never reachable from anywhere a plain staff or customer session could
/// navigate to — see CUSTOMER_ARCHITECTURE.md.
class CustomerNotesScreen extends ConsumerWidget {
  const CustomerNotesScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(ownerCustomerNotesProvider(customerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Internal notes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: notesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load notes.',
          onRetry: () => ref.invalidate(ownerCustomerNotesProvider(customerId)),
        ),
        data: (notes) {
          if (notes.isEmpty) {
            return const EmptyView(icon: Icons.sticky_note_2_outlined, message: 'No notes yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  title: Text(note.body),
                  subtitle: Text([if (note.authorName != null) note.authorName!, if (note.createdAt != null) note.createdAt!].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await ref.read(ownerCustomerRepositoryProvider).deleteNote(customerId, note.id);
                        ref.invalidate(ownerCustomerNotesProvider(customerId));
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
                  onTap: () => _showForm(context, ref, existing: note),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, {CustomerNoteEntry? existing}) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => _NoteForm(customerId: customerId, existing: existing));
  }
}

class _NoteForm extends ConsumerStatefulWidget {
  const _NoteForm({required this.customerId, this.existing});

  final String customerId;
  final CustomerNoteEntry? existing;

  @override
  ConsumerState<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends ConsumerState<_NoteForm> {
  late final _bodyController = TextEditingController(text: widget.existing?.body);
  bool _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_bodyController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a note.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final repository = ref.read(ownerCustomerRepositoryProvider);
      if (widget.existing == null) {
        await repository.addNote(widget.customerId, _bodyController.text.trim());
      } else {
        await repository.updateNote(widget.customerId, widget.existing!.id, _bodyController.text.trim());
      }
      ref.invalidate(ownerCustomerNotesProvider(widget.customerId));
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
          Text(widget.existing == null ? 'Add note' : 'Edit note', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(controller: _bodyController, maxLines: 4, decoration: const InputDecoration(labelText: 'Note')),
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
