import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/notifications/data/models/notification_preference.dart';
import 'package:salon_customer/features/notifications/data/repositories/device_token_repository.dart';
import 'package:salon_customer/features/notifications/data/repositories/notification_preference_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;

  setUp(() {
    client = MockApiClient();
  });

  group('NotificationPreferenceRepository', () {
    late NotificationPreferenceRepository repository;

    setUp(() => repository = NotificationPreferenceRepository(client));

    test('personal() fetches the personal preference endpoint', () async {
      when(() => client.get<List<dynamic>>(any())).thenAnswer(
        (_) async => [
          {'event_type': 'booking.created', 'channel': 'push', 'enabled': true, 'is_override': false},
        ],
      );

      final rows = await repository.personal();

      verify(() => client.get<List<dynamic>>('/notifications/preferences')).called(1);
      expect(rows.single.channel, 'push');
    });

    test('updateTenant() PUTs to the tenant-wide endpoint with the exact preferences payload', () async {
      when(() => client.put<List<dynamic>>(any(), data: any(named: 'data'))).thenAnswer((_) async => []);

      await repository.updateTenant(const [
        NotificationPreferenceRow(eventType: 'booking.cancelled', channel: 'email', enabled: false, isOverride: true),
      ]);

      final captured = verify(
        () => client.put<List<dynamic>>('/salon/notification-settings', data: captureAny(named: 'data')),
      ).captured.single as Map<String, dynamic>;
      expect(captured['preferences'], [
        {'event_type': 'booking.cancelled', 'channel': 'email', 'enabled': false},
      ]);
    });
  });

  group('DeviceTokenRepository', () {
    late DeviceTokenRepository repository;

    setUp(() => repository = DeviceTokenRepository(client));

    test('register() sends platform/token/device_identifier', () async {
      when(() => client.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer((_) async => null);

      await repository.register(platform: 'android', token: 'tok-1', deviceIdentifier: 'device-a');

      final captured = verify(
        () => client.post<dynamic>('/notifications/device-tokens', data: captureAny(named: 'data')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'platform': 'android', 'token': 'tok-1', 'device_identifier': 'device-a'});
    });

    test('deactivate() sends only the token', () async {
      when(() => client.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer((_) async => null);

      await repository.deactivate('tok-1');

      final captured = verify(
        () => client.post<dynamic>('/notifications/device-tokens/deactivate', data: captureAny(named: 'data')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'token': 'tok-1'});
    });
  });
}
