import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/customers/presentation/providers/owner_customer_providers.dart';
import 'package:salon_customer/features/owner/customers/presentation/screens/customer_list_screen.dart';
import 'package:salon_customer/features/profile/data/models/customer_profile.dart';

import '../support/fakes.dart';

void main() {
  late MockOwnerCustomerRepository customerRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ownerCustomerRepositoryProvider.overrideWithValue(customerRepository),
      ],
      child: const MaterialApp(home: CustomerListScreen()),
    );
  }

  setUp(() {
    customerRepository = MockOwnerCustomerRepository();
  });

  testWidgets('lists customers with their status', (tester) async {
    when(
      () => customerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: any(named: 'search'),
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer(
      (_) async => const [
        CustomerProfile(id: 'c1', name: 'Anita Rao', phone: '9000000001', status: 'active'),
        CustomerProfile(id: 'c2', name: 'Vikram Shah', phone: '9000000002', status: 'inactive'),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Anita Rao'), findsOneWidget);
    expect(find.text('9000000002'), findsOneWidget);
  });

  testWidgets('submitting the search field re-fetches with the search term', (tester) async {
    when(
      () => customerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: any(named: 'search'),
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer((_) async => const []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'anita');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    verify(
      () => customerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: 'anita',
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).called(1);
  });

  testWidgets('shows an empty state when there are no customers', (tester) async {
    when(
      () => customerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: any(named: 'search'),
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer((_) async => const []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No customers found.'), findsOneWidget);
  });
}
