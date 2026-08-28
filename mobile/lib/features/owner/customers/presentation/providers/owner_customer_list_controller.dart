import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../profile/data/models/customer_profile.dart';
import '../../data/repositories/owner_customer_repository.dart';
import 'owner_customer_providers.dart';

const _perPage = 20;

class OwnerCustomerListState {
  const OwnerCustomerListState({
    this.customers = const [],
    this.search = '',
    this.status,
    this.gender,
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<CustomerProfile> customers;
  final String search;
  final String? status;
  final String? gender;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  OwnerCustomerListState copyWith({
    List<CustomerProfile>? customers,
    String? search,
    String? status,
    bool clearStatus = false,
    String? gender,
    bool clearGender = false,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return OwnerCustomerListState(
      customers: customers ?? this.customers,
      search: search ?? this.search,
      status: clearStatus ? null : (status ?? this.status),
      gender: clearGender ? null : (gender ?? this.gender),
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class OwnerCustomerListController extends StateNotifier<OwnerCustomerListState> {
  OwnerCustomerListController(this._repository) : super(const OwnerCustomerListState()) {
    loadFirstPage();
  }

  final OwnerCustomerRepository _repository;
  int _page = 1;

  Future<void> setSearch(String search) async {
    state = state.copyWith(search: search);
    await loadFirstPage();
  }

  Future<void> setFilters({String? status, String? gender}) async {
    state = state.copyWith(status: status, clearStatus: status == null, gender: gender, clearGender: gender == null);
    await loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final customers = await _fetch(_page);
      state = state.copyWith(customers: customers, isLoadingFirstPage: false, hasMore: customers.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _fetch(_page + 1);
      _page += 1;
      state = state.copyWith(customers: [...state.customers, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }

  Future<List<CustomerProfile>> _fetch(int page) {
    return _repository.list(page: page, perPage: _perPage, search: state.search, status: state.status, gender: state.gender);
  }
}

final ownerCustomerListControllerProvider =
    StateNotifierProvider.autoDispose<OwnerCustomerListController, OwnerCustomerListState>((ref) {
      return OwnerCustomerListController(ref.watch(ownerCustomerRepositoryProvider));
    });
