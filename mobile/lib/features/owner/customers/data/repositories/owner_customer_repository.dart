import '../../../../../core/network/api_client.dart';
import '../../../../profile/data/models/customer_profile.dart';
import '../models/customer_note_entry.dart';
import '../models/customer_summary.dart';

/// Talks to the Phase 5 customer APIs (`/customers*`) from the owner side.
class OwnerCustomerRepository {
  OwnerCustomerRepository(this._client);

  final ApiClient _client;

  Future<List<CustomerProfile>> list({int page = 1, int perPage = 20, String? search, String? status, String? gender}) async {
    final data = await _client.get<List<dynamic>>(
      '/customers',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        if (search != null && search.isNotEmpty) 'search': search,
        'status': ?status,
        'gender': ?gender,
      },
    );
    return data.map((c) => CustomerProfile.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<CustomerProfile> details(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/customers/$id');
    return CustomerProfile.fromJson(data);
  }

  Future<CustomerProfile> create({
    required String name,
    required String phone,
    String? countryCode,
    String? email,
    String? gender,
    String? dateOfBirth,
    String? address,
    String? status,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customers',
      data: {
        'name': name,
        'phone': phone,
        if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
        if (email != null && email.isNotEmpty) 'email': email,
        'gender': ?gender,
        'date_of_birth': ?dateOfBirth,
        if (address != null && address.isNotEmpty) 'address': address,
        'status': ?status,
      },
    );
    return CustomerProfile.fromJson(data);
  }

  Future<CustomerProfile> update(
    String id, {
    required String name,
    required String phone,
    String? countryCode,
    String? email,
    String? gender,
    String? dateOfBirth,
    String? address,
    String? status,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/customers/$id',
      data: {
        'name': name,
        'phone': phone,
        if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
        if (email != null && email.isNotEmpty) 'email': email,
        'gender': ?gender,
        'date_of_birth': ?dateOfBirth,
        if (address != null && address.isNotEmpty) 'address': address,
        'status': ?status,
      },
    );
    return CustomerProfile.fromJson(data);
  }

  Future<void> delete(String id) => _client.delete<dynamic>('/customers/$id');

  Future<CustomerSummary> summary(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/customers/$id/summary');
    return CustomerSummary.fromJson(data['summary'] as Map<String, dynamic>);
  }

  Future<List<CustomerNoteEntry>> notes(String customerId) async {
    final data = await _client.get<List<dynamic>>('/customers/$customerId/notes');
    return data.map((n) => CustomerNoteEntry.fromJson(n as Map<String, dynamic>)).toList();
  }

  Future<CustomerNoteEntry> addNote(String customerId, String body) async {
    final data = await _client.post<Map<String, dynamic>>('/customers/$customerId/notes', data: {'body': body});
    return CustomerNoteEntry.fromJson(data);
  }

  Future<CustomerNoteEntry> updateNote(String customerId, int noteId, String body) async {
    final data = await _client.patch<Map<String, dynamic>>('/customers/$customerId/notes/$noteId', data: {'body': body});
    return CustomerNoteEntry.fromJson(data);
  }

  Future<void> deleteNote(String customerId, int noteId) => _client.delete<dynamic>('/customers/$customerId/notes/$noteId');
}
