import '../../../../../core/network/api_client.dart';
import '../../../../membership/data/models/membership_plan.dart';

/// Talks to the Phase 12 owner membership-plan-management APIs
/// (`/membership-plans*`).
class OwnerMembershipPlanRepository {
  OwnerMembershipPlanRepository(this._client);

  final ApiClient _client;

  Future<List<MembershipPlan>> list({int page = 1, int perPage = 20, bool? isActive}) async {
    final data = await _client.get<List<dynamic>>(
      '/membership-plans',
      queryParameters: {'page': page, 'per_page': perPage, 'is_active': ?isActive},
    );
    return data.map((p) => MembershipPlan.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<MembershipPlan> details(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/membership-plans/$id');
    return MembershipPlan.fromJson(data);
  }

  Future<MembershipPlan> create(Map<String, dynamic> payload) async {
    final data = await _client.post<Map<String, dynamic>>('/membership-plans', data: payload);
    return MembershipPlan.fromJson(data);
  }

  Future<MembershipPlan> update(String id, Map<String, dynamic> payload) async {
    final data = await _client.patch<Map<String, dynamic>>('/membership-plans/$id', data: payload);
    return MembershipPlan.fromJson(data);
  }

  Future<MembershipPlan> activate(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/membership-plans/$id/activate');
    return MembershipPlan.fromJson(data);
  }

  Future<MembershipPlan> deactivate(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/membership-plans/$id/deactivate');
    return MembershipPlan.fromJson(data);
  }

  Future<void> delete(String id) => _client.delete<dynamic>('/membership-plans/$id');
}
