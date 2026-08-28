import '../../../../../core/network/api_client.dart';
import '../../../../salon/data/models/salon.dart';

/// Talks to the Phase 2 salon APIs (`/salon`, `/salon/settings`) from the
/// owner side. Settings use the approved key/value extension point from
/// `App\Enums\SalonSettingKey` (Phase 2 config keys plus the Phase 6 booking
/// settings — slot interval, advance-booking window, buffer, cancellation
/// window) — see SALON_ARCHITECTURE.md and BOOKING_ENGINE.md.
class OwnerSalonRepository {
  OwnerSalonRepository(this._client);

  final ApiClient _client;

  Future<Salon> show() async {
    final data = await _client.get<Map<String, dynamic>>('/salon');
    return Salon.fromJson(data);
  }

  /// A freshly self-registered owner has a Tenant but no Salon yet — `show()`
  /// returns a 404 for that tenant (see requireSalon() on the backend's
  /// TenantManagementController). This is the one-time onboarding step that
  /// creates it via `POST /salon`.
  Future<Salon> create({
    required String name,
    required String genderType,
    String? description,
    String? phone,
    String? email,
    String? website,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? timezone,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/salon',
      data: {
        'name': name,
        'gender_type': genderType,
        if (description != null && description.isNotEmpty) 'description': description,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (website != null && website.isNotEmpty) 'website': website,
        if (addressLine1 != null && addressLine1.isNotEmpty) 'address_line_1': addressLine1,
        if (city != null && city.isNotEmpty) 'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        if (country != null && country.isNotEmpty) 'country': country,
        if (postalCode != null && postalCode.isNotEmpty) 'postal_code': postalCode,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
      },
    );
    return Salon.fromJson(data);
  }

  Future<Salon> update({
    required String name,
    required String genderType,
    String? description,
    String? phone,
    String? email,
    String? website,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? timezone,
    String? status,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/salon',
      data: {
        'name': name,
        'gender_type': genderType,
        if (description != null && description.isNotEmpty) 'description': description,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (website != null && website.isNotEmpty) 'website': website,
        if (addressLine1 != null && addressLine1.isNotEmpty) 'address_line_1': addressLine1,
        if (city != null && city.isNotEmpty) 'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        if (country != null && country.isNotEmpty) 'country': country,
        if (postalCode != null && postalCode.isNotEmpty) 'postal_code': postalCode,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        'status': ?status,
      },
    );
    return Salon.fromJson(data);
  }

  Future<Map<String, dynamic>> settings() => _client.get<Map<String, dynamic>>('/salon/settings');

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> settings) =>
      _client.put<Map<String, dynamic>>('/salon/settings', data: {'settings': settings});
}
