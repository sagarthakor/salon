import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/billing/data/models/checkout_order.dart';
import 'package:salon_customer/features/owner/billing/data/models/subscription.dart';
import 'package:salon_customer/features/owner/billing/presentation/providers/billing_providers.dart';
import 'package:salon_customer/features/owner/billing/presentation/screens/payment_checkout_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockSubscriptionRepository repository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        subscriptionRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: PaymentCheckoutScreen(planId: 'pl-1')),
    );
  }

  setUp(() {
    repository = MockSubscriptionRepository();
    when(() => repository.checkout(any(), idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer(
      (_) async => const CheckoutOrder(
        paymentId: 'pay-1',
        idempotencyKey: 'idem-1',
        gateway: 'razorpay',
        gatewayKey: 'rzp_test_key',
        gatewayOrderId: 'order-1',
        amount: 500,
        currency: 'INR',
        planName: 'Salon Basic',
      ),
    );
  });

  testWidgets('shows the real server-resolved order amount and plan name', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Salon Basic'), findsOneWidget);
    expect(find.text('INR 500'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Pay with Razorpay'), findsOneWidget);
  });

  testWidgets(
    'checking status before the backend confirms shows a waiting message, never a fabricated success',
    (tester) async {
      when(() => repository.show()).thenAnswer(
        (_) async => const Subscription(id: 's1', status: 'past_due', cancelAtPeriodEnd: false, hasBusinessAccess: true),
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text("I've completed the payment"));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining("haven't received confirmation"), findsOneWidget);
      expect(find.text('Payment successful'), findsNothing);
    },
  );

  testWidgets('checking status once the backend confirms active shows success, driven only by the server response', (tester) async {
    when(() => repository.show()).thenAnswer(
      (_) async => const Subscription(id: 's1', status: 'active', cancelAtPeriodEnd: false, hasBusinessAccess: true),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text("I've completed the payment"));
    await tester.pump();
    await tester.pump();

    expect(find.text('Payment successful'), findsOneWidget);
    expect(find.text('Your subscription is now active.'), findsOneWidget);
  });
}
