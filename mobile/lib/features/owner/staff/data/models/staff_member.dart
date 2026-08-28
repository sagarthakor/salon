import '../../../../salon/data/models/branch.dart';

/// Mirrors `App\Http\Resources\StaffResource`.
class StaffMember {
  const StaffMember({
    required this.id,
    this.userId,
    required this.name,
    this.photo,
    this.phone,
    this.email,
    required this.gender,
    this.bio,
    this.joiningDate,
    required this.status,
    this.commissionType,
    this.commissionValue,
    this.branches = const [],
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    id: json['id'] as String,
    userId: json['user_id'] as int?,
    name: json['name'] as String,
    photo: json['photo'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    gender: json['gender'] as String,
    bio: json['bio'] as String?,
    joiningDate: json['joining_date'] as String?,
    status: json['status'] as String,
    commissionType: json['commission_type'] as String?,
    commissionValue: json['commission_value'] != null ? num.parse(json['commission_value'].toString()) : null,
    branches: json['branches'] is List
        ? (json['branches'] as List<dynamic>).map((b) => Branch.fromJson(b as Map<String, dynamic>)).toList()
        : const [],
  );

  final String id;
  final int? userId;
  final String name;
  final String? photo;
  final String? phone;
  final String? email;
  final String gender;
  final String? bio;
  final String? joiningDate;
  final String status;
  final String? commissionType;
  final num? commissionValue;
  final List<Branch> branches;

  bool get isActive => status == 'active';
}
