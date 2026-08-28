import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/notifications/data/models/notification_preference.dart';
import 'package:salon_customer/features/notifications/presentation/screens/notification_preference_matrix_screen.dart';

void main() {
  List<NotificationPreferenceRow> rows() => const [
    NotificationPreferenceRow(eventType: 'booking.created', channel: 'push', enabled: true, isOverride: false),
    NotificationPreferenceRow(eventType: 'booking.created', channel: 'email', enabled: false, isOverride: false),
  ];

  testWidgets('renders one card per event with a filter chip per channel, reflecting current enablement', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NotificationPreferenceMatrixScreen(
            title: 'Notification preferences',
            fetch: () async => rows(),
            update: (r) async => r,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Booking Created'), findsOneWidget);
    final pushChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Push'));
    final emailChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Email'));
    expect(pushChip.selected, isTrue);
    expect(emailChip.selected, isFalse);
  });

  testWidgets('tapping a channel chip calls update() with the toggled row', (tester) async {
    List<NotificationPreferenceRow>? sentUpdate;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NotificationPreferenceMatrixScreen(
            title: 'Notification preferences',
            fetch: () async => rows(),
            update: (r) async {
              sentUpdate = r;
              return r;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'Email'));
    await tester.pump();
    await tester.pump();

    expect(sentUpdate, isNotNull);
    expect(sentUpdate!.single.channel, 'email');
    expect(sentUpdate!.single.enabled, isTrue);
  });
}
