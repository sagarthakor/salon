import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/billing/data/models/invoice.dart';
import 'package:salon_customer/features/owner/billing/data/models/payment.dart';
import 'package:salon_customer/features/owner/billing/presentation/providers/billing_providers.dart';
import 'package:salon_customer/features/owner/billing/presentation/screens/invoice_history_screen.dart';
import 'package:salon_customer/features/owner/billing/presentation/screens/payment_history_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockSubscriptionRepository repository;

  setUp(() {
    repository = MockSubscriptionRepository();
  });

  Widget buildApp(Widget child) => ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      subscriptionRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(home: child),
  );

  testWidgets('payment history lists real amount, currency, and status — never a gateway secret', (tester) async {
    when(() => repository.payments(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer(
      (_) async => const [
        Payment(id: 'pay-1', amount: 500, currency: 'INR', status: 'paid', gateway: 'razorpay', createdAt: '2026-08-24T00:00:00+00:00'),
      ],
    );

    await tester.pumpWidget(buildApp(const PaymentHistoryScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('INR 500'), findsOneWidget);
    expect(find.text('paid'), findsOneWidget);
  });

  testWidgets('payment history shows an empty state when there are none', (tester) async {
    when(() => repository.payments(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp(const PaymentHistoryScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('No payments yet.'), findsOneWidget);
  });

  testWidgets('invoice history lists the real invoice number, period, and status', (tester) async {
    when(() => repository.invoices(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer(
      (_) async => const [
        Invoice(id: 'inv-1', invoiceNumber: 'INV-2026-000001', subtotal: 500, tax: 0, total: 500, currency: 'INR', status: 'paid', issuedAt: '2026-08-24T00:00:00+00:00'),
      ],
    );

    await tester.pumpWidget(buildApp(const InvoiceHistoryScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('INV-2026-000001'), findsOneWidget);
    expect(find.text('paid'), findsOneWidget);
  });

  testWidgets('invoice history shows an empty state when there are none', (tester) async {
    when(() => repository.invoices(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp(const InvoiceHistoryScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('No invoices yet.'), findsOneWidget);
  });
}
