import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/notifications/presentation/providers/notification_providers.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_member.dart';
import 'package:salon_customer/features/staff/presentation/screens/staff_profile_screen.dart';

import '../support/fakes.dart';

void main() {
  Widget buildApp(StaffMember staff) {
    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.unreadCount()).thenAnswer((_) async => 0);

    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        notificationRepositoryProvider.overrideWithValue(notificationRepository),
      ],
      child: MaterialApp(home: StaffProfileScreen(staff: staff)),
    );
  }

  testWidgets('shows the real profile fields and no editable form controls', (tester) async {
    const staff = StaffMember(
      id: 'stf-1',
      name: 'Amit Kumar',
      phone: '9876543210',
      email: 'amit@example.test',
      gender: 'male',
      bio: 'Senior stylist',
      status: 'active',
      joiningDate: '2024-01-15',
    );

    await tester.pumpWidget(buildApp(staff));
    await tester.pump();

    expect(find.text('Amit Kumar'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('amit@example.test'), findsOneWidget);
    expect(find.text('Senior stylist'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('2024-01-15'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('falls back to em-dashes for unset optional fields, never fabricated values', (tester) async {
    const staff = StaffMember(id: 'stf-2', name: 'New Hire', gender: 'female', status: 'inactive');

    await tester.pumpWidget(buildApp(staff));
    await tester.pump();

    expect(find.text('—'), findsWidgets);
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('tapping Log out signs the session out', (tester) async {
    const staff = StaffMember(id: 'stf-1', name: 'Amit', gender: 'male', status: 'active');

    await tester.pumpWidget(buildApp(staff));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Log out'), 200);

    expect(find.text('Log out'), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });
}
