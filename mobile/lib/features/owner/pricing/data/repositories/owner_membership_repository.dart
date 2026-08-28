import '../../../../../core/network/api_client.dart';
import '../../../../membership/data/models/customer_membership.dart';

/// Talks to the Phase 12 owner customer-membership APIs (`/memberships*`).
class OwnerMembershipRepository {
  OwnerMembershipRepository(this._client);

  final ApiClient _client;

  Future<List<CustomerMembership>> list({int page = 1, int perPage = 20, String? status, bool expiringSoon = false}) async {
    final data = await _client.get<List<dynamic>>(
      '/memberships',
      queryParameters: {'page': page, 'per_page': perPage, 'status': ?status, if (expiringSoon) 'expiring_soon': 1},
    );
    return data.map((m) => CustomerMembership.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<CustomerMembership> grant({required String customerId, required String membershipPlanId}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/memberships/grant',
      data: {'customer_id': customerId, 'membership_plan_id': membershipPlanId},
    );
    return CustomerMembership.fromJson(data);
  }

  Future<CustomerMembership> cancel(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/memberships/$id/cancel');
    return CustomerMembership.fromJson(data);
  }
}
