import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_providers.dart';
import 'notification_preference_matrix_screen.dart';

/// Personal channel preferences (`GET/PUT /notifications/preferences`) —
/// available to any authenticated user (customer, staff, or owner).
class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(notificationPreferenceRepositoryProvider);
    return NotificationPreferenceMatrixScreen(
      title: 'Notification preferences',
      fetch: repository.personal,
      update: repository.updatePersonal,
    );
  }
}
