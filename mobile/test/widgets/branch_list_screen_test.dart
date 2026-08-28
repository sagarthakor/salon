import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/branches/presentation/providers/owner_branch_providers.dart';
import 'package:salon_customer/features/owner/branches/presentation/screens/branch_list_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';

import '../support/fakes.dart';

void main() {
  late MockOwnerBranchRepository branchRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ownerBranchRepositoryProvider.overrideWithValue(branchRepository),
      ],
      child: const MaterialApp(home: BranchListScreen()),
    );
  }

  setUp(() {
    branchRepository = MockOwnerBranchRepository();
  });

  testWidgets('lists branches with an Active/Inactive chip and their address', (tester) async {
    when(() => branchRepository.list()).thenAnswer(
      (_) async => const [
        Branch(
          id: 'br-1',
          name: 'MG Road',
          slug: 'mg-road',
          address: Address(line1: '12 MG Road', city: 'Bengaluru'),
          timezone: 'Asia/Kolkata',
          status: 'active',
        ),
        Branch(id: 'br-2', name: 'Whitefield', slug: 'whitefield', address: Address(), timezone: 'Asia/Kolkata', status: 'inactive'),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('MG Road'), findsOneWidget);
    expect(find.text('12 MG Road, Bengaluru'), findsOneWidget);
    expect(find.text('Whitefield'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('shows an empty state prompting to add a branch when there are none', (tester) async {
    when(() => branchRepository.list()).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No branches yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('shows an error view with retry when branches fail to load', (tester) async {
    when(() => branchRepository.list()).thenThrow(const ApiException(message: 'Could not load branches.', type: ApiErrorType.network));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
  });
}
