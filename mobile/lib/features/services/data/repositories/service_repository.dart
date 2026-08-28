import '../../../../core/network/api_client.dart';
import '../models/branch_services.dart';

/// Talks to `GET /branches/{branch}/services`.
class ServiceRepository {
  ServiceRepository(this._client);

  final ApiClient _client;

  /// [audience] (`male`/`female`/`unisex`/`kids`) narrows the catalog to one
  /// segment — the customer dashboard's "Men / Women / Unisex / Kids" entry
  /// point. Omitted entirely (never sent as an empty value) when `null`, so
  /// the full unfiltered catalog this method always returned still works.
  Future<BranchServices> forBranch(String branchId, {String? audience}) async {
    final data = await _client.get<Map<String, dynamic>>(
      '/branches/$branchId/services',
      queryParameters: {'audience': ?audience},
    );
    return BranchServices.fromJson(data);
  }
}
