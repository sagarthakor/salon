import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_member.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/screens/staff_list_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockStaffRepository staffRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        staffRepositoryProvider.overrideWithValue(staffRepository),
      ],
      child: const MaterialApp(home: StaffListScreen()),
    );
  }

  setUp(() {
    staffRepository = MockStaffRepository();
  });

  testWidgets('lists staff with an Active/Inactive chip per member', (tester) async {
    when(
      () => staffRepository.list(page: any(named: 'page'), perPage: any(named: 'perPage'), status: any(named: 'status')),
    ).thenAnswer(
      (_) async => [
        const StaffMember(id: 'stf-1', name: 'Priya Verma', gender: 'female', status: 'active'),
        const StaffMember(id: 'stf-2', name: 'Rohit Das', gender: 'male', status: 'inactive'),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Priya Verma'), findsOneWidget);
    expect(find.text('Rohit Das'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('shows an empty state prompting to add staff when there are none yet', (tester) async {
    when(
      () => staffRepository.list(page: any(named: 'page'), perPage: any(named: 'perPage'), status: any(named: 'status')),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No staff yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('shows an error view with retry when the request fails', (tester) async {
    when(
      () => staffRepository.list(page: any(named: 'page'), perPage: any(named: 'perPage'), status: any(named: 'status')),
    ).thenThrow(const ApiException(message: 'Could not load staff.', type: ApiErrorType.network));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
  });
}
