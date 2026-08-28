import '../../../../core/network/api_client.dart';
import '../models/notification_preference.dart';

/// Two independent scopes, both backed by `NotificationPreferenceController`:
/// `personal` (any authenticated user, `/notifications/preferences`) and
/// `tenant` (owner-only tenant-wide defaults, `/salon/notification-settings`).
/// See NOTIFICATION_ARCHITECTURE.md, "Preferences".
class NotificationPreferenceRepository {
  NotificationPreferenceRepository(this._client);

  final ApiClient _client;

  Future<List<NotificationPreferenceRow>> personal() => _fetch('/notifications/preferences');

  Future<List<NotificationPreferenceRow>> updatePersonal(List<NotificationPreferenceRow> rows) =>
      _update('/notifications/preferences', rows);

  Future<List<NotificationPreferenceRow>> tenant() => _fetch('/salon/notification-settings');

  Future<List<NotificationPreferenceRow>> updateTenant(List<NotificationPreferenceRow> rows) =>
      _update('/salon/notification-settings', rows);

  Future<List<NotificationPreferenceRow>> _fetch(String path) async {
    final data = await _client.get<List<dynamic>>(path);
    return data.map((r) => NotificationPreferenceRow.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<NotificationPreferenceRow>> _update(String path, List<NotificationPreferenceRow> rows) async {
    final data = await _client.put<List<dynamic>>(
      path,
      data: {
        'preferences': rows
            .map((r) => {'event_type': r.eventType, 'channel': r.channel, 'enabled': r.enabled})
            .toList(),
      },
    );
    return data.map((r) => NotificationPreferenceRow.fromJson(r as Map<String, dynamic>)).toList();
  }
}
