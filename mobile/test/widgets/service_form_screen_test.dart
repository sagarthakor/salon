import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/branches/presentation/providers/owner_branch_providers.dart';
import 'package:salon_customer/features/owner/services/presentation/providers/owner_service_providers.dart';
import 'package:salon_customer/features/owner/services/presentation/screens/service_form_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';
import 'package:salon_customer/features/services/data/models/service_category.dart';

import '../support/fakes.dart';

void main() {
  late MockOwnerServiceRepository serviceRepository;
  late GoRouter router;

  Widget buildApp() {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('behind'))),
        GoRoute(path: '/form', builder: (context, state) => const ServiceFormScreen()),
        GoRoute(
          path: '/form/:id',
          builder: (context, state) => ServiceFormScreen(serviceId: state.pathParameters['id']),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ownerServiceRepositoryProvider.overrideWithValue(serviceRepository),
        ownerBranchesProvider.overrideWith(
          (ref) async => [const Branch(id: 'br-1', name: 'MG Road', slug: 'mg-road', address: Address(), timezone: 'Asia/Kolkata', status: 'active')],
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    serviceRepository = MockOwnerServiceRepository();
    when(() => serviceRepository.categories()).thenAnswer(
      (_) async => const [ServiceCategory(id: 'cat-1', branchId: 'br-1', name: 'Hair', slug: 'hair', status: 'active', sortOrder: 0)],
    );
  });

  testWidgets('refuses to submit without a branch/category selected', (tester) async {
    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Haircut');
    await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '300');
    await tester.enterText(find.widgetWithText(TextFormField, 'Duration (min)'), '30');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Select a branch and category.'), findsOneWidget);
    verifyNever(
      () => serviceRepository.createService(
        branchId: any(named: 'branchId'),
        categoryId: any(named: 'categoryId'),
        name: any(named: 'name'),
        description: any(named: 'description'),
        gender: any(named: 'gender'),
        price: any(named: 'price'),
        durationMinutes: any(named: 'durationMinutes'),
        status: any(named: 'status'),
        imagePath: any(named: 'imagePath'),
        instagramUrl: any(named: 'instagramUrl'),
      ),
    );
  });

  testWidgets('creates a service once branch, category, name, price, and duration are filled in', (tester) async {
    when(
      () => serviceRepository.createService(
        branchId: any(named: 'branchId'),
        categoryId: any(named: 'categoryId'),
        name: any(named: 'name'),
        description: any(named: 'description'),
        gender: any(named: 'gender'),
        price: any(named: 'price'),
        durationMinutes: any(named: 'durationMinutes'),
        status: any(named: 'status'),
        imagePath: any(named: 'imagePath'),
        instagramUrl: any(named: 'instagramUrl'),
      ),
    ).thenAnswer(
      (_) async => const SalonService(
        id: 'sv-1',
        branchId: 'br-1',
        name: 'Haircut',
        slug: 'haircut',
        gender: 'unisex',
        price: 300,
        durationMinutes: 30,
        status: 'active',
        sortOrder: 0,
      ),
    );

    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MG Road').last);
    await tester.pump();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hair').last);
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Haircut');
    await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '300');
    await tester.enterText(find.widgetWithText(TextFormField, 'Duration (min)'), '30');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => serviceRepository.createService(
        branchId: 'br-1',
        categoryId: 'cat-1',
        name: 'Haircut',
        description: '',
        gender: 'unisex',
        price: '300',
        durationMinutes: 30,
        status: 'active',
        imagePath: null,
        instagramUrl: '',
      ),
    ).called(1);
  });

  testWidgets('offers a tap-to-add-photo affordance for a new service with no image yet', (tester) async {
    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.add_a_photo), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('submits the entered Instagram URL when creating a service', (tester) async {
    when(
      () => serviceRepository.createService(
        branchId: any(named: 'branchId'),
        categoryId: any(named: 'categoryId'),
        name: any(named: 'name'),
        description: any(named: 'description'),
        gender: any(named: 'gender'),
        price: any(named: 'price'),
        durationMinutes: any(named: 'durationMinutes'),
        status: any(named: 'status'),
        imagePath: any(named: 'imagePath'),
        instagramUrl: any(named: 'instagramUrl'),
      ),
    ).thenAnswer(
      (_) async => const SalonService(
        id: 'sv-1',
        branchId: 'br-1',
        name: 'Haircut',
        slug: 'haircut',
        gender: 'unisex',
        price: 300,
        durationMinutes: 30,
        status: 'active',
        sortOrder: 0,
      ),
    );

    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MG Road').last);
    await tester.pump();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hair').last);
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Haircut');
    await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '300');
    await tester.enterText(find.widgetWithText(TextFormField, 'Duration (min)'), '30');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Instagram post/reel URL (optional)'),
      'https://www.instagram.com/reel/Cabc123/',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => serviceRepository.createService(
        branchId: 'br-1',
        categoryId: 'cat-1',
        name: 'Haircut',
        description: '',
        gender: 'unisex',
        price: '300',
        durationMinutes: 30,
        status: 'active',
        imagePath: null,
        instagramUrl: 'https://www.instagram.com/reel/Cabc123/',
      ),
    ).called(1);
  });

  testWidgets('editing a service with an existing image offers Remove photo, and removing it sends removeImage', (tester) async {
    when(
      () => serviceRepository.updateService(
        'sv-1',
        branchId: any(named: 'branchId'),
        categoryId: any(named: 'categoryId'),
        name: any(named: 'name'),
        description: any(named: 'description'),
        gender: any(named: 'gender'),
        price: any(named: 'price'),
        durationMinutes: any(named: 'durationMinutes'),
        status: any(named: 'status'),
        imagePath: any(named: 'imagePath'),
        instagramUrl: any(named: 'instagramUrl'),
        removeImage: any(named: 'removeImage'),
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
        status: 'active',
        sortOrder: 0,
      ),
    );
    when(() => serviceRepository.serviceDetails('sv-1')).thenAnswer(
      (_) async => const SalonService(
        id: 'sv-1',
        branchId: 'br-1',
        category: ServiceCategory(id: 'cat-1', branchId: 'br-1', name: 'Hair', slug: 'hair', status: 'active', sortOrder: 0),
        name: 'Haircut',
        slug: 'haircut',
        gender: 'unisex',
        price: 300,
        durationMinutes: 30,
        imageUrl: 'https://cdn.example.test/services/haircut.jpg',
        status: 'active',
        sortOrder: 0,
      ),
    );

    await tester.pumpWidget(buildApp());
    router.push('/form/sv-1');
    await tester.pump();
    await tester.pump();

    expect(find.text('Remove photo'), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo), findsNothing);

    await tester.tap(find.text('Remove photo'));
    await tester.pump();

    expect(find.byIcon(Icons.add_a_photo), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => serviceRepository.updateService(
        'sv-1',
        branchId: 'br-1',
        categoryId: 'cat-1',
        name: 'Haircut',
        description: '',
        gender: 'unisex',
        price: '300.00',
        durationMinutes: 30,
        status: 'active',
        imagePath: null,
        instagramUrl: '',
        removeImage: true,
      ),
    ).called(1);
  });
}
