import '../../../../core/network/api_client.dart';

/// Registers/deactivates this device's push token with the backend
/// (`user_device_tokens`). NOT yet wired to a real FCM token source —
/// `firebase_messaging`/`firebase_core` were deliberately not added in this
/// phase without a real Firebase project's `google-services.json` /
/// `GoogleService-Info.plist` (see NOTIFICATION_ARCHITECTURE.md, "What Phase
/// 11 does NOT claim"). Once those exist, call [register] with the real FCM
/// token after login and on token refresh, and [deactivate] on logout.
class DeviceTokenRepository {
  DeviceTokenRepository(this._client);

  final ApiClient _client;

  Future<void> register({required String platform, required String token, String? deviceIdentifier}) {
    return _client.post<dynamic>(
      '/notifications/device-tokens',
      data: {'platform': platform, 'token': token, 'device_identifier': ?deviceIdentifier},
    );
  }

  Future<void> deactivate(String token) {
    return _client.post<dynamic>('/notifications/device-tokens/deactivate', data: {'token': token});
  }
}
