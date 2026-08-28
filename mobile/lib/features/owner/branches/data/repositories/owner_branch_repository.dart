import '../../../../../core/network/api_client.dart';
import '../../../../salon/data/models/branch.dart';
import '../models/branch_working_hour_entry.dart';

/// Talks to the Phase 2 branch APIs (`/branches*`) from the owner side.
class OwnerBranchRepository {
  OwnerBranchRepository(this._client);

  final ApiClient _client;

  Future<List<Branch>> list() async {
    final data = await _client.get<List<dynamic>>('/branches');
    return data.map((b) => Branch.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<Branch> details(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/branches/$id');
    return Branch.fromJson(data);
  }

  Future<Branch> create({
    required String name,
    String? phone,
    String? email,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? timezone,
    String? status,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/branches',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (addressLine1 != null && addressLine1.isNotEmpty) 'address_line_1': addressLine1,
        if (city != null && city.isNotEmpty) 'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        if (country != null && country.isNotEmpty) 'country': country,
        if (postalCode != null && postalCode.isNotEmpty) 'postal_code': postalCode,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        'status': ?status,
      },
    );
    return Branch.fromJson(data);
  }

  Future<Branch> update(
    String id, {
    required String name,
    String? phone,
    String? email,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? timezone,
    String? status,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/branches/$id',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (addressLine1 != null && addressLine1.isNotEmpty) 'address_line_1': addressLine1,
        if (city != null && city.isNotEmpty) 'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        if (country != null && country.isNotEmpty) 'country': country,
        if (postalCode != null && postalCode.isNotEmpty) 'postal_code': postalCode,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        'status': ?status,
      },
    );
    return Branch.fromJson(data);
  }

  Future<void> delete(String id) => _client.delete<dynamic>('/branches/$id');

  Future<List<BranchWorkingHourEntry>> workingHours(String branchId) async {
    final data = await _client.get<List<dynamic>>('/branches/$branchId/working-hours');
    return data.map((h) => BranchWorkingHourEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  Future<List<BranchWorkingHourEntry>> updateWorkingHours(String branchId, List<BranchWorkingHourEntry> hours) async {
    final data = await _client.put<List<dynamic>>(
      '/branches/$branchId/working-hours',
      data: {'hours': hours.map((h) => h.toJson()).toList()},
    );
    return data.map((h) => BranchWorkingHourEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  Future<List<BranchHolidayEntry>> holidays(String branchId) async {
    final data = await _client.get<List<dynamic>>('/branches/$branchId/holidays');
    return data.map((h) => BranchHolidayEntry.fromJson(h as Map<String, dynamic>)).toList();
  }

  Future<BranchHolidayEntry> createHoliday(String branchId, {required String holidayDate, required String name}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/branches/$branchId/holidays',
      data: {'holiday_date': holidayDate, 'name': name},
    );
    return BranchHolidayEntry.fromJson(data);
  }

  Future<BranchHolidayEntry> updateHoliday(
    String branchId,
    String holidayId, {
    required String holidayDate,
    required String name,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/branches/$branchId/holidays/$holidayId',
      data: {'holiday_date': holidayDate, 'name': name},
    );
    return BranchHolidayEntry.fromJson(data);
  }

  Future<void> deleteHoliday(String branchId, String holidayId) =>
      _client.delete<dynamic>('/branches/$branchId/holidays/$holidayId');
}
