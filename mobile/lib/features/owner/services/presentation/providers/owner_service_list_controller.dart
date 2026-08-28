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
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<SalonService> services;
  final String? categoryId;
  final String? branchId;
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

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final services = await _repository.services(page: _page, perPage: _perPage, categoryId: state.categoryId, branchId: state.branchId);
      state = state.copyWith(services: services, isLoadingFirstPage: false, hasMore: services.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _repository.services(page: _page + 1, perPage: _perPage, categoryId: state.categoryId, branchId: state.branchId);
      _page += 1;
      state = state.copyWith(services: [...state.services, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }
}

final ownerServiceListControllerProvider =
    StateNotifierProvider.autoDispose<OwnerServiceListController, OwnerServiceListState>((ref) {
      return OwnerServiceListController(ref.watch(ownerServiceRepositoryProvider));
    });
