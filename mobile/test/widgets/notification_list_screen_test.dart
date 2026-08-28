import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/notifications/data/models/app_notification.dart';
import 'package:salon_customer/features/notifications/presentation/providers/notification_providers.dart';
import 'package:salon_customer/features/notifications/presentation/screens/notification_list_screen.dart';

import '../support/fakes.dart';

AppNotification _notification({required String id, required bool isRead}) => AppNotification(
  id: id,
  type: 'booking.created',
  title: 'Booking $id',
  body: 'Body for $id',
  data: const {},
  isRead: isRead,
  readAt: isRead ? '2026-08-27T12:00:00+00:00' : null,
  createdAt: '2026-08-27T10:00:00+00:00',
);

void main() {
  late MockNotificationRepository repository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: NotificationListScreen()),
    );
  }

  setUp(() {
    repository = MockNotificationRepository();
  });

  testWidgets('lists notifications, unread ones bolded with a dot', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer(
      (_) async => [_notification(id: '1', isRead: false), _notification(id: '2', isRead: true)],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Booking 1'), findsOneWidget);
    expect(find.text('Booking 2'), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsOneWidget); // unread icon
    expect(find.byIcon(Icons.notifications_none), findsOneWidget); // read icon
  });

  testWidgets('shows an empty state when there are no notifications', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No notifications yet.'), findsOneWidget);
  });

  testWidgets('tapping an unread notification marks it read and updates the unread-count provider', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer(
      (_) async => [_notification(id: '1', isRead: false)],
    );
    when(() => repository.markRead('1')).thenAnswer((_) async => _notification(id: '1', isRead: true));
    when(() => repository.unreadCount()).thenAnswer((_) async => 0);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Booking 1'));
    await tester.pump();
    await tester.pump();

    verify(() => repository.markRead('1')).called(1);
    expect(find.byIcon(Icons.notifications), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('Mark all read is disabled when nothing is unread, enabled otherwise', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer(
      (_) async => [_notification(id: '1', isRead: true)],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Mark all read calls the repository and clears unread state', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer(
      (_) async => [_notification(id: '1', isRead: false), _notification(id: '2', isRead: false)],
    );
    when(() => repository.markAllRead()).thenAnswer((_) async {});
    when(() => repository.unreadCount()).thenAnswer((_) async => 0);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Mark all read'));
    await tester.pump();
    await tester.pump();

    verify(() => repository.markAllRead()).called(1);
    expect(find.byIcon(Icons.notifications), findsNothing);
  });
}
