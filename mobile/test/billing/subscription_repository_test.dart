import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/owner/billing/data/repositories/subscription_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;

  setUp(() {
    client = MockApiClient();
  });

  group('SubscriptionRepository.checkout', () {
    test('sends only plan_id — never an amount/price the client could tamper with', () async {
      when(
        () => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => {
          'payment_id': 'pay-1',
          'idempotency_key': 'idem-1',
          'gateway': 'razorpay',
          'gateway_key': 'k',
          'gateway_order_id': 'order-1',
          'amount': '500.00',
          'currency': 'INR',
          'plan': {'id': 'pl-1', 'name': 'Salon Basic', 'code': 'SALON_BASIC'},
        },
      );

      await SubscriptionRepository(client).checkout('pl-1');

      final captured = verify(
        () => client.post<Map<String, dynamic>>('/subscription/checkout', data: captureAny(named: 'data'), headers: any(named: 'headers')),
      ).captured.single as Map<String, dynamic>;
      expect(captured.keys, ['plan_id']);
      expect(captured['plan_id'], 'pl-1');
    });

    test('an idempotency key is sent as a header, not in the body', () async {
      when(
        () => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => {
          'payment_id': 'pay-1',
          'idempotency_key': 'retry-key',
          'gateway': 'razorpay',
          'amount': '500.00',
          'currency': 'INR',
          'plan': {'id': 'pl-1', 'name': 'Salon Basic', 'code': 'SALON_BASIC'},
        },
      );

      await SubscriptionRepository(client).checkout('pl-1', idempotencyKey: 'retry-key');

      final headers = verify(
        () => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'), headers: captureAny(named: 'headers')),
      ).captured.single as Map<String, dynamic>;
      expect(headers['Idempotency-Key'], 'retry-key');
    });
  });

  group('SubscriptionRepository.show/plans/payments/invoices', () {
    test('show() calls GET /subscription', () async {
      when(() => client.get<Map<String, dynamic>>('/subscription')).thenAnswer(
        (_) async => {'id': 's1', 'status': 'active', 'cancel_at_period_end': false, 'has_business_access': true},
      );
      final subscription = await SubscriptionRepository(client).show();
      expect(subscription.status, 'active');
    });

    test('plans() calls GET /subscription/plans', () async {
      when(() => client.get<List<dynamic>>('/subscription/plans')).thenAnswer((_) async => []);
      final plans = await SubscriptionRepository(client).plans();
      expect(plans, isEmpty);
      verify(() => client.get<List<dynamic>>('/subscription/plans')).called(1);
    });
  });
}
