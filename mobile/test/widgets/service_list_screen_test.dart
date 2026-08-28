import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/services/presentation/providers/owner_service_providers.dart';
import 'package:salon_customer/features/owner/services/presentation/screens/service_list_screen.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';
import 'package:salon_customer/features/services/data/models/service_category.dart';

import '../support/fakes.dart';

void main() {
  late MockOwnerServiceRepository serviceRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ownerServiceRepositoryProvider.overrideWithValue(serviceRepository),
      ],
      child: const MaterialApp(home: ServiceListScreen()),
    );
  }

  setUp(() {
    serviceRepository = MockOwnerServiceRepository();
    when(() => serviceRepository.categories()).thenAnswer((_) async => const []);
  });

  testWidgets('lists services with category, duration, and price', (tester) async {
    when(
      () => serviceRepository.services(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        categoryId: any(named: 'categoryId'),
        branchId: any(named: 'branchId'),
      ),
    ).thenAnswer(
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
    expect(find.text('₹300'), findsOneWidget);
  });

  testWidgets('shows an empty state prompting to add a service when there are none', (tester) async {
    when(
      () => serviceRepository.services(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        categoryId: any(named: 'categoryId'),
        branchId: any(named: 'branchId'),
      ),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No services yet. Tap + to add one.'), findsOneWidget);
  });
}
