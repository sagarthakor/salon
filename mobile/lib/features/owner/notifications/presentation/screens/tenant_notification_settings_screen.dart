import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../notifications/presentation/providers/notification_providers.dart';
import '../../../../notifications/presentation/screens/notification_preference_matrix_screen.dart';

/// Owner-only tenant-wide notification defaults
/// (`GET/PUT /salon/notification-settings`) — see NOTIFICATION_ARCHITECTURE.md,
/// "Preferences". The backend itself re-checks the salon-owner role on every
/// write; this screen is only reachable from Owner's "More" tab in the first
/// place.
class TenantNotificationSettingsScreen extends ConsumerWidget {
  const TenantNotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(notificationPreferenceRepositoryProvider);
    return NotificationPreferenceMatrixScreen(
      title: 'Salon notification settings',
      fetch: repository.tenant,
      update: repository.updateTenant,
    );
  }
}
