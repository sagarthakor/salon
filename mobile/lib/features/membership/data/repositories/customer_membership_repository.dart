import '../../../../core/network/api_client.dart';
import '../models/customer_membership.dart';
import '../models/membership_checkout_order.dart';
import '../models/membership_plan.dart';

/// Talks to the customer-facing Phase 12 membership APIs. Same
/// X-Tenant-Slug convention as `SubscriptionRepository`/other customer
/// repositories with cross-tenant profiles — see
/// `ApiClient.tenantSlug`.
class CustomerMembershipRepository {
  CustomerMembershipRepository(this._client);

  final ApiClient _client;

  Future<List<MembershipPlan>> plans(String branchId) async {
    final data = await _client.get<List<dynamic>>('/branches/$branchId/membership-plans');
    return data.map((p) => MembershipPlan.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<CustomerMembership?> current() async {
    final data = await _client.get<Map<String, dynamic>?>('/customer/membership');
    return data != null ? CustomerMembership.fromJson(data) : null;
  }

  Future<MembershipCheckoutOrder> checkout(String membershipPlanId) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customer/membership/checkout',
      data: {'membership_plan_id': membershipPlanId},
    );
    return MembershipCheckoutOrder.fromJson(data);
  }

  Future<CustomerMembership> verify({
    required String paymentId,
    required String gatewayPaymentId,
    required String gatewaySignature,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customer/membership/checkout/verify',
      data: {'payment_id': paymentId, 'gateway_payment_id': gatewayPaymentId, 'gateway_signature': gatewaySignature},
    );
    return CustomerMembership.fromJson(data);
  }
}
