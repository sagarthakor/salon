import '../../../../core/network/api_client.dart';
import '../models/branch_services.dart';

/// Talks to `GET /branches/{branch}/services`.
class ServiceRepository {
  ServiceRepository(this._client);

  final ApiClient _client;

  Future<BranchServices> forBranch(String branchId) async {
    final data = await _client.get<Map<String, dynamic>>('/branches/$branchId/services');
    return BranchServices.fromJson(data);
  }
}
