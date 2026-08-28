import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../notifications/presentation/providers/notification_providers.dart';

class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _MenuTile(icon: Icons.bar_chart_outlined, title: 'Reports', onTap: () => context.push('/owner/reports')),
          _MenuTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            badgeCount: unreadCount,
            onTap: () => context.push('/notifications'),
          ),
          _MenuTile(icon: Icons.tune, title: 'Notification settings', onTap: () => context.push('/owner/notification-settings')),
          _MenuTile(icon: Icons.content_cut, title: 'Services', onTap: () => context.push('/owner/services')),
          _MenuTile(icon: Icons.category_outlined, title: 'Categories', onTap: () => context.push('/owner/categories')),
          _MenuTile(icon: Icons.storefront, title: 'Branches', onTap: () => context.push('/owner/branches')),
          _MenuTile(icon: Icons.business, title: 'Salon profile', onTap: () => context.push('/owner/salon')),
          _MenuTile(icon: Icons.settings_outlined, title: 'Booking settings', onTap: () => context.push('/owner/salon/settings')),
          _MenuTile(icon: Icons.card_membership_outlined, title: 'Subscription', onTap: () => context.push('/owner/subscription')),
          _MenuTile(icon: Icons.sell_outlined, title: 'Coupons', onTap: () => context.push('/owner/coupons')),
          _MenuTile(icon: Icons.workspace_premium_outlined, title: 'Membership plans', onTap: () => context.push('/owner/membership-plans')),
          _MenuTile(icon: Icons.groups_outlined, title: 'Customer memberships', onTap: () => context.push('/owner/memberships')),
          _MenuTile(icon: Icons.stars_outlined, title: 'Loyalty', onTap: () => context.push('/owner/loyalty')),
          const Divider(height: AppSpacing.xl),
          _MenuTile(
            icon: Icons.logout,
            title: 'Log out',
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.onTap, this.badgeCount = 0});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: badgeCount > 0
            ? Badge(label: Text('$badgeCount'), child: const Icon(Icons.chevron_right))
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
