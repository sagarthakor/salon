import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/billing/data/models/plan.dart';
import 'package:salon_customer/features/owner/billing/presentation/providers/billing_providers.dart';
import 'package:salon_customer/features/owner/billing/presentation/screens/plan_selection_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockSubscriptionRepository repository;
  late GoRouter router;

  Widget buildApp() {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const PlanSelectionScreen()),
        GoRoute(
          path: '/owner/subscription/checkout/:planId',
          builder: (context, state) => Scaffold(body: Text('Checkout ${state.pathParameters['planId']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        subscriptionRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    repository = MockSubscriptionRepository();
  });

  testWidgets('lists real plans from the backend with their real price, never a hard-coded ₹500', (tester) async {
    when(() => repository.plans()).thenAnswer(
      (_) async => const [
        Plan(id: 'pl-1', name: 'Salon Basic', code: 'SALON_BASIC', amount: 500, currency: 'INR', billingInterval: 'month', billingIntervalCount: 1, trialDays: 14, isActive: true),
        Plan(id: 'pl-2', name: 'Salon Pro', code: 'SALON_PRO', amount: 999, currency: 'INR', billingInterval: 'month', billingIntervalCount: 1, trialDays: 7, isActive: true),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Salon Basic'), findsOneWidget);
    expect(find.text('INR 500 / month'), findsOneWidget);
    expect(find.text('Salon Pro'), findsOneWidget);
    expect(find.text('INR 999 / month'), findsOneWidget);
    expect(find.text('14-day free trial'), findsOneWidget);
  });

  testWidgets('selecting a plan navigates to checkout with that plan\'s id', (tester) async {
    when(() => repository.plans()).thenAnswer(
      (_) async => const [
        Plan(id: 'pl-1', name: 'Salon Basic', code: 'SALON_BASIC', amount: 500, currency: 'INR', billingInterval: 'month', billingIntervalCount: 1, trialDays: 14, isActive: true),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    expect(find.text('Checkout pl-1'), findsOneWidget);
  });

  testWidgets('shows an empty state when no plans are available', (tester) async {
    when(() => repository.plans()).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No plans are available right now.'), findsOneWidget);
  });
}
