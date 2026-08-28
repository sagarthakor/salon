import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/booking/data/models/booking_pricing.dart';
import 'package:salon_customer/features/loyalty/data/models/loyalty_account.dart';
import 'package:salon_customer/features/loyalty/data/models/loyalty_transaction.dart';
import 'package:salon_customer/features/membership/data/models/customer_membership.dart';
import 'package:salon_customer/features/membership/data/models/membership_checkout_order.dart';
import 'package:salon_customer/features/membership/data/models/membership_plan.dart';
import 'package:salon_customer/features/owner/pricing/data/models/coupon.dart';

void main() {
  group('Coupon.fromJson', () {
    test('parses a percentage coupon with service/category restrictions', () {
      final coupon = Coupon.fromJson({
        'id': 'cp_1',
        'code': 'WELCOME10',
        'name': 'Welcome discount',
        'description': null,
        'discount_type': 'percentage',
        'discount_value': '10.00',
        'minimum_booking_amount': '200.00',
        'maximum_discount_amount': '100.00',
        'starts_at': null,
        'expires_at': null,
        'usage_limit': 100,
        'usage_limit_per_customer': 1,
        'usage_count': 3,
        'is_active': true,
        'first_booking_only': false,
        'service_ids': ['sv_1'],
        'category_ids': [],
      });

      expect(coupon.code, 'WELCOME10');
      expect(coupon.discountLabel, '10%');
      expect(coupon.usageCount, 3);
      expect(coupon.serviceIds, ['sv_1']);
    });

    test('a fixed_amount coupon renders a currency discount label', () {
      final coupon = Coupon.fromJson({
        'id': 'cp_2',
        'code': 'FLAT50',
        'name': 'Flat 50',
        'discount_type': 'fixed_amount',
        'discount_value': '50.00',
        'usage_count': 0,
        'is_active': true,
        'first_booking_only': false,
      });

      expect(coupon.discountLabel, '₹50');
    });
  });

  group('MembershipPlan.fromJson', () {
    test('parses a real plan', () {
      final plan = MembershipPlan.fromJson({
        'id': 'mp_1',
        'name': 'Gold',
        'code': 'GOLD',
        'description': 'Gold membership',
        'price': '999.00',
        'currency': 'INR',
        'duration_days': 30,
        'discount_type': 'percentage',
        'discount_value': '15.00',
        'maximum_discount_amount': null,
        'is_active': true,
      });

      expect(plan.name, 'Gold');
      expect(plan.price, 999.0);
      expect(plan.discountLabel, '15%');
    });
  });

  group('CustomerMembership.fromJson', () {
    test('parses with a nested plan', () {
      final membership = CustomerMembership.fromJson({
        'id': 'cm_1',
        'plan': {
          'id': 'mp_1',
          'name': 'Gold',
          'code': 'GOLD',
          'price': '999.00',
          'currency': 'INR',
          'duration_days': 30,
          'discount_type': 'percentage',
          'discount_value': '15.00',
          'is_active': true,
        },
        'status': 'active',
        'starts_at': '2026-01-01T00:00:00+00:00',
        'expires_at': '2026-02-01T00:00:00+00:00',
        'purchased_amount': '999.00',
        'currency': 'INR',
        'source': 'purchase',
        'is_currently_active': true,
      });

      expect(membership.status, 'active');
      expect(membership.plan?.name, 'Gold');
      expect(membership.isCurrentlyActive, isTrue);
    });
  });

  group('MembershipCheckoutOrder.fromJson', () {
    test('parses the checkout payload including the nested plan', () {
      final order = MembershipCheckoutOrder.fromJson({
        'payment_id': 'mpay_1',
        'idempotency_key': 'idem_1',
        'gateway': 'razorpay',
        'gateway_key': 'key_test',
        'gateway_order_id': 'order_1',
        'amount': '999.00',
        'currency': 'INR',
        'plan': {'id': 'mp_1', 'name': 'Gold', 'code': 'GOLD'},
      });

      expect(order.paymentId, 'mpay_1');
      expect(order.planName, 'Gold');
      expect(order.amount, 999.0);
    });
  });

  group('LoyaltyAccount.fromJson', () {
    test('parses balance/lifetime fields', () {
      final account = LoyaltyAccount.fromJson({
        'id': 'la_1',
        'balance': 250,
        'lifetime_earned': 400,
        'lifetime_redeemed': 150,
      });

      expect(account.balance, 250);
      expect(account.lifetimeEarned, 400);
    });
  });

  group('LoyaltyTransactionEntry.fromJson', () {
    test('a negative points value represents a redemption/expiry', () {
      final entry = LoyaltyTransactionEntry.fromJson({
        'id': 1,
        'type': 'redeem',
        'points': -100,
        'balance_after': 150,
        'description': 'Redeemed against booking bk_1',
        'booking_id': 'bk_1',
        'created_at': '2026-01-01T00:00:00+00:00',
      });

      expect(entry.points, -100);
      expect(entry.type, 'redeem');
      expect(entry.bookingId, 'bk_1');
    });
  });

  group('BookingPricing.fromJson', () {
    test('parses a full discount breakdown with messages', () {
      final pricing = BookingPricing.fromJson({
        'subtotal': '300.00',
        'coupon_code': 'WELCOME10',
        'coupon_discount': '30.00',
        'membership_discount': '0.00',
        'loyalty_points_redeemed': 20,
        'loyalty_discount': '20.00',
        'discount': '50.00',
        'tax': '0.00',
        'total': '250.00',
        'messages': ['Coupon WELCOME10 applied.'],
      });

      expect(pricing.couponDiscount, 30.0);
      expect(pricing.loyaltyPointsRedeemed, 20);
      expect(pricing.total, 250.0);
      expect(pricing.messages, ['Coupon WELCOME10 applied.']);
    });

    test('defaults messages to an empty list when absent', () {
      final pricing = BookingPricing.fromJson({
        'subtotal': '300.00',
        'coupon_code': null,
        'coupon_discount': '0.00',
        'membership_discount': '0.00',
        'loyalty_points_redeemed': 0,
        'loyalty_discount': '0.00',
        'discount': '0.00',
        'tax': '0.00',
        'total': '300.00',
      });

      expect(pricing.messages, isEmpty);
      expect(pricing.couponCode, isNull);
    });
  });
}
