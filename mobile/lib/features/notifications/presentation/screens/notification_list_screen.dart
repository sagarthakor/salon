import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/models/app_role.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/app_notification.dart';
import '../providers/notification_providers.dart';

/// Shared across all three roles — every backing endpoint is already scoped
/// to the authenticated user (see NOTIFICATION_ARCHITECTURE.md), so this one
/// screen is correct for the customer, staff, and owner apps alike, the same
/// way OwnerBookingDetailsScreen is already reused by the staff app.
class NotificationListScreen extends ConsumerWidget {
  const NotificationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationListControllerProvider);
    final controller = ref.read(notificationListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: state.notifications.any((n) => !n.isRead) ? controller.markAllRead : null,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.notifications.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          if (state.notifications.isEmpty) {
            return const EmptyView(icon: Icons.notifications_none, message: 'No notifications yet.');
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
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: state.notifications.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index >= state.notifications.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final n = state.notifications[index];
                  return _NotificationTile(
                    notification: n,
                    onTap: () async {
                      if (!n.isRead) await controller.markRead(n.id);
                      if (context.mounted) _navigateToDeepLink(context, ref, n);
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _navigateToDeepLink(BuildContext context, WidgetRef ref, AppNotification n) {
    if (n.deepLink != 'booking' || n.bookingId == null) return;
    final role = AppRole.fromBackendRole(ref.read(authControllerProvider).user?.role ?? '');
    final path = switch (role) {
      AppRole.ownerAdmin => '/owner/bookings/${n.bookingId}',
      AppRole.staff => '/staff/appointments/${n.bookingId}',
      AppRole.customer => '/bookings/${n.bookingId}',
      AppRole.unknown => null,
    };
    if (path != null) context.push(path);
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        notification.isRead ? Icons.notifications_none : Icons.notifications,
        color: notification.isRead ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.primary,
      ),
      title: Text(notification.title, style: TextStyle(fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold)),
      subtitle: Text(notification.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: notification.isRead ? null : const CircleAvatar(radius: 4),
    );
  }
}
