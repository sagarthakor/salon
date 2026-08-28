import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';
import 'package:salon_customer/features/services/data/models/service_category.dart';
import 'package:salon_customer/features/staff/presentation/screens/my_services_screen.dart';

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
      child: const MaterialApp(home: MyServicesScreen(staffId: _staffId)),
    );
  }

  setUp(() {
    staffRepository = MockStaffRepository();
  });

  testWidgets('lists only the services assigned to this staff member', (tester) async {
    when(() => staffRepository.services(_staffId)).thenAnswer(
      (_) async => [
        SalonService(
          id: 'sv-1',
          branchId: 'br-1',
          category: const ServiceCategory(id: 'cat-1', branchId: 'br-1', name: 'Hair', slug: 'hair', status: 'active', sortOrder: 0),
          name: 'Haircut',
          slug: 'haircut',
          gender: 'unisex',
          price: 300,
          durationMinutes: 30,
          status: 'active',
          sortOrder: 0,
        ),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('Hair · 30 min'), findsOneWidget);
  });

  testWidgets('shows an empty state when no services are assigned yet', (tester) async {
    when(() => staffRepository.services(_staffId)).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No services assigned to you yet.'), findsOneWidget);
  });
}
