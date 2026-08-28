import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_service_selection_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';
import 'package:salon_customer/features/services/data/models/branch_services.dart';
import 'package:salon_customer/features/services/presentation/providers/service_providers.dart';

import '../support/fakes.dart';

void main() {
  const branch = Branch(id: 'br_1', name: 'Main Branch', slug: 'main', address: Address(), timezone: 'UTC', status: 'active');

  final branchServices = BranchServices.fromJson({
    'categories': [
      {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
    ],
    'services': [
      {
        'id': 'sv_1',
        'branch_id': 'br_1',
        'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        'name': 'Haircut',
        'slug': 'haircut',
        'gender': 'unisex',
        'price': '300.00',
        'duration_minutes': 30,
        'status': 'active',
        'sort_order': 0,
      },
      {
        'id': 'sv_2',
        'branch_id': 'br_1',
        'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        'name': 'Beard Trim',
        'slug': 'beard-trim',
        'gender': 'male',
        'price': '150.00',
        'duration_minutes': 20,
        'status': 'active',
        'sort_order': 1,
      },
    ],
  });

  Widget buildApp(MockServiceRepository serviceRepository) {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        serviceRepositoryProvider.overrideWithValue(serviceRepository),
        selectedBranchProvider.overrideWith((ref) => branch),
      ],
      child: const MaterialApp(home: BookingServiceSelectionScreen()),
    );
  }

  testWidgets('lists services grouped by category and lets the customer select more than one', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hair'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('Beard Trim'), findsOneWidget);
    expect(find.text('Select at least one service'), findsOneWidget);

    await tester.tap(find.text('Haircut'));
    await tester.pump();

    expect(find.textContaining('1 service(s)'), findsOneWidget);
    expect(find.textContaining('₹300'), findsWidgets);

    await tester.tap(find.text('Beard Trim'));
    await tester.pump();

    expect(find.textContaining('2 service(s)'), findsOneWidget);
    expect(find.textContaining('₹450'), findsWidgets);

    final nextButtonFinder = find.widgetWithText(ElevatedButton, 'Next');
    final nextButton = tester.widget<ElevatedButton>(nextButtonFinder);
    expect(nextButton.onPressed, isNotNull);
  });

  testWidgets('shows an empty state when the branch has no bookable services', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer(
      (_) async => BranchServices.fromJson({'categories': <dynamic>[], 'services': <dynamic>[]}),
    );

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    expect(find.text('This branch has no bookable services yet.'), findsOneWidget);
  });
}
