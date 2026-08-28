import '../../../../../core/network/api_client.dart';
import '../models/coupon.dart';

/// Talks to the Phase 12 owner coupon-management APIs (`/coupons*`).
class CouponRepository {
  CouponRepository(this._client);

  final ApiClient _client;

  Future<List<Coupon>> list({int page = 1, int perPage = 20, bool? isActive, String? search}) async {
    final data = await _client.get<List<dynamic>>(
      '/coupons',
      queryParameters: {'page': page, 'per_page': perPage, 'is_active': ?isActive, 'search': ?search},
    );
    return data.map((c) => Coupon.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<Coupon> details(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/coupons/$id');
    return Coupon.fromJson(data);
  }

  Future<Coupon> create(Map<String, dynamic> payload) async {
    final data = await _client.post<Map<String, dynamic>>('/coupons', data: payload);
    return Coupon.fromJson(data);
  }

  Future<Coupon> update(String id, Map<String, dynamic> payload) async {
    final data = await _client.patch<Map<String, dynamic>>('/coupons/$id', data: payload);
    return Coupon.fromJson(data);
  }

  Future<Coupon> activate(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/coupons/$id/activate');
    return Coupon.fromJson(data);
  }

  Future<Coupon> deactivate(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/coupons/$id/deactivate');
    return Coupon.fromJson(data);
  }

  Future<void> delete(String id) => _client.delete<dynamic>('/coupons/$id');
}
