import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../../../services/data/models/salon_service.dart';
import '../../../../services/data/models/service_category.dart';
import '../../data/repositories/owner_service_repository.dart';

final ownerServiceRepositoryProvider = Provider<OwnerServiceRepository>(
  (ref) => OwnerServiceRepository(ref.watch(apiClientProvider)),
);

final ownerCategoriesProvider = FutureProvider<List<ServiceCategory>>((ref) {
  return ref.watch(ownerServiceRepositoryProvider).categories();
});

/// Full active service list — used by pickers (e.g. staff service
/// assignment). The dedicated Services tab uses `OwnerServiceListController`
/// for pagination/filtering.
final allServicesProvider = FutureProvider<List<SalonService>>((ref) {
  return ref.watch(ownerServiceRepositoryProvider).services(perPage: 100);
});

final serviceDetailsProvider = FutureProvider.family<SalonService, String>((ref, id) {
  return ref.watch(ownerServiceRepositoryProvider).serviceDetails(id);
});
