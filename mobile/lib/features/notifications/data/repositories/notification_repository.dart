import '../../../../core/network/api_client.dart';
import '../models/app_notification.dart';

/// Talks to the Phase 11 in-app notification APIs (`/notifications*`).
/// Every endpoint here is already scoped server-side to the authenticated
/// user — see NOTIFICATION_ARCHITECTURE.md — so this repository never needs
/// to pass a user or tenant id itself.
class NotificationRepository {
  NotificationRepository(this._client);

  final ApiClient _client;

  Future<List<AppNotification>> list({int page = 1, int perPage = 20, bool unreadOnly = false}) async {
    final data = await _client.get<List<dynamic>>(
      '/notifications',
      queryParameters: {'page': page, 'per_page': perPage, if (unreadOnly) 'unread_only': 1},
    );
    return data.map((n) => AppNotification.fromJson(n as Map<String, dynamic>)).toList();
  }

  Future<int> unreadCount() async {
    final data = await _client.get<Map<String, dynamic>>('/notifications/unread-count');
    return data['unread_count'] as int;
  }

  Future<AppNotification> markRead(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/notifications/$id/read');
    return AppNotification.fromJson(data);
  }

  Future<void> markAllRead() => _client.post<dynamic>('/notifications/read-all');
}
