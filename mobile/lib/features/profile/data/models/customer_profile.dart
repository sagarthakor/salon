/// Mirrors `App\Http\Resources\CustomerResource` — the authenticated
/// customer's own operational profile for one salon (`GET /customer/profile`).
/// Never includes internal owner-only notes; those are not exposed to this
/// endpoint at all on the backend.
class CustomerProfile {
  const CustomerProfile({
    required this.id,
    this.userId,
    required this.name,
    required this.phone,
    this.countryCode,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.profilePhoto,
    this.address,
    required this.status,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) => CustomerProfile(
    id: json['id'] as String,
    userId: json['user_id'] as int?,
    name: json['name'] as String,
    phone: json['phone'] as String,
    countryCode: json['country_code'] as String?,
    email: json['email'] as String?,
    gender: json['gender'] as String?,
    dateOfBirth: json['date_of_birth'] as String?,
    profilePhoto: json['profile_photo'] as String?,
    address: json['address'] as String?,
    status: json['status'] as String,
  );

  final String id;
  final int? userId;
  final String name;
  final String phone;
  final String? countryCode;
  final String? email;
  final String? gender;
  final String? dateOfBirth;
  final String? profilePhoto;
  final String? address;
  final String status;
}
