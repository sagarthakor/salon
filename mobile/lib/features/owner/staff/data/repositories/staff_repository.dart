import 'package:dio/dio.dart';

import '../../../../../core/network/api_client.dart';
import '../../../../services/data/models/salon_service.dart';
import '../models/staff_member.dart';
import '../models/staff_schedule.dart';

/// Talks to the Phase 4 staff APIs (`/staff*`) — profile CRUD, service
/// assignment, working hours, breaks, and leave. Shared by the owner surface
/// (any staff id) and the Phase 9 staff app (always its own id, resolved via
/// [me] — a client never supplies its own staff id directly, see
/// STAFF_APP_ARCHITECTURE.md).
class StaffRepository {
  StaffRepository(this._client);

  final ApiClient _client;

  /// `GET /staff/me` (Phase 9) — resolves the authenticated user's own staff
  /// profile server-side from `user_id`. Never accepts or infers a staff id
  /// client-side.
  Future<StaffMember> me() async {
    final data = await _client.get<Map<String, dynamic>>('/staff/me');
    return StaffMember.fromJson(data);
  }

  Future<List<StaffMember>> list({int page = 1, int perPage = 20, String? status, String? branchId}) async {
    final data = await _client.get<List<dynamic>>(
      '/staff',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'status': ?status,
        'branch_id': ?branchId,
      },
    );
    return data.map((s) => StaffMember.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<StaffMember> details(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/staff/$id');
    return StaffMember.fromJson(data);
  }

  Future<StaffMember> create({
    required String name,
    required String gender,
    String? phone,
    String? email,
    String? bio,
    String? joiningDate,
    String? status,
    List<String> branchIds = const [],
    String? photoPath,
  }) async {
    final fields = <String, dynamic>{
      'name': name,
      'gender': gender,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (bio != null && bio.isNotEmpty) 'bio': bio,
      'joining_date': ?joiningDate,
      'status': ?status,
      for (var i = 0; i < branchIds.length; i++) 'branch_ids[$i]': branchIds[i],
      if (photoPath != null) 'photo': await MultipartFile.fromFile(photoPath),
    };
    final data = await _client.postMultipart<Map<String, dynamic>>('/staff', fields);
    return StaffMember.fromJson(data);
  }

  Future<StaffMember> update(
    String id, {
    required String name,
    required String gender,
    String? phone,
    String? email,
    String? bio,
    String? joiningDate,
    String? status,
    List<String> branchIds = const [],
    String? photoPath,
  }) async {
    final fields = <String, dynamic>{
      'name': name,
      'gender': gender,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (bio != null && bio.isNotEmpty) 'bio': bio,
      'joining_date': ?joiningDate,
      'status': ?status,
      for (var i = 0; i < branchIds.length; i++) 'branch_ids[$i]': branchIds[i],
      if (photoPath != null) 'photo': await MultipartFile.fromFile(photoPath),
    };
    final data = await _client.postMultipart<Map<String, dynamic>>('/staff/$id', fields, httpMethodOverride: 'PUT');
    return StaffMember.fromJson(data);
  }

  Future<void> delete(String id) => _client.delete<dynamic>('/staff/$id');

  Future<List<SalonService>> services(String staffId) async {
    final data = await _client.get<List<dynamic>>('/staff/$staffId/services');
    return data.map((s) => SalonService.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<SalonService>> updateServices(String staffId, List<String> serviceIds) async {
    final data = await _client.put<List<dynamic>>('/staff/$staffId/services', data: {'service_ids': serviceIds});
    return data.map((s) => SalonService.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<StaffWorkingHourEntry>> workingHours(String staffId) async {
    final data = await _client.get<List<dynamic>>('/staff/$staffId/working-hours');
    return data.map((h) => StaffWorkingHourEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  Future<List<StaffWorkingHourEntry>> updateWorkingHours(String staffId, List<StaffWorkingHourEntry> hours) async {
    final data = await _client.put<List<dynamic>>(
      '/staff/$staffId/working-hours',
      data: {'hours': hours.map((h) => h.toJson()).toList()},
    );
    return data.map((h) => StaffWorkingHourEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  Future<List<StaffBreakEntry>> breaks(String staffId) async {
    final data = await _client.get<List<dynamic>>('/staff/$staffId/breaks');
    return data.map((b) => StaffBreakEntry.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<StaffBreakEntry> createBreak(String staffId, {required int dayOfWeek, required String startTime, required String endTime}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/staff/$staffId/breaks',
      data: {'day_of_week': dayOfWeek, 'start_time': startTime, 'end_time': endTime},
    );
    return StaffBreakEntry.fromJson(data);
  }

  Future<StaffBreakEntry> updateBreak(
    String staffId,
    int breakId, {
    required int dayOfWeek,
    required String startTime,
    required String endTime,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/staff/$staffId/breaks/$breakId',
      data: {'day_of_week': dayOfWeek, 'start_time': startTime, 'end_time': endTime},
    );
    return StaffBreakEntry.fromJson(data);
  }

  Future<void> deleteBreak(String staffId, int breakId) => _client.delete<dynamic>('/staff/$staffId/breaks/$breakId');

  Future<List<StaffLeaveEntry>> leaves(String staffId) async {
    final data = await _client.get<List<dynamic>>('/staff/$staffId/leaves');
    return data.map((l) => StaffLeaveEntry.fromJson(l as Map<String, dynamic>)).toList();
  }

  Future<StaffLeaveEntry> createLeave(String staffId, {required String startDate, required String endDate, String? reason}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/staff/$staffId/leaves',
      data: {'start_date': startDate, 'end_date': endDate, if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return StaffLeaveEntry.fromJson(data);
  }

  Future<StaffLeaveEntry> updateLeave(
    String staffId,
    int leaveId, {
    required String startDate,
    required String endDate,
    String? reason,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/staff/$staffId/leaves/$leaveId',
      data: {'start_date': startDate, 'end_date': endDate, if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return StaffLeaveEntry.fromJson(data);
  }

  Future<void> deleteLeave(String staffId, int leaveId) => _client.delete<dynamic>('/staff/$staffId/leaves/$leaveId');
}
