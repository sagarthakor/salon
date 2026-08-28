import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/salon_branch_selection_screen.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';

import '../support/fakes.dart';

/// Step between the Customer Dashboard's salon-discovery list and the
/// existing audience-selection screen — see CUSTOMER_ARCHITECTURE.md,
/// "Customer discovery and first-time booking".
void main() {
  late MockSalonRepository salonRepository;

  Branch branchFixture(String id, String name) => Branch.fromJson({
    'id': id,
    'name': name,
    'slug': name.toLowerCase().replaceAll(' ', '-'),
    'address': null,
    'timezone': 'UTC',
    'status': 'active',
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/salons/salon-1/branches',
      routes: [
        GoRoute(
          path: '/salons/:salonId/branches',
          builder: (context, state) => SalonBranchSelectionScreen(salonId: state.pathParameters['salonId']!, salonName: 'Prime Hair Studio'),
        ),
        GoRoute(path: '/booking/audience', builder: (context, state) => const Scaffold(body: Text('Audience Selection'))),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        salonRepositoryProvider.overrideWithValue(salonRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    salonRepository = MockSalonRepository();
  });

  testWidgets('lists the salon\'s active branches and lets the customer pick one', (tester) async {
    when(() => salonRepository.branchesForSalon('salon-1')).thenAnswer(
      (_) async => [branchFixture('br-1', 'Main Branch'), branchFixture('br-2', 'Second Branch')],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Main Branch'), findsOneWidget);
    expect(find.text('Second Branch'), findsOneWidget);

    await tester.tap(find.text('Main Branch'));
    await tester.pumpAndSettle();

    expect(find.text('Audience Selection'), findsOneWidget);
  });

  testWidgets('a single-branch salon skips straight to audience selection', (tester) async {
    when(() => salonRepository.branchesForSalon('salon-1')).thenAnswer((_) async => [branchFixture('br-1', 'Main Branch')]);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Audience Selection'), findsOneWidget);
  });

  testWidgets('shows a friendly empty state when the salon has no active branches', (tester) async {
    when(() => salonRepository.branchesForSalon('salon-1')).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('This salon has no active branches right now.'), findsOneWidget);
  });
}
