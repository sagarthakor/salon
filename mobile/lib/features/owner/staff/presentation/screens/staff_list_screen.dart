import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/staff_member.dart';
import '../providers/staff_list_controller.dart';

class StaffListScreen extends ConsumerWidget {
  const StaffListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(staffListControllerProvider);
    final controller = ref.read(staffListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: controller.setStatus,
            itemBuilder: (context) => const [
              PopupMenuItem(value: null, child: Text('All')),
              PopupMenuItem(value: 'active', child: Text('Active')),
              PopupMenuItem(value: 'inactive', child: Text('Inactive')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Explicit tag required: OwnerShell's IndexedStack keeps this screen
        // mounted alongside CustomerListScreen (also a default-tag FAB), so
        // the two default tags collide within that one subtree during
        // animated transitions into /owner ("multiple heroes share the same
        // tag"). See OWNER_APP_ARCHITECTURE.md.
        heroTag: 'owner-staff-list-fab',
        onPressed: () => context.push('/owner/staff/new'),
        child: const Icon(Icons.add),
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.staff.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          if (state.staff.isEmpty) {
            return RefreshIndicator(
              onRefresh: controller.loadFirstPage,
              child: ListView(
                children: const [
                  SizedBox(height: 200, child: EmptyView(icon: Icons.people_outline, message: 'No staff yet. Tap + to add one.')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: controller.loadFirstPage,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (state.hasMore &&
                    !state.isLoadingMore &&
                    notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                  controller.loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: state.staff.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index >= state.staff.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _StaffTile(staff: state.staff[index]);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.staff});

  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: staff.photo != null ? NetworkImage(staff.photo!) : null,
          child: staff.photo == null ? Text(staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?') : null,
        ),
        title: Text(staff.name),
        subtitle: Text(staff.branches.map((b) => b.name).join(', ').isEmpty ? 'No branch assigned' : staff.branches.map((b) => b.name).join(', ')),
        trailing: Chip(label: Text(staff.isActive ? 'Active' : 'Inactive')),
        onTap: () => context.push('/owner/staff/${staff.id}'),
      ),
    );
  }
}
