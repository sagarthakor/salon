import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../data/models/staff_member.dart';
import '../../data/repositories/staff_repository.dart';
import 'staff_providers.dart';

const _perPage = 20;

class StaffListState {
  const StaffListState({
    this.staff = const [],
    this.status,
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<StaffMember> staff;
  final String? status;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  StaffListState copyWith({
    List<StaffMember>? staff,
    String? status,
    bool clearStatus = false,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return StaffListState(
      staff: staff ?? this.staff,
      status: clearStatus ? null : (status ?? this.status),
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class StaffListController extends StateNotifier<StaffListState> {
  StaffListController(this._repository) : super(const StaffListState()) {
    loadFirstPage();
  }

  final StaffRepository _repository;
  int _page = 1;

  Future<void> setStatus(String? status) async {
    state = state.copyWith(status: status, clearStatus: status == null);
    await loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final staff = await _repository.list(page: _page, perPage: _perPage, status: state.status);
      state = state.copyWith(staff: staff, isLoadingFirstPage: false, hasMore: staff.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _repository.list(page: _page + 1, perPage: _perPage, status: state.status);
      _page += 1;
      state = state.copyWith(staff: [...state.staff, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }
}

final staffListControllerProvider = StateNotifierProvider.autoDispose<StaffListController, StaffListState>((ref) {
  return StaffListController(ref.watch(staffRepositoryProvider));
});
