import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/notifications/data/repositories/notification_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;
  late NotificationRepository repository;

  setUp(() {
    client = MockApiClient();
    repository = NotificationRepository(client);
  });

  test('list() requests the given page/perPage and parses each notification', () async {
    when(() => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => [
        {
          'id': 'ntf_1',
          'type': 'booking.created',
          'title': 'Booking received',
          'body': 'body',
          'data': {},
          'is_read': false,
          'read_at': null,
          'created_at': '2026-08-27T10:00:00+00:00',
        },
      ],
    );

    final result = await repository.list(page: 2, perPage: 10);

    expect(result, hasLength(1));
    expect(result.single.id, 'ntf_1');
    final captured = verify(
      () => client.get<List<dynamic>>('/notifications', queryParameters: captureAny(named: 'queryParameters')),
    ).captured.single as Map<String, dynamic>;
    expect(captured['page'], 2);
    expect(captured['per_page'], 10);
    expect(captured.containsKey('unread_only'), isFalse);
  });

  test('list(unreadOnly: true) sends unread_only=1', () async {
    when(() => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async => []);

    await repository.list(unreadOnly: true);

    final captured = verify(
      () => client.get<List<dynamic>>('/notifications', queryParameters: captureAny(named: 'queryParameters')),
    ).captured.single as Map<String, dynamic>;
    expect(captured['unread_only'], 1);
  });

  test('unreadCount() returns the server-computed count', () async {
    when(() => client.get<Map<String, dynamic>>('/notifications/unread-count')).thenAnswer(
      (_) async => {'unread_count': 4},
    );

    expect(await repository.unreadCount(), 4);
  });

  test('markRead(id) posts to the per-notification read endpoint and returns the updated notification', () async {
    when(() => client.post<Map<String, dynamic>>(any())).thenAnswer(
      (_) async => {
        'id': 'ntf_1',
        'type': 'booking.created',
        'title': 'Booking received',
        'body': 'body',
        'data': {},
        'is_read': true,
        'read_at': '2026-08-27T12:00:00+00:00',
        'created_at': '2026-08-27T10:00:00+00:00',
      },
    );

    final updated = await repository.markRead('ntf_1');

    verify(() => client.post<Map<String, dynamic>>('/notifications/ntf_1/read')).called(1);
    expect(updated.isRead, true);
  });

  test('markAllRead() posts to the read-all endpoint', () async {
    when(() => client.post<dynamic>(any())).thenAnswer((_) async => null);

    await repository.markAllRead();

    verify(() => client.post<dynamic>('/notifications/read-all')).called(1);
  });
}
