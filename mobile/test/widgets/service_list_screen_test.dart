import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
        audience: any(named: 'audience'),
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
    expect(find.text('Hair · ₹300 · 30 min'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('shows an empty state prompting to add a service when there are none', (tester) async {
    when(
      () => serviceRepository.services(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        categoryId: any(named: 'categoryId'),
        branchId: any(named: 'branchId'),
        audience: any(named: 'audience'),
      ),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No services yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('tapping the switch turns a service off without opening the edit form', (tester) async {
    const service = SalonService(
      id: 'sv-1',
      branchId: 'br-1',
      category: ServiceCategory(id: 'cat-1', branchId: 'br-1', name: 'Hair', slug: 'hair', status: 'active', sortOrder: 0),
      name: 'Haircut',
      slug: 'haircut',
      gender: 'unisex',
      price: 300,
      durationMinutes: 30,
      status: 'active',
      sortOrder: 0,
    );
    when(
      () => serviceRepository.services(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        categoryId: any(named: 'categoryId'),
        branchId: any(named: 'branchId'),
        audience: any(named: 'audience'),
      ),
    ).thenAnswer((_) async => [service]);
    when(
      () => serviceRepository.updateService(
        'sv-1',
        branchId: 'br-1',
        categoryId: 'cat-1',
        name: 'Haircut',
        description: null,
        gender: 'unisex',
        price: '300',
        durationMinutes: 30,
        status: 'inactive',
        instagramUrl: null,
      ),
    ).thenAnswer(
      (_) async => const SalonService(
        id: 'sv-1',
        branchId: 'br-1',
        category: ServiceCategory(id: 'cat-1', branchId: 'br-1', name: 'Hair', slug: 'hair', status: 'active', sortOrder: 0),
        name: 'Haircut',
        slug: 'haircut',
        gender: 'unisex',
        price: 300,
        durationMinutes: 30,
        status: 'inactive',
        sortOrder: 0,
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();

    verify(
      () => serviceRepository.updateService(
        'sv-1',
        branchId: 'br-1',
        categoryId: 'cat-1',
        name: 'Haircut',
        description: null,
        gender: 'unisex',
        price: '300',
        durationMinutes: 30,
        status: 'inactive',
        instagramUrl: null,
      ),
    ).called(1);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    // No navigation happened — still on the Services list, never the edit form.
    expect(find.text('Services'), findsOneWidget);
  });

  testWidgets('tapping Edit opens the edit form where price and duration can be changed', (tester) async {
    when(
      () => serviceRepository.services(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        categoryId: any(named: 'categoryId'),
        branchId: any(named: 'branchId'),
        audience: any(named: 'audience'),
      ),
    ).thenAnswer(
      (_) async => [
        const SalonService(
          id: 'sv-1',
          branchId: 'br-1',
          category: ServiceCategory(id: 'cat-1', branchId: 'br-1', name: 'Hair', slug: 'hair', status: 'active', sortOrder: 0),
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

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const ServiceListScreen()),
        GoRoute(
          path: '/owner/services/:id/edit',
          builder: (context, state) => Scaffold(body: Text('Editing ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          ownerServiceRepositoryProvider.overrideWithValue(serviceRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Editing sv-1'), findsOneWidget);
  });
}
