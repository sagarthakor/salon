import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_schedule.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/staff/presentation/screens/staff_schedule_screen.dart';

import '../support/fakes.dart';

const _staffId = 'stf-1';

void main() {
  late MockStaffRepository staffRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        staffRepositoryProvider.overrideWithValue(staffRepository),
      ],
      child: const MaterialApp(home: StaffScheduleScreen(staffId: _staffId)),
    );
  }

  setUp(() {
    staffRepository = MockStaffRepository();
  });

  testWidgets('shows real working hours, breaks, and leave with no edit controls', (tester) async {
    when(() => staffRepository.workingHours(_staffId)).thenAnswer(
      (_) async => [
        const StaffWorkingHourEntry(dayOfWeek: 1, isWorking: true, startTime: '09:00', endTime: '18:00'),
        const StaffWorkingHourEntry(dayOfWeek: 0, isWorking: false),
      ],
    );
    when(() => staffRepository.breaks(_staffId)).thenAnswer(
      (_) async => [const StaffBreakEntry(id: 1, dayOfWeek: 1, startTime: '13:00', endTime: '14:00')],
    );
    when(() => staffRepository.leaves(_staffId)).thenAnswer(
      (_) async => [const StaffLeaveEntry(id: 1, startDate: '2026-09-01', endDate: '2026-09-02', status: 'approved', reason: 'Personal')],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Monday'), findsWidgets);
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('9:00 AM – 6:00 PM'), findsOneWidget);
    expect(find.text('1:00 PM – 2:00 PM'), findsOneWidget);
    expect(find.text('2026-09-01 – 2026-09-02'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('shows an empty state for breaks and leave when there are none', (tester) async {
    when(() => staffRepository.workingHours(_staffId)).thenAnswer((_) async => []);
    when(() => staffRepository.breaks(_staffId)).thenAnswer((_) async => []);
    when(() => staffRepository.leaves(_staffId)).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No breaks set.'), findsOneWidget);
    expect(find.text('No leave on record.'), findsOneWidget);
  });
}
