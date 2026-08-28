import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/staff_list_controller.dart';
import '../providers/staff_providers.dart';

class StaffDetailsScreen extends ConsumerWidget {
  const StaffDetailsScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffDetailsProvider(staffId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff details'),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => context.push('/owner/staff/$staffId/edit')),
        ],
      ),
      body: staffAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this staff member.',
          onRetry: () => ref.invalidate(staffDetailsProvider(staffId)),
        ),
        data: (staff) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: staff.photo != null ? NetworkImage(staff.photo!) : null,
                          child: staff.photo == null ? Text(staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?') : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(staff.name, style: Theme.of(context).textTheme.titleMedium),
                              Chip(label: Text(staff.isActive ? 'Active' : 'Inactive')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.lg),
                    if (staff.phone != null) _Row(label: 'Phone', value: staff.phone!),
                    if (staff.email != null) _Row(label: 'Email', value: staff.email!),
                    _Row(label: 'Gender', value: staff.gender),
                    if (staff.joiningDate != null) _Row(label: 'Joined', value: staff.joiningDate!),
                    if (staff.bio != null) _Row(label: 'Bio', value: staff.bio!),
                    _Row(label: 'Branches', value: staff.branches.isEmpty ? 'None' : staff.branches.map((b) => b.name).join(', ')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _NavCard(icon: Icons.content_cut, title: 'Services', onTap: () => context.push('/owner/staff/$staffId/services')),
            _NavCard(icon: Icons.schedule, title: 'Working hours', onTap: () => context.push('/owner/staff/$staffId/working-hours')),
            _NavCard(icon: Icons.free_breakfast, title: 'Breaks', onTap: () => context.push('/owner/staff/$staffId/breaks')),
            _NavCard(icon: Icons.beach_access, title: 'Leave', onTap: () => context.push('/owner/staff/$staffId/leaves')),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => _confirmDelete(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete staff member'),
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this staff member?'),
        content: const Text('This soft-deletes the profile; historical bookings remain intact.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(staffRepositoryProvider).delete(staffId);
      ref.invalidate(staffListControllerProvider);
      if (context.mounted) context.pop();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(leading: Icon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right), onTap: onTap),
    );
  }
}
