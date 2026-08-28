import '../../../../core/network/api_client.dart';
import '../models/customer_profile.dart';

/// Talks to `GET|PUT /customer/profile`. `tenantSlug` is only needed when a
/// customer has profiles in more than one salon — see CUSTOMER_ARCHITECTURE.md.
class ProfileRepository {
  ProfileRepository(this._client);

  final ApiClient _client;

  Future<CustomerProfile> show() async {
    final data = await _client.get<Map<String, dynamic>>('/customer/profile');
    return CustomerProfile.fromJson(data);
  }

  Future<CustomerProfile> update({
    required String name,
    required String phone,
    String? countryCode,
    String? email,
    String? gender,
    String? dateOfBirth,
    String? address,
  }) async {
    final data = await _client.put<Map<String, dynamic>>(
      '/customer/profile',
      data: {
        'name': name,
        'phone': phone,
        if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
        if (email != null && email.isNotEmpty) 'email': email,
        if (gender != null && gender.isNotEmpty) 'gender': gender,
        if (dateOfBirth != null && dateOfBirth.isNotEmpty) 'date_of_birth': dateOfBirth,
        if (address != null && address.isNotEmpty) 'address': address,
      },
    );
    return CustomerProfile.fromJson(data);
  }
}
