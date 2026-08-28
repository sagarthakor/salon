import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../owner/staff/data/models/staff_member.dart';

/// My Profile — view-only. `PATCH /staff/{id}` requires `managedTenant()`
/// (owner/super-admin only), so a staff member cannot edit their own profile
/// today; see STAFF_APP_ARCHITECTURE.md. Data comes straight from
/// [staffMeProvider]'s already-fetched result (`GET /staff/me`), not a
/// second request.
class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key, required this.staff});

  final StaffMember staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$unreadCount'),
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundImage: staff.photo != null ? NetworkImage(staff.photo!) : null,
              child: staff.photo == null ? Text(staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 28)) : null,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Column(
              children: [
                _InfoTile(label: 'Name', value: staff.name),
                _InfoTile(label: 'Phone', value: staff.phone ?? '—'),
                _InfoTile(label: 'Email', value: staff.email ?? '—'),
                _InfoTile(label: 'Gender', value: staff.gender),
                if (staff.bio != null && staff.bio!.isNotEmpty) _InfoTile(label: 'Bio', value: staff.bio!),
                _InfoTile(label: 'Branch', value: staff.branches.isEmpty ? '—' : staff.branches.map((b) => b.name).join(', ')),
                _InfoTile(label: 'Status', value: staff.isActive ? 'Active' : 'Inactive'),
                if (staff.joiningDate != null) _InfoTile(label: 'Joined', value: staff.joiningDate!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => context.push('/notifications/preferences'),
            icon: const Icon(Icons.tune),
            label: const Text('Notification preferences'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(label), subtitle: Text(value));
  }
}
