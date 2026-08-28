import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../booking/data/models/booking.dart';
import '../../../../booking/data/repositories/booking_repository.dart';

const _perPage = 20;

class OwnerBookingFilters {
  const OwnerBookingFilters({this.date, this.status, this.branchId, this.staffId, this.customerId});

  final String? date;
  final String? status;
  final String? branchId;
  final String? staffId;
  final String? customerId;

  bool get isEmpty => date == null && status == null && branchId == null && staffId == null && customerId == null;

  OwnerBookingFilters copyWith({
    String? date,
    bool clearDate = false,
    String? status,
    bool clearStatus = false,
    String? branchId,
    bool clearBranchId = false,
    String? staffId,
    bool clearStaffId = false,
    String? customerId,
    bool clearCustomerId = false,
  }) {
    return OwnerBookingFilters(
      date: clearDate ? null : (date ?? this.date),
      status: clearStatus ? null : (status ?? this.status),
      branchId: clearBranchId ? null : (branchId ?? this.branchId),
      staffId: clearStaffId ? null : (staffId ?? this.staffId),
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
    );
  }
}

class OwnerBookingsState {
  const OwnerBookingsState({
    this.filters = const OwnerBookingFilters(),
    this.bookings = const [],
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final OwnerBookingFilters filters;
  final List<Booking> bookings;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  OwnerBookingsState copyWith({
    OwnerBookingFilters? filters,
    List<Booking>? bookings,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return OwnerBookingsState(
      filters: filters ?? this.filters,
      bookings: bookings ?? this.bookings,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owner/staff booking list with server-side filters (`date`, `status`,
/// `branch_id`, `staff_id`, `customer_id`) and load-more pagination (the
/// same "did the last page come back full" heuristic as the customer app's
/// `MyBookingsController` — see MOBILE_API_INTEGRATION.md for why there's no
/// pagination metadata to read instead).
class OwnerBookingsController extends StateNotifier<OwnerBookingsState> {
  /// [initialFilters] lets a caller pin a filter for the lifetime of this
  /// controller instance — e.g. the staff app's "My Appointments" screen
  /// (`features/staff/`) always scopes to the signed-in staff member's own
  /// `staff_id` and never exposes the filter sheet to change it.
  OwnerBookingsController(this._repository, {OwnerBookingFilters initialFilters = const OwnerBookingFilters()})
    : super(OwnerBookingsState(filters: initialFilters)) {
    loadFirstPage();
  }

  final BookingRepository _repository;
  int _page = 1;

  Future<void> setFilters(OwnerBookingFilters filters) async {
    state = state.copyWith(filters: filters);
    await loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final bookings = await _fetch(_page);
      state = state.copyWith(bookings: bookings, isLoadingFirstPage: false, hasMore: bookings.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = await _fetch(_page + 1);
      _page += 1;
      state = state.copyWith(
        bookings: [...state.bookings, ...nextPage],
        isLoadingMore: false,
        hasMore: nextPage.length == _perPage,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }

  Future<List<Booking>> _fetch(int page) {
    final f = state.filters;
    return _repository.ownerBookings(
      page: page,
      perPage: _perPage,
      date: f.date,
      status: f.status,
      branchId: f.branchId,
      staffId: f.staffId,
      customerId: f.customerId,
    );
  }
}
