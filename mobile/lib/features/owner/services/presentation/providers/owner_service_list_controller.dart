import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../services/data/models/salon_service.dart';
import '../../data/repositories/owner_service_repository.dart';
import 'owner_service_providers.dart';

const _perPage = 20;

class OwnerServiceListState {
  const OwnerServiceListState({
    this.services = const [],
    this.categoryId,
    this.branchId,
    this.audience,
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<SalonService> services;
  final String? categoryId;
  final String? branchId;

  /// `male`/`female`/`unisex`/`kids`, or `null` for "all" — the owner's
  /// Men/Women/Unisex/Kids grouping on the Services screen. See
  /// MASTER_CATALOG_ARCHITECTURE.md.
  final String? audience;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  OwnerServiceListState copyWith({
    List<SalonService>? services,
    String? categoryId,
    bool clearCategoryId = false,
    String? branchId,
    bool clearBranchId = false,
    String? audience,
    bool clearAudience = false,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return OwnerServiceListState(
      services: services ?? this.services,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      branchId: clearBranchId ? null : (branchId ?? this.branchId),
      audience: clearAudience ? null : (audience ?? this.audience),
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class OwnerServiceListController extends StateNotifier<OwnerServiceListState> {
  OwnerServiceListController(this._repository) : super(const OwnerServiceListState()) {
    loadFirstPage();
  }

  final OwnerServiceRepository _repository;
  int _page = 1;

  Future<void> setCategory(String? categoryId) async {
    state = state.copyWith(categoryId: categoryId, clearCategoryId: categoryId == null);
    await loadFirstPage();
  }

  Future<void> setAudience(String? audience) async {
    state = state.copyWith(audience: audience, clearAudience: audience == null);
    await loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final services = await _repository.services(
        page: _page,
        perPage: _perPage,
        categoryId: state.categoryId,
        branchId: state.branchId,
        audience: state.audience,
      );
      state = state.copyWith(services: services, isLoadingFirstPage: false, hasMore: services.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _repository.services(
        page: _page + 1,
        perPage: _perPage,
        categoryId: state.categoryId,
        branchId: state.branchId,
        audience: state.audience,
      );
      _page += 1;
      state = state.copyWith(services: [...state.services, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }

  /// Flips a service's ON/OFF state in place — the owner's "quick enable/
  /// disable" action from the Services list, never requiring the edit form.
  /// Reuses the existing full `updateService()` call (the backend has no
  /// separate toggle endpoint) with every other field carried over
  /// unchanged from the service already held in memory.
  Future<void> toggleStatus(SalonService service) async {
    final category = service.category;
    if (category == null) return;
    final newStatus = service.isActive ? 'inactive' : 'active';
    final updated = await _repository.updateService(
      service.id,
      branchId: service.branchId,
      categoryId: category.id,
      name: service.name,
      description: service.description,
      gender: service.gender,
      price: service.price.toString(),
      durationMinutes: service.durationMinutes,
      status: newStatus,
      instagramUrl: service.instagramUrl,
    );
    state = state.copyWith(services: [for (final s in state.services) s.id == service.id ? updated : s]);
  }
}

final ownerServiceListControllerProvider =
    StateNotifierProvider.autoDispose<OwnerServiceListController, OwnerServiceListState>((ref) {
      return OwnerServiceListController(ref.watch(ownerServiceRepositoryProvider));
    });
