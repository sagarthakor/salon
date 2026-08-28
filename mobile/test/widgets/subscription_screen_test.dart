import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/billing/data/models/plan.dart';
import 'package:salon_customer/features/owner/billing/data/models/subscription.dart';
import 'package:salon_customer/features/owner/billing/presentation/providers/billing_providers.dart';
import 'package:salon_customer/features/owner/billing/presentation/screens/subscription_screen.dart';

import '../support/fakes.dart';

const _plan = Plan(
  id: 'pl-1',
  name: 'Salon Basic',
  code: 'SALON_BASIC',
  amount: 500,
  currency: 'INR',
  billingInterval: 'month',
  billingIntervalCount: 1,
  trialDays: 14,
  isActive: true,
);

Subscription _subscription({
  required String status,
  bool cancelAtPeriodEnd = false,
  String? trialEndsAt,
  String? currentPeriodEnd,
  String? graceEndsAt,
}) => Subscription(
  id: 'sub-1',
  status: status,
  plan: _plan,
  trialEndsAt: trialEndsAt,
  currentPeriodEnd: currentPeriodEnd,
  graceEndsAt: graceEndsAt,
  cancelAtPeriodEnd: cancelAtPeriodEnd,
  hasBusinessAccess: status != 'cancelled' && status != 'expired',
);

void main() {
  late MockSubscriptionRepository repository;
  late GoRouter router;

  Widget buildApp() {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
        GoRoute(path: '/owner/subscription/plans', builder: (context, state) => const Scaffold(body: Text('Plan selection'))),
        GoRoute(path: '/owner/subscription/payments', builder: (context, state) => const Scaffold(body: Text('Payments'))),
        GoRoute(path: '/owner/subscription/invoices', builder: (context, state) => const Scaffold(body: Text('Invoices'))),
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

  testWidgets('active subscription shows the real plan price and no renewal prompt', (tester) async {
    when(() => repository.show()).thenAnswer((_) async => _subscription(status: 'active', currentPeriodEnd: '2026-09-24T00:00:00+00:00'));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Your plan is active.'), findsOneWidget);
    expect(find.text('INR 500 / month'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Renew subscription'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel subscription'), findsOneWidget);
  });

  testWidgets('trialing subscription shows the trial message and a Subscribe now action', (tester) async {
    when(() => repository.show()).thenAnswer((_) async => _subscription(status: 'trialing', trialEndsAt: '2026-09-07T00:00:00+00:00'));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Free trial'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Subscribe now'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe now'));
    await tester.pumpAndSettle();
    expect(find.text('Plan selection'), findsOneWidget);
  });

  testWidgets('expired subscription shows a clear expired message and a Renew action — never blocked from billing', (tester) async {
    when(() => repository.show()).thenAnswer((_) async => _subscription(status: 'expired'));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Your subscription has expired. Renew to restore access.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Renew subscription'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel subscription'), findsNothing);
  });

  testWidgets('grace_period subscription shows the renew-by date and a Renew action', (tester) async {
    when(() => repository.show()).thenAnswer(
      (_) async => _subscription(status: 'grace_period', graceEndsAt: '2026-08-27T00:00:00+00:00'),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Renew required'), findsOneWidget);
    expect(find.textContaining('Renew by'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Renew subscription'), findsOneWidget);
  });

  testWidgets('a cancelled subscription shows no cancel action (already terminal)', (tester) async {
    when(() => repository.show()).thenAnswer((_) async => _subscription(status: 'cancelled'));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel subscription'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Renew subscription'), findsOneWidget);
  });

  testWidgets('a subscription already flagged cancel_at_period_end shows the flag and no duplicate cancel action', (tester) async {
    when(() => repository.show()).thenAnswer(
      (_) async => _subscription(status: 'active', cancelAtPeriodEnd: true, currentPeriodEnd: '2026-09-24T00:00:00+00:00'),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Cancels at period end'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel subscription'), findsNothing);
    expect(find.textContaining('Access ends'), findsOneWidget);
  });

  testWidgets('tapping payment/invoice history navigates to those screens', (tester) async {
    when(() => repository.show()).thenAnswer((_) async => _subscription(status: 'active'));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Payment history'));
    await tester.pumpAndSettle();
    expect(find.text('Payments'), findsOneWidget);
  });
}
