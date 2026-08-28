import '../../../../../core/network/api_client.dart';
import '../models/dashboard_summary.dart';

class DashboardRepository {
  DashboardRepository(this._client);

  final ApiClient _client;

  Future<DashboardSummary> summary() async {
    final data = await _client.get<Map<String, dynamic>>('/dashboard/summary');
    return DashboardSummary.fromJson(data);
  }
}
