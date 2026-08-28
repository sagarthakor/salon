import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';

const _perPage = 20;

class MyBookingsState {
  const MyBookingsState({
    this.bookings = const [],
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<Booking> bookings;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  MyBookingsState copyWith({
    List<Booking>? bookings,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return MyBookingsState(
      bookings: bookings ?? this.bookings,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Backend list endpoints in this project don't return pagination metadata
/// (see MOBILE_API_INTEGRATION.md) — "has more" is therefore inferred from
/// whether the last page came back full (`length == perPage`), a standard
/// client-side heuristic that needs no backend change.
class MyBookingsController extends StateNotifier<MyBookingsState> {
  MyBookingsController(this._repository) : super(const MyBookingsState()) {
    loadFirstPage();
  }

  final BookingRepository _repository;
  int _page = 1;

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final bookings = await _repository.myBookings(page: _page, perPage: _perPage);
      state = MyBookingsState(bookings: bookings, isLoadingFirstPage: false, hasMore: bookings.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = await _repository.myBookings(page: _page + 1, perPage: _perPage);
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
}
