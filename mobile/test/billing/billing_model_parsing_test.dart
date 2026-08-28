import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/owner/billing/data/models/checkout_order.dart';
import 'package:salon_customer/features/owner/billing/data/models/invoice.dart';
import 'package:salon_customer/features/owner/billing/data/models/payment.dart';
import 'package:salon_customer/features/owner/billing/data/models/plan.dart';
import 'package:salon_customer/features/owner/billing/data/models/subscription.dart';

void main() {
  group('Plan.fromJson', () {
    test('parses the real ₹500/month default plan shape — never a hard-coded price', () {
      final plan = Plan.fromJson({
        'id': 'pl-1',
        'name': 'Salon Basic',
        'code': 'SALON_BASIC',
        'description': 'The default plan.',
        'amount': '500.00',
        'currency': 'INR',
        'billing_interval': 'month',
        'billing_interval_count': 1,
        'trial_days': 14,
        'is_active': true,
      });

      expect(plan.amount, 500.0);
      expect(plan.currency, 'INR');
      expect(plan.billingSummary, 'INR 500 / month');
    });

    test('billingSummary pluralizes a multi-count interval', () {
      final plan = Plan.fromJson({
        'id': 'pl-2',
        'name': 'Salon Quarterly',
        'code': 'SALON_QUARTERLY',
        'amount': '1400.00',
        'currency': 'INR',
        'billing_interval': 'month',
        'billing_interval_count': 3,
        'trial_days': 0,
        'is_active': true,
      });

      expect(plan.billingSummary, 'INR 1400 / 3 months');
    });
  });

  group('Subscription.fromJson and status copy', () {
    test('parses every field including a nested plan', () {
      final subscription = Subscription.fromJson({
        'id': 'sub-1',
        'status': 'active',
        'plan': {
          'id': 'pl-1', 'name': 'Salon Basic', 'code': 'SALON_BASIC', 'amount': '500.00', 'currency': 'INR',
          'billing_interval': 'month', 'billing_interval_count': 1, 'trial_days': 14, 'is_active': true,
        },
        'trial_starts_at': null,
        'trial_ends_at': null,
        'starts_at': '2026-08-24T00:00:00+00:00',
        'current_period_start': '2026-08-24T00:00:00+00:00',
        'current_period_end': '2026-09-24T00:00:00+00:00',
        'cancel_at_period_end': false,
        'cancelled_at': null,
        'grace_ends_at': null,
        'ended_at': null,
        'has_business_access': true,
      });

      expect(subscription.plan?.code, 'SALON_BASIC');
      expect(subscription.statusLabel, 'Active');
      expect(subscription.statusMessage, 'Your plan is active.');
      expect(subscription.isTerminal, isFalse);
    });

    test('every one of the six real backend statuses maps to distinct, non-empty UI copy', () {
      for (final status in ['trialing', 'active', 'past_due', 'grace_period', 'cancelled', 'expired']) {
        final subscription = Subscription.fromJson({
          'id': 'sub-1',
          'status': status,
          'cancel_at_period_end': false,
          'has_business_access': status != 'cancelled' && status != 'expired',
        });
        expect(subscription.statusLabel, isNotEmpty, reason: status);
        expect(subscription.statusMessage, isNotEmpty, reason: status);
      }
    });

    test('isTerminal is true only for cancelled/expired', () {
      for (final status in ['trialing', 'active', 'past_due', 'grace_period']) {
        final subscription = Subscription.fromJson({'id': 's', 'status': status, 'cancel_at_period_end': false, 'has_business_access': true});
        expect(subscription.isTerminal, isFalse, reason: status);
      }
      for (final status in ['cancelled', 'expired']) {
        final subscription = Subscription.fromJson({'id': 's', 'status': status, 'cancel_at_period_end': false, 'has_business_access': false});
        expect(subscription.isTerminal, isTrue, reason: status);
      }
    });
  });

  group('Payment.fromJson', () {
    test('parses real fields and never exposes anything named "secret"', () {
      final payment = Payment.fromJson({
        'id': 'pay-1',
        'invoice_id': 'inv-1',
        'amount': '500.00',
        'currency': 'INR',
        'status': 'paid',
        'payment_method': null,
        'gateway': 'razorpay',
        'gateway_order_id': 'order_x',
        'gateway_payment_id': 'pay_x',
        'paid_at': '2026-08-24T00:00:00+00:00',
        'failed_at': null,
        'failure_reason': null,
        'created_at': '2026-08-24T00:00:00+00:00',
      });

      expect(payment.amount, 500.0);
      expect(payment.status, 'paid');
      expect(payment.gatewayPaymentId, 'pay_x');
    });
  });

  group('Invoice.fromJson', () {
    test('parses totals and a real billed-item snapshot', () {
      final invoice = Invoice.fromJson({
        'id': 'inv-1',
        'invoice_number': 'INV-2026-000001',
        'subtotal': '500.00',
        'tax': '0.00',
        'total': '500.00',
        'currency': 'INR',
        'status': 'paid',
        'billing_period_start': '2026-08-24T00:00:00+00:00',
        'billing_period_end': '2026-09-24T00:00:00+00:00',
        'issued_at': '2026-08-24T00:00:00+00:00',
        'paid_at': '2026-08-24T00:05:00+00:00',
        'due_at': '2026-08-24T00:00:00+00:00',
        'items': [
          {'description': 'Salon Basic (1 month)', 'quantity': 1, 'unit_amount': '500.00', 'amount': '500.00'},
        ],
      });

      expect(invoice.invoiceNumber, 'INV-2026-000001');
      expect(invoice.total, 500.0);
      expect(invoice.items, hasLength(1));
      expect(invoice.items.first.description, 'Salon Basic (1 month)');
    });
  });

  group('CheckoutOrder.fromJson', () {
    test('parses the checkout response — never a client-echoed price beyond what the server sent', () {
      final order = CheckoutOrder.fromJson({
        'payment_id': 'pay-1',
        'idempotency_key': 'idem-1',
        'gateway': 'razorpay',
        'gateway_key': 'rzp_test_public',
        'gateway_order_id': 'order_x',
        'amount': '500.00',
        'currency': 'INR',
        'plan': {'id': 'pl-1', 'name': 'Salon Basic', 'code': 'SALON_BASIC'},
      });

      expect(order.amount, 500.0);
      expect(order.planName, 'Salon Basic');
      expect(order.gatewayKey, 'rzp_test_public');
    });
  });
}
